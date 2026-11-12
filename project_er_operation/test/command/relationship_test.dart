import 'package:flutter_test/flutter_test.dart';
import 'package:project_er_operation/command/command.dart';
import 'package:project_er_operation/model/model.dart';

import '../support/sample_models.dart';

CommandHistory historyOf(ErModel m) =>
    CommandHistory(CommandContext(m, () => EntityLayouter(m)));

void main() {
  group('リレーションシップの追加(7-5)', () {
    test('同名の列があればそれを外部キー列にする。依存関係が有効なので子のPKに含めNotNullにする', () {
      final m = ErModel.empty();
      final parent = table(m, 'customer', [col(m, 'id', 'auto', pk: true)]);
      final child = table(m, 'orders', [
        col(m, 'order_no', 'integer', pk: true),
        col(m, 'id', 'integer'),
      ]);
      final h = historyOf(m);
      final cmd = AddRelationshipCommand(tableAId: parent.id, tableBId: child.id);
      h.execute(cmd);
      final r = m.relationshipById(cmd.createdId!)!;
      expect(r.parentId, parent.id);
      expect(r.columnPairs.single.childColumnId, child.columns[1].id);
      expect(child.columns.length, 2); // 列は作られない
      expect(child.columns[1].pk, isTrue);
      expect(child.columns[1].notNull, isTrue);
    });

    test('部分一致の列を使う。複数あれば列順で先頭', () {
      final m = ErModel.empty();
      final parent = table(m, 'customer', [col(m, 'id', 'auto', pk: true)]);
      final child = table(m, 'orders', [
        col(m, 'a', 'integer'),
        col(m, 'customer_id', 'integer'),
        col(m, 'other_id', 'integer'),
      ]);
      final h = historyOf(m);
      final cmd = AddRelationshipCommand(tableAId: parent.id, tableBId: child.id);
      h.execute(cmd);
      expect(m.relationshipById(cmd.createdId!)!.columnPairs.single.childColumnId, child.columns[1].id);
    });

    test('見つからなければ子に列を作る(型はautoをintegerへ、PKの直後に挿入)', () {
      final m = ErModel.empty();
      final parent = table(m, 'customer', [col(m, 'id', 'auto', pk: true, logical: 'ID')], logical: '顧客');
      final child = table(m, 'orders', [
        col(m, 'order_no', 'integer', pk: true),
        col(m, 'memo', 'text'),
      ]);
      final h = historyOf(m);
      h.execute(AddRelationshipCommand(tableAId: parent.id, tableBId: child.id));
      expect(child.columns.map((c) => c.physicalName), ['order_no', 'customer_id', 'memo']);
      final fk = child.columns[1];
      expect(fk.typeId, 'integer');
      expect(fk.logicalName, '顧客_ID');
      expect(fk.pk, isTrue);
      expect(fk.notNull, isTrue);
    });

    test('作成する列の物理名が重複するときは _2 を付ける。子側の別リレーションで割当済みの列は候補にしない', () {
      final m = ErModel.empty();
      final parent = table(m, 'customer', [col(m, 'id', 'auto', pk: true)]);
      final child = table(m, 'orders', [col(m, 'k', 'integer', pk: true), col(m, 'customer_id', 'text')]);
      final h = historyOf(m);
      // customer_id (text) は一致するため最初に使われる
      final c1 = AddRelationshipCommand(tableAId: parent.id, tableBId: child.id);
      h.execute(c1);
      final c2 = AddRelationshipCommand(tableAId: parent.id, tableBId: child.id);
      h.execute(c2);
      final r2 = m.relationshipById(c2.createdId!)!;
      final created = child.columnById(r2.columnPairs.single.childColumnId)!;
      expect(created.physicalName, 'customer_id_2');
    });

    test('ロック中のテーブル、自己参照、親に鍵がない場合は追加できない', () {
      final m = ErModel.empty();
      final a = table(m, 'a', [col(m, 'id', 'auto', pk: true)]);
      final b = table(m, 'b', [col(m, 'x', 'integer')]);
      expect(relationshipAddBlocker(m, a, a), isNotNull);
      expect(relationshipAddBlocker(m, a, b), isNull);
      expect(relationshipAddBlocker(m, b, a), isNull);
      final c = table(m, 'c', [col(m, 'x', 'integer')]); // 鍵なし。IDが小さい方(b)が親
      expect(relationshipAddBlocker(m, b, c), isNotNull);
      a.locked = true;
      expect(relationshipAddBlocker(m, a, b), isNotNull);
      final h = historyOf(m);
      expect(() => h.execute(AddRelationshipCommand(tableAId: a.id, tableBId: b.id)),
          throwsA(isA<CommandException>()));
    });

    test('Undoで外部キー列の自動作成も含めて1コマンドで元に戻る', () {
      final m = ErModel.empty();
      final parent = table(m, 'customer', [col(m, 'id', 'auto', pk: true)]);
      final child = table(m, 'orders', [col(m, 'k', 'integer', pk: true)]);
      final h = historyOf(m);
      h.execute(AddRelationshipCommand(tableAId: parent.id, tableBId: child.id));
      expect(m.relationships.length, 1);
      h.undo();
      expect(m.relationships, isEmpty);
      expect(m.tableById(child.id)!.columns.length, 1);
      h.redo();
      expect(m.relationships.length, 1);
      expect(m.tableById(child.id)!.columns.length, 2);
    });
  });

  group('依存関係の連動(7-6)', () {
    late ErModel m;
    late TableEntity parent, child;
    late int relId;
    late CommandHistory h;
    setUp(() {
      m = ErModel.empty();
      parent = table(m, 'p', [col(m, 'id', 'auto', pk: true)]);
      child = table(m, 'c', [col(m, 'k', 'integer', pk: true)]);
      h = historyOf(m);
      final cmd = AddRelationshipCommand(tableAId: parent.id, tableBId: child.id);
      h.execute(cmd);
      relId = cmd.createdId!;
    });

    ColumnDef fk() => m.tableById(child.id)!.columns.firstWhere((c) => c.physicalName == 'p_id');

    test('依存関係を無効にする(連動あり): PKとNotNullを解除', () {
      h.execute(UpdateRelationshipCommand(relId, {'dependency': false}, link: true));
      expect(fk().pk, isFalse);
      expect(fk().notNull, isFalse);
    });

    test('連動なし(確認で「いいえ」相当)の場合は列を変えない', () {
      h.execute(UpdateRelationshipCommand(relId, {'dependency': false}, link: false));
      expect(fk().pk, isTrue);
    });

    test('無効→有効: PKとNotNullを有効に', () {
      h.execute(UpdateRelationshipCommand(relId, {'dependency': false}, link: true));
      h.execute(UpdateRelationshipCommand(relId, {'dependency': true}, link: true));
      expect(fk().pk, isTrue);
      expect(fk().notNull, isTrue);
    });

    test('有効のまま両方「適用しない」: PKを解除しNotNullは維持、戻すとPKを有効に', () {
      h.execute(UpdateRelationshipCommand(relId, {'onDelete': 'none', 'onUpdate': 'none'}, link: true));
      expect(fk().pk, isFalse);
      expect(fk().notNull, isTrue);
      h.execute(UpdateRelationshipCommand(relId, {'onDelete': 'cascade'}, link: true));
      expect(fk().pk, isTrue);
    });

    test('linkagePlan は変更の種類ごとの計画を返す', () {
      Relationship r({bool dep = true, RefAction d = RefAction.noAction, RefAction u = RefAction.noAction}) =>
          Relationship(id: 1, parentId: 1, childId: 2, dependency: dep, onDelete: d, onUpdate: u);
      expect(linkagePlan(r(dep: false), r()), (true, true));
      expect(linkagePlan(r(), r(dep: false)), (false, false));
      expect(linkagePlan(r(), r(d: RefAction.none, u: RefAction.none)), (false, null));
      expect(linkagePlan(r(d: RefAction.none, u: RefAction.none), r()), (true, null));
      expect(linkagePlan(r(dep: false), r(dep: false, d: RefAction.cascade)), (null, null));
    });

    test('共通列の外部キー列は連動しない', () {
      final p = CommonColumnPattern(id: m.allocateId(), name: 'p', position: PatternPosition.end, columns: [
        col(m, 'common_fk', 'integer'),
      ]);
      m.patterns.add(p);
      final r = m.relationshipById(relId)!;
      r.columnPairs = [ColumnPair(parentColumnId: parent.columns[0].id, childColumnId: p.columns[0].id)];
      h.execute(UpdateRelationshipCommand(relId, {'dependency': false}, link: true));
      expect(p.columns[0].pk, isFalse);
    });

    test('削除しても外部キー列は残る(PK・NotNullも維持)', () {
      h.execute(RemoveRelationshipCommand([relId]));
      expect(m.relationships, isEmpty);
      expect(fk().pk, isTrue);
    });

    test('ロック中のリレーションシップは更新・削除できない', () {
      m.relationshipById(relId)!.locked = true;
      expect(() => h.execute(RemoveRelationshipCommand([relId])), throwsA(isA<CommandException>()));
      expect(() => h.execute(UpdateRelationshipCommand(relId, {'name': 'x'})), throwsA(isA<CommandException>()));
    });

    test('方向の入替で列対応をやり直す', () {
      // 親側の鍵(id)と子の鍵(k)を入れ替えると、cがp_..でなくk起点になる
      h.execute(SwapRelationshipDirectionCommand(relId));
      final r = m.relationshipById(relId)!;
      expect(r.parentId, child.id);
      expect(r.childId, parent.id);
      expect(r.columnPairs.length, parentKeyColumns(m, child).length);
    });
  });

  test('外部キー名: 子テーブルを子とするリレーションシップのID昇順の位置', () {
    final m = ErModel.empty();
    final p1 = table(m, 'p1', [col(m, 'id', 'integer', pk: true)]);
    final p2 = table(m, 'p2', [col(m, 'id', 'integer', pk: true)]);
    final c = table(m, 'c', [col(m, 'k', 'integer', pk: true)]);
    final h = historyOf(m);
    final a = AddRelationshipCommand(tableAId: p1.id, tableBId: c.id)..createdId;
    h.execute(a);
    final b = AddRelationshipCommand(tableAId: p2.id, tableBId: c.id);
    h.execute(b);
    expect(m.foreignKeyName(m.relationshipById(a.createdId!)!), 'c_fk1');
    expect(m.foreignKeyName(m.relationshipById(b.createdId!)!), 'c_fk2');
  });
}
