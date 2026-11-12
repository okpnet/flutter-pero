import 'package:flutter_test/flutter_test.dart';
import 'package:project_er_operation/command/command.dart';
import 'package:project_er_operation/model/model.dart';

import '../support/sample_models.dart';

void main() {
  CommandHistory h(ErModel m) => CommandHistory(CommandContext(m, () => EntityLayouter(m)));

  test('列のドラッグ: ドロップ先の列を外部キー列にする(列は作られない)。ドラッグ元が親', () {
    final m = ErModel.empty();
    final a = table(m, 'a', [col(m, 'id', 'integer', pk: true)]); // IDは小さい
    final b = table(m, 'b', [col(m, 'k', 'integer', pk: true), col(m, 'ref', 'integer')]);
    // IDの大きいbを親にしてドラッグする
    final cmd = AddRelationshipCommand(
        tableAId: b.id, tableBId: a.id, parentId: b.id, parentColumnId: b.columns[0].id, childColumnId: a.columns[0].id);
    h(m).execute(cmd);
    final r = m.relationshipById(cmd.createdId!)!;
    expect((r.parentId, r.childId), (b.id, a.id));
    expect(r.columnPairs.single.childColumnId, a.columns[0].id);
    expect(a.columns.length, 1);
  });

  test('親の列が主キー/ユニークでなければ拒否する', () {
    final m = ErModel.empty();
    final a = table(m, 'a', [col(m, 'id', 'integer', pk: true), col(m, 'x', 'integer')]);
    final b = table(m, 'b', [col(m, 'k', 'integer', pk: true)]);
    final cmd = AddRelationshipCommand(
        tableAId: a.id, tableBId: b.id, parentId: a.id, parentColumnId: a.columns[1].id, childColumnId: b.columns[0].id);
    expect(() => h(m).execute(cmd), throwsA(isA<CommandException>()));
    expect(m.relationships, isEmpty);
  });

  test('ドロップ先が列でないとき(エンティティ)は自動決定(7-5)', () {
    final m = ErModel.empty();
    final a = table(m, 'a', [col(m, 'id', 'integer', pk: true)]);
    final b = table(m, 'b', [col(m, 'k', 'integer', pk: true)]);
    final cmd = AddRelationshipCommand(tableAId: a.id, tableBId: b.id, parentId: a.id);
    h(m).execute(cmd);
    expect(b.columns.map((c) => c.physicalName), ['k', 'a_id']);
  });

  test('列指定付きのコマンドもJSONで再生できる(キャッシュ)', () {
    final m = ErModel.empty();
    final a = table(m, 'a', [col(m, 'id', 'integer', pk: true)]);
    final b = table(m, 'b', [col(m, 'k', 'integer', pk: true), col(m, 'ref', 'integer')]);
    final cmd = AddRelationshipCommand(
        tableAId: a.id, tableBId: b.id, parentId: a.id, parentColumnId: a.columns[0].id, childColumnId: b.columns[1].id);
    final back = commandFromJson(cmd.toJson()) as AddRelationshipCommand;
    expect((back.parentColumnId, back.childColumnId), (a.columns[0].id, b.columns[1].id));
  });
}
