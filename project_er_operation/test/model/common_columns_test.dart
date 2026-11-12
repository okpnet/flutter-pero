import 'package:flutter_test/flutter_test.dart';
import 'package:project_er_operation/command/command.dart';
import 'package:project_er_operation/generation/generation.dart';
import 'package:project_er_operation/model/model.dart';

import '../support/sample_models.dart';

CommonColumnPattern pattern(ErModel m, String name, List<ColumnDef> cols,
        {String include = r'^.*$',
        String exclude = '',
        PatternPosition pos = PatternPosition.end,
        bool enabled = true}) =>
    CommonColumnPattern(
        id: m.allocateId(),
        name: name,
        include: include,
        exclude: exclude,
        position: pos,
        enabled: enabled,
        columns: cols);

List<String> names(ErModel m, TableEntity t) =>
    m.expand(t).columns.map((c) => c.column.physicalName).toList();

void main() {
  test('先頭は実列の前、末尾は実列の後に、パターンの並び順で展開する', () {
    final m = ErModel.empty();
    final t = table(m, 'users', [col(m, 'id', 'integer', pk: true)]);
    m.patterns.addAll([
      pattern(m, 'A', [col(m, 'a_end', 'text')]),
      pattern(m, 'B', [col(m, 'b_start', 'text')], pos: PatternPosition.start),
      pattern(m, 'C', [col(m, 'c_end', 'text')]),
    ]);
    expect(names(m, t), ['b_start', 'id', 'a_end', 'c_end']);
    expect(m.expand(t).columns.first.isCommon, isTrue);
    expect(m.expand(t).columns[1].isCommon, isFalse);
  });

  test('対象フィルタは全体一致(大文字小文字を区別)、除外フィルタに一致したら適用しない', () {
    final m = ErModel.empty();
    final t1 = table(m, 'mst_user', [col(m, 'id', 'integer')]);
    final t2 = table(m, 'tmp_user', [col(m, 'id', 'integer')]);
    final t3 = table(m, 'MST_USER2', [col(m, 'id', 'integer')]);
    m.patterns.add(pattern(m, 'P', [col(m, 'created', 'timestamp')], include: 'mst_.*', exclude: '.*2'));
    expect(names(m, t1), ['id', 'created']);
    expect(names(m, t2), ['id']);
    expect(names(m, t3), ['id']);
    // 全体一致: 部分一致では適用しない
    m.patterns.first.include = 'mst';
    expect(names(m, t1), ['id']);
  });

  test('無効なパターンは適用しない。不正な正規表現は無効扱い', () {
    final m = ErModel.empty();
    final t = table(m, 't', [col(m, 'id', 'integer')]);
    m.patterns.add(pattern(m, 'off', [col(m, 'x', 'text')], enabled: false));
    m.patterns.add(pattern(m, 'bad', [col(m, 'y', 'text')], include: '('));
    expect(names(m, t), ['id']);
    expect(m.patterns[1].isRegexValid, isFalse);
  });

  test('物理名の衝突は先に存在する方を優先し、後の列は展開しない(警告)', () {
    final m = ErModel.empty();
    final t = table(m, 't', [col(m, 'created_at', 'text')]);
    m.patterns.addAll([
      pattern(m, 'P1', [col(m, 'upd', 'text'), col(m, 'CREATED_AT', 'timestamp')]),
      pattern(m, 'P2', [col(m, 'upd', 'integer')]),
    ]);
    final r = m.expand(t);
    expect(r.columns.map((c) => c.column.physicalName), ['created_at', 'upd']);
    expect(r.skipped.length, 2);
    expect(r.columns.last.patternName, 'P1');
    final v = ModelValidator(m).validate();
    expect(v.warnings.where((w) => w.message.contains('衝突')).length, 2);
  });

  test('展開されなくなった共通列への参照は保持し、生成前検証でエラーにする', () {
    final m = ErModel.empty();
    final t = table(m, 't', [col(m, 'id', 'integer', pk: true)]);
    final p = pattern(m, 'P', [col(m, 'created', 'timestamp')]);
    m.patterns.add(p);
    t.uniques.add(ConstraintDef(id: m.allocateId(), columnIds: [p.columns.first.id]));
    expect(ModelValidator(m).validate().hasErrors, isFalse);
    p.enabled = false; // 展開されなくなる
    expect(t.uniques.single.columnIds, [p.columns.first.id]); // 参照は保持
    final v = ModelValidator(m).validate();
    expect(v.errors.any((e) => e.message.contains('created') && e.message.contains('展開されません')), isTrue);
  });

  test('共通列はテーブルに保存されず、パターンの変更がすべてのテーブルに追従する', () {
    final m = ErModel.empty();
    final t = table(m, 't', [col(m, 'id', 'integer')]);
    final p = pattern(m, 'P', [col(m, 'a', 'text')]);
    m.patterns.add(p);
    expect(t.columns.length, 1);
    p.columns.add(col(m, 'b', 'text'));
    expect(names(m, t), ['id', 'a', 'b']);
  });

  test('共通列の列IDはリレーションシップの子の列として指定でき、生成用JSONにorigin: commonで出る', () {
    final m = ErModel.empty();
    final parent = table(m, 'p', [col(m, 'id', 'integer', pk: true)]);
    final child = table(m, 'c', [col(m, 'k', 'integer', pk: true)]);
    final pat = pattern(m, 'P', [col(m, 'p_id', 'integer')], include: 'c');
    m.patterns.add(pat);
    final h = CommandHistory(CommandContext(m, () => EntityLayouter(m)));
    final cmd = AddRelationshipCommand(tableAId: parent.id, tableBId: child.id);
    h.execute(cmd);
    // 子の実列に一致する列が無いため実列が作られる。共通列と名前が衝突しないよう _2 が付く。
    expect(child.columns.map((c) => c.physicalName), ['k', 'p_id_2']);
    // 子の列を共通列に付け替える
    h.execute(UpdateRelationshipCommand(cmd.createdId!, {
      'columnPairs': [
        {'parentColumnId': parent.columns[0].id, 'childColumnId': pat.columns[0].id}
      ]
    }));
    final json = GenerationJsonBuilder(m).build();
    final c = (json['tables'] as List).firstWhere((t) => t['physicalName'] == 'c');
    expect((c['columns'] as List).map((x) => x['origin']), ['table', 'table', 'common']);
    final fk = (json['foreignKeys'] as List).single;
    expect(fk['columns'], [
      {'child': 'p_id', 'parent': 'id'}
    ]);
  });
}
