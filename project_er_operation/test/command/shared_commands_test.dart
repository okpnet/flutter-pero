import 'package:flutter_test/flutter_test.dart';
import 'package:project_er_operation/command/command.dart';
import 'package:project_er_operation/model/model.dart';
import 'package:project_er_operation/persistence/persistence.dart';

import '../support/sample_models.dart';

CommandHistory historyOf(ErModel m) => CommandHistory(CommandContext(m, () => EntityLayouter(m)));

void main() {
  test('メソッドの一括置換: 削除したメソッドの参照を解除し、追加したIDより大きく nextId を引き上げる', () {
    final m = fullModel();
    final h = historyOf(m);
    final keep = m.methods.firstWhere((x) => x.name == 'now_utc').copy();
    final fresh = MethodDef(id: m.nextId + 10, name: 'new_fn'); // ダイアログで採番したID
    // トリガーのメソッド(touch)を削除、関数 now_utc は残す(関数ビューが参照)
    h.execute(ReplaceSharedResourcesCommand.of(methods: [keep, fresh]));
    final orders = m.tables.firstWhere((t) => t.physicalName == 'orders');
    expect(orders.triggers.length, 1); // 公開トリガーは削除、入力のトリガーは残る
    expect(m.methods.map((x) => x.name), ['now_utc', 'new_fn']);
    expect(m.nextId, greaterThan(fresh.id));
    h.undo();
    expect(m.methods.length, 3); // now_utc, touch, empty_string
    expect(m.tables.firstWhere((t) => t.physicalName == 'orders').triggers.length, 2);
  });

  test('関数ビューが参照しているメソッドは、一括置換でも削除できない', () {
    final m = fullModel();
    final h = historyOf(m);
    final before = PeroEncoder.encode(m);
    final trgOnly = m.methods.where((x) => x.kind == MethodKind.trigger).map((x) => x.copy()).toList();
    expect(() => h.execute(ReplaceSharedResourcesCommand.of(methods: trgOnly)), throwsA(isA<CommandException>()));
    expect(PeroEncoder.encode(m), before);
  });

  test('型の一括置換: 使用中の型の削除は置換先が必須。置換先へ付け替える', () {
    final m = fullModel(); // custom_1 は orders.price が使用中
    final h = historyOf(m);
    final next = m.types.where((t) => t.id != 'custom_1').map((t) => t.copy()).toList();
    expect(() => h.execute(ReplaceSharedResourcesCommand.of(types: next)), throwsA(isA<CommandException>()));
    h.execute(ReplaceSharedResourcesCommand.of(types: next, typeReplacements: {'custom_1': 'integer'}));
    expect(m.typeById('custom_1'), isNull);
    expect(m.tables.firstWhere((t) => t.physicalName == 'orders').columns[2].typeId, 'integer');
    h.undo();
    expect(m.typeById('custom_1'), isNotNull);
    expect(m.tables.firstWhere((t) => t.physicalName == 'orders').columns[2].typeId, 'custom_1');
  });

  test('標準型は一括置換でも削除できず、物理名テンプレートの編集は反映される', () {
    final m = fullModel();
    final h = historyOf(m);
    final noInt = m.types.where((t) => t.id != 'uuid').map((t) => t.copy()).toList();
    expect(() => h.execute(ReplaceSharedResourcesCommand.of(types: noInt)), throwsA(isA<CommandException>()));
    final edited = m.types.map((t) => t.copy()).toList();
    edited.firstWhere((t) => t.id == 'text').physical[DbKind.postgresql] = 'citext';
    h.execute(ReplaceSharedResourcesCommand.of(types: edited));
    expect(m.typeById('text')!.physical[DbKind.postgresql], 'citext');
  });

  test('共通列パターンの置換: 並び順と内容が反映され、列のIDより大きく nextId を引き上げる。JSONで再生できる', () {
    final m = fullModel();
    final h = historyOf(m);
    final p = m.patterns.first.copy();
    final newCol = ColumnDef(id: m.nextId + 5, physicalName: 'updated_at', typeId: 'timestamp');
    p.columns.add(newCol);
    final p2 = CommonColumnPattern(id: m.nextId + 3, name: '先頭', position: PatternPosition.start);
    final cmd = ReplaceSharedResourcesCommand.of(patterns: [p2, p]);
    h.execute(cmd);
    expect(m.patterns.map((x) => x.name), ['先頭', '監査列']);
    expect(m.nextId, greaterThan(newCol.id));
    final back = commandFromJson(cmd.toJson()) as ReplaceSharedResourcesCommand;
    final m2 = fullModel();
    m2.id = m.id; // モデルIDは生成時刻由来
    historyOf(m2).execute(back);
    expect(PeroEncoder.encode(m2), PeroEncoder.encode(m));
  });

  test('エンティティ置換でトリガー/制約のIDを採番してもキャッシュ再生でIDが衝突しない', () {
    final m = fullModel();
    final h = historyOf(m);
    final orders = m.tables.firstWhere((t) => t.physicalName == 'orders').copy();
    orders.triggers.add(TriggerDef(id: m.nextId + 7)); // プロパティペインでの採番相当
    h.execute(ReplaceEntityCommand.of(orders));
    expect(m.nextId, greaterThan(orders.triggers.last.id));
    final add = AddTableCommand(diagramId: m.diagrams.first.id, x: 0, y: 0);
    h.execute(add);
    expect(add.createdId, greaterThan(orders.triggers.last.id));
  });

  test('関数ビューの追加と定義の編集(ビュー定義はコマンドで追加・置換できる)', () {
    final m = fullModel();
    final h = historyOf(m);
    final fn = m.methods.firstWhere((x) => x.name == 'now_utc');
    final v = ViewEntity(
        id: 0,
        physicalName: 'v_new',
        viewType: ViewType.function,
        function: ViewFunctionDef(methodId: fn.id, args: ['1'], columns: [FunctionReturnColumn(name: 'x', typeId: 'integer')]));
    final add = AddViewCommand(diagramId: m.diagrams.first.id, x: 10, y: 10, entityMap: PeroEncoder.entityToMap(v));
    h.execute(add);
    final created = m.entityById(add.createdId!) as ViewEntity;
    expect(created.function.args, ['1']);
    final edit = created.copy()..function.args = ['2', '3'];
    h.execute(ReplaceEntityCommand.of(edit));
    expect((m.entityById(created.id) as ViewEntity).function.args, ['2', '3']);
  });
}
