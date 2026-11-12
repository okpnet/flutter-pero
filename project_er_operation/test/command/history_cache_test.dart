import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:project_er_operation/command/command.dart';
import 'package:project_er_operation/model/model.dart';
import 'package:project_er_operation/persistence/persistence.dart';

import '../support/sample_models.dart';

CommandHistory historyOf(ErModel m, {int limit = 100}) =>
    CommandHistory(CommandContext(m, () => EntityLayouter(m)), limit: limit);

String dump(ErModel m) => PeroEncoder.encode(m);

void main() {
  group('Undo / Redo', () {
    late ErModel m;
    late CommandHistory h;
    setUp(() {
      m = ErModel.empty();
      h = historyOf(m);
    });

    test('テーブル追加(既定値: 4.2-2)のUndo/Redoで状態が完全に戻る(ID採番も)', () {
      final before = dump(m);
      final add = AddTableCommand(diagramId: m.diagrams.first.id, x: 40, y: 40);
      h.execute(add);
      final t = m.tableById(add.createdId!)!;
      expect((t.logicalName, t.physicalName), ('テーブル1', 'table_1'));
      expect(t.columns.single.typeId, 'auto');
      expect(t.columns.single.pk, isTrue);
      final after = dump(m);
      h.undo();
      expect(dump(m), before);
      h.redo();
      expect(dump(m), after);
    });

    test('名前の採番は未使用の最小の正の整数', () {
      final d = m.diagrams.first.id;
      h.execute(AddTableCommand(diagramId: d, x: 0, y: 0));
      final c2 = AddTableCommand(diagramId: d, x: 0, y: 0);
      h.execute(c2);
      h.execute(AddTableCommand(diagramId: d, x: 0, y: 0));
      h.execute(DeleteEntitiesCommand([c2.createdId!]));
      final c = AddTableCommand(diagramId: d, x: 0, y: 0);
      h.execute(c);
      expect(m.tableById(c.createdId!)!.physicalName, 'table_2');
    });

    test('未保存判定: 保存位置と現在位置が異なるとき', () {
      expect(h.isDirty, isFalse);
      h.execute(AddTableCommand(diagramId: m.diagrams.first.id, x: 0, y: 0));
      expect(h.isDirty, isTrue);
      h.markSaved();
      expect(h.isDirty, isFalse);
      h.undo();
      expect(h.isDirty, isTrue);
      h.redo();
      expect(h.isDirty, isFalse);
      h.undo();
      h.execute(AddTableCommand(diagramId: m.diagrams.first.id, x: 0, y: 0)); // 保存位置へは戻れない
      h.undo();
      h.undo();
      expect(h.isDirty, isTrue);
    });

    test('履歴の上限を超えたら古いものから破棄する', () {
      final h2 = historyOf(m, limit: 3);
      for (var i = 0; i < 5; i++) {
        h2.execute(AddTableCommand(diagramId: m.diagrams.first.id, x: 0, y: 0));
      }
      var n = 0;
      while (h2.canUndo) {
        h2.undo();
        n++;
      }
      expect(n, 3);
      expect(m.tables.length, 2);
    });

    test('失敗したコマンドは状態を変えず履歴にも積まない', () {
      final d = m.diagrams.first.id;
      final add = AddTableCommand(diagramId: d, x: 0, y: 0);
      h.execute(add);
      m.tableById(add.createdId!)!.locked = true;
      final before = dump(m);
      expect(() => h.execute(DeleteEntitiesCommand([add.createdId!])), throwsA(isA<CommandException>()));
      expect(dump(m), before);
      expect(() => h.execute(AddColumnCommand(add.createdId!)), throwsA(isA<CommandException>()));
      h.undo(); // 積まれているのは AddTable のみ
      expect(m.tables, isEmpty);
    });

    test('ドラッグ移動(複数同時)は1コマンド', () {
      final d = m.diagrams.first;
      final a = AddTableCommand(diagramId: d.id, x: 0, y: 0)..createdId;
      h.execute(a);
      final b = AddTableCommand(diagramId: d.id, x: 100, y: 0);
      h.execute(b);
      h.execute(MovePlacementsCommand(d.id, {a.createdId!: [10, 10], b.createdId!: [210, 10]}));
      h.undo();
      final d2 = m.diagrams.first; // Undoで差し替わるため取得し直す
      expect(d2.placementOf(a.createdId!)!.x, 0);
      expect(d2.placementOf(b.createdId!)!.x, 100);
    });

    test('モデルから削除は、リレーションシップ・配置の削除を含めて1コマンド', () {
      final d = m.diagrams.first;
      final p = table(m, 'p', [col(m, 'id', 'auto', pk: true)]);
      final c = table(m, 'c', [col(m, 'k', 'integer', pk: true)]);
      h.execute(AddRelationshipCommand(tableAId: p.id, tableBId: c.id));
      final before = dump(m);
      h.execute(DeleteEntitiesCommand([p.id]));
      expect(m.relationships, isEmpty);
      expect(d.placementOf(p.id), isNull);
      h.undo();
      expect(dump(m), before);
    });

    test('ビューのソースになっているテーブルは削除できない。列も同様', () {
      final m2 = fullModel();
      final h2 = historyOf(m2);
      final orders = m2.tables.firstWhere((t) => t.physicalName == 'orders');
      expect(DeleteEntitiesCommand.blockers(m2, [orders.id]).any((s) => s.contains('ビュー')), isTrue);
      expect(RemoveColumnCommand.blockers(m2, orders.id, orders.columns[0].id), isNotEmpty);
      expect(() => h2.execute(DeleteEntitiesCommand([orders.id])), throwsA(isA<CommandException>()));
    });

    test('列の削除: 制約から除外し、列が0になる制約とリレーションシップを削除する', () {
      final m2 = fullModel();
      final h2 = historyOf(m2);
      final orders = m2.tables.firstWhere((t) => t.physicalName == 'orders');
      // ビューが使っていない列(price)で試す前に、使っている customer_id を避ける
      final customerId = orders.columns[1];
      // customer_id はビューの結合条件に使われているため削除不可
      expect(RemoveColumnCommand.blockers(m2, orders.id, customerId.id), isNotEmpty);
      // ビューを除いてから削除する
      m2.entities.removeWhere((e) => e is ViewEntity);
      final impacts = RemoveColumnCommand.impacts(m2, orders.id, customerId.id);
      expect(impacts.length, 3); // index, unique, relationship
      h2.execute(RemoveColumnCommand(orders.id, customerId.id));
      expect(orders.indexes, isEmpty);
      expect(orders.uniques.single.columnIds, [orders.columns[0].id]);
      expect(m2.relationships, isEmpty);
      h2.undo();
      final orders2 = m2.tables.firstWhere((t) => t.physicalName == 'orders'); // Undoで差し替わる
      expect(orders2.indexes.length, 1);
      expect(m2.relationships.length, 1);
    });

    test('削除時のロック・参照の保護(メソッド・型)', () {
      final m2 = fullModel();
      final h2 = historyOf(m2);
      final fn = m2.methods.firstWhere((x) => x.name == 'now_utc');
      expect(() => h2.execute(DeleteMethodCommand(fn.id)), throwsA(isA<CommandException>())); // 関数ビューが参照
      final trg = m2.methods.firstWhere((x) => x.name == 'touch');
      h2.execute(DeleteMethodCommand(trg.id));
      expect(m2.tables.firstWhere((t) => t.physicalName == 'orders').triggers.length, 1);
      expect(() => h2.execute(DeleteTypeCommand('integer', null)), throwsA(isA<CommandException>()));
      expect(DeleteTypeCommand.usageCount(m2, 'custom_1'), 1);
      expect(() => h2.execute(DeleteTypeCommand('custom_1', null)), throwsA(isA<CommandException>()));
      h2.execute(DeleteTypeCommand('custom_1', 'integer'));
      expect(m2.tables.firstWhere((t) => t.physicalName == 'orders').columns[2].typeId, 'integer');
      expect(m2.typeById('custom_1'), isNull);
    });

    test('貼り付け: 新しいID、位置は(20,20)ずれ、名前は _copy、ロックは解除', () {
      final m2 = fullModel();
      final h2 = historyOf(m2);
      final d = m2.diagrams.first;
      final orders = m2.tables.firstWhere((t) => t.physicalName == 'orders');
      orders.locked = true;
      final clip = ClipboardData.fromSelection(m2, d, [orders.id]);
      final p = d.placementOf(orders.id)!;
      final paste = PasteEntitiesCommand(diagramId: d.id, data: clip);
      h2.execute(paste);
      final n = m2.tableById(paste.createdIds.single)!;
      expect(n.physicalName, 'orders_copy');
      expect(n.logicalName, '注文のコピー');
      expect(n.locked, isFalse);
      expect(d.placementOf(n.id)!.x, p.x + 20);
      expect(n.uniques.single.name, 'orders_uq_custom_copy');
      final h3 = historyOf(m2);
      h3.execute(PasteEntitiesCommand(diagramId: d.id, data: clip));
      expect(m2.tables.map((t) => t.physicalName), contains('orders_copy2'));
      // 全IDが一意
      final ids = <int>{};
      for (final t in m2.tables) {
        expect(ids.add(t.id), isTrue);
        for (final c in t.columns) {
          expect(ids.add(c.id), isTrue);
        }
      }
    });

    test('貼り付け: 選択エンティティ同士を結ぶリレーションシップも複製する', () {
      final m2 = fullModel();
      final h2 = historyOf(m2);
      final d = m2.diagrams.first;
      final ids = m2.tables.map((t) => t.id).toList();
      final paste = PasteEntitiesCommand(diagramId: d.id, data: ClipboardData.fromSelection(m2, d, ids));
      h2.execute(paste);
      expect(m2.relationships.length, 2);
      final r = m2.relationships.last;
      final parent = m2.tableById(r.parentId)!;
      final child = m2.tableById(r.childId)!;
      expect(parent.physicalName, 'customers_copy');
      expect(child.columnById(r.columnPairs.single.childColumnId), isNotNull);
      expect(parent.columnById(r.columnPairs.single.parentColumnId), isNotNull);
    });
  });

  group('キャッシュの再生(9.2)', () {
    test('base.pero に commands.jsonl を再生すると、編集後のモデルと同じになる(Undo/Redo含む)', () {
      final dir = Directory.systemTemp.createTempSync('pero_cache');
      addTearDown(() => dir.deleteSync(recursive: true));
      final store = CacheStore(dir.path);
      final m = fullModel();
      final h = historyOf(m);
      store.writeBase(m, r'C:\x\a.pero', baseText: CacheStore.baseTextOf(m));
      h.onJournal = store.append;

      final d = m.diagrams.first;
      final add = AddTableCommand(diagramId: d.id, x: 50, y: 700);
      h.execute(add);
      h.execute(AddColumnCommand(add.createdId!));
      h.undo();
      h.redo();
      final orders = m.tables.firstWhere((t) => t.physicalName == 'orders');
      h.execute(MovePlacementsCommand(d.id, {orders.id: [900, 900]}));
      final customers = m.tables.firstWhere((t) => t.physicalName == 'customers');
      h.execute(UpdateRelationshipCommand(m.relationships.first.id, {'dependency': false}, link: true));
      h.execute(SetLockedCommand([customers.id], true));
      h.execute(AddDiagramCommand());
      h.execute(ReplaceEntityCommand.of(
          m.entityById(add.createdId!)!.copy()..logicalName = '変更後'));
      h.undo();
      h.execute(UpdateModelPropertiesCommand({'outputFileName': 'zzz'}));
      final expected = dump(m);

      final state = store.read()!;
      expect(store.isRecoverable(state), isTrue);
      final r = recoverFromCache(state, (mm) => EntityLayouter(mm));
      expect(r.error, isNull);
      expect(dump(r.model!), expected);
    });

    test('一度も保存していないモデルは記録しない。保存で commands.jsonl が空になる', () {
      final dir = Directory.systemTemp.createTempSync('pero_cache2');
      addTearDown(() => dir.deleteSync(recursive: true));
      final store = CacheStore(dir.path);
      store.append({'op': 'undo'});
      expect(store.read(), isNull);
      final m = ErModel.empty();
      store.writeBase(m, 'a.pero', baseText: CacheStore.baseTextOf(m));
      store.append({'op': 'undo'});
      expect(store.read()!.journal.length, 1);
      store.writeBase(m, 'a.pero', baseText: CacheStore.baseTextOf(m));
      expect(store.read()!.journal, isEmpty);
      expect(store.isRecoverable(store.read()), isFalse);
    });

    test('セッションロック: 残っていれば前回は異常終了', () {
      final dir = Directory.systemTemp.createTempSync('pero_lock');
      addTearDown(() => dir.deleteSync(recursive: true));
      final store = CacheStore(dir.path);
      expect(store.previousSessionCrashed, isFalse);
      store.createSessionLock();
      expect(CacheStore(dir.path).previousSessionCrashed, isTrue);
      store.deleteSessionLock();
      expect(store.previousSessionCrashed, isFalse);
    });

    test('破損したキャッシュ・再生の失敗はエラーとして返す', () {
      final dir = Directory.systemTemp.createTempSync('pero_cache3');
      addTearDown(() => dir.deleteSync(recursive: true));
      final store = CacheStore(dir.path);
      final m = ErModel.empty();
      store.writeBase(m, 'a.pero', baseText: CacheStore.baseTextOf(m));
      File('${dir.path}/cache/commands.jsonl').writeAsStringSync('not json\n');
      String? msg;
      expect(store.read(corrupt: (e) => msg = e), isNull);
      expect(msg, isNotNull);
      final r = recoverFromCache(
          CacheState(
              modelId: 1, filePath: null, savedOnce: true, appVersion: '', baseText: CacheStore.baseTextOf(m), journal: [
            {'op': 'exec', 'cmd': {'type': 'unknown', 'args': {}}}
          ]),
          (mm) => EntityLayouter(mm));
      expect(r.model, isNull);
      expect(r.error, contains('再生に失敗'));
    });
  });
}
