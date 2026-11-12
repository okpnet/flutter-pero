import 'package:flutter_test/flutter_test.dart';
import 'package:project_er_operation/generation/generation.dart';
import 'package:project_er_operation/model/model.dart';

import '../support/post_models.dart';
import '../support/sample_models.dart';

bool hasMsg(List<ValidationIssue> l, String s) => l.any((e) => e.message.contains(s));

void main() {
  test('サンプルモデルはエラーなし', () {
    for (final f in [modelSimple, modelForeignKeys, modelCommonColumns, modelViews, modelTriggersAndCycle, fullModel]) {
      expect(ModelValidator(f()).validate().errors, isEmpty, reason: f.toString());
    }
  });

  test('物理名の空・形式不正・重複(大文字小文字を区別しない)', () {
    final m = ErModel.empty();
    table(m, '', [col(m, 'id', 'integer')]);
    table(m, '1bad', [col(m, 'a', 'integer'), col(m, 'A', 'integer')]);
    table(m, 'Dup', [col(m, 'id', 'integer')]);
    table(m, 'dup', [col(m, 'id', 'integer')]);
    final e = ModelValidator(m).validate().errors;
    expect(hasMsg(e, '物理名が空'), isTrue);
    expect(hasMsg(e, '形式に一致しません'), isTrue);
    expect(hasMsg(e, '列名「A」が重複'), isTrue);
    expect(hasMsg(e, 'エンティティの物理名「dup」が重複'), isTrue);
  });

  test('型が存在しない/対象DBのテンプレート未定義はエラー', () {
    final m = ErModel.empty();
    table(m, 't', [col(m, 'a', 'nothing'), col(m, 'b', 'integer')]);
    m.typeById('integer')!.physical[DbKind.postgresql] = '';
    final e = ModelValidator(m).validate().errors;
    expect(hasMsg(e, '型「nothing」が存在しません'), isTrue);
    expect(hasMsg(e, 'テンプレートがありません'), isTrue);
  });

  test('auto型が2つ以上、本体が空のメソッド参照、不正な正規表現はエラー', () {
    final m = ErModel.empty();
    final fn = MethodDef(id: m.allocateId(), name: 'f');
    m.methods.add(fn);
    table(m, 't', [
      col(m, 'a', 'auto', pk: true),
      col(m, 'b', 'auto'),
      col(m, 'c', 'timestamp', defKind: DefaultKind.method, defMethod: fn.id),
    ]);
    m.patterns.add(CommonColumnPattern(id: m.allocateId(), name: 'bad', include: '('));
    final e = ModelValidator(m).validate().errors;
    expect(hasMsg(e, 'auto型の列が2つ以上'), isTrue);
    expect(hasMsg(e, '本体が空'), isTrue);
    expect(hasMsg(e, '正規表現が不正'), isTrue);
    // 参照されていない空本体のメソッドはエラーにならない
    fn.external = true;
    expect(hasMsg(ModelValidator(m).validate().errors, '本体が空'), isFalse);
  });

  test('リレーションシップの列対応、ビュー定義、トリガーの不備はエラー', () {
    final m = fullModel();
    m.relationships.first.columnPairs.clear();
    final v = m.views.first;
    v.join.columns.clear();
    final orders = m.tables.firstWhere((t) => t.physicalName == 'orders');
    orders.triggers.first.events.clear();
    orders.triggers.last.inlineBodies[DbKind.postgresql] = '';
    final e = ModelValidator(m).validate().errors;
    expect(hasMsg(e, '列対応が未割当'), isTrue);
    expect(hasMsg(e, '出力列がありません'), isTrue);
    expect(hasMsg(e, 'イベントが未選択'), isTrue);
    expect(hasMsg(e, '本体が空'), isTrue);
  });

  test('警告: 主キーなし、列0、型の不一致、長さ超過、予約語', () {
    final m = ErModel.empty();
    table(m, 'no_pk', [col(m, 'x', 'integer')]);
    table(m, 'empty', []);
    table(m, 'user', [col(m, 'id', 'integer', pk: true)]); // 予約語
    table(m, 'x' * 64, [col(m, 'id', 'integer', pk: true)]);
    final w = ModelValidator(m).validate().warnings;
    expect(hasMsg(w, '主キーがありません'), isTrue);
    expect(hasMsg(w, '列がありません'), isTrue);
    expect(hasMsg(w, '予約語'), isTrue);
    expect(hasMsg(w, '識別子の長さ'), isTrue);
    m.properties.targetDb = DbKind.sqlite;
    expect(hasMsg(ModelValidator(m).validate().warnings, '識別子の長さ'), isFalse);
    expect(hasMsg(ModelValidator(m).validate().warnings, '予約語'), isFalse);
  });

  test('警告: 外部キー列と親の列の型の不一致、SET DEFAULTでデフォルトなし', () {
    final m = fullModel();
    final orders = m.tables.firstWhere((t) => t.physicalName == 'orders');
    orders.columns[1].typeId = 'varchar';
    m.relationships.first.onDelete = RefAction.setDefault;
    final w = ModelValidator(m).validate().warnings;
    expect(hasMsg(w, '型が異なります'), isTrue);
    expect(hasMsg(w, 'SET DEFAULT'), isTrue);
  });

  test('制約名はモデル全体で重複できない', () {
    final m = ErModel.empty();
    final a = table(m, 'a', [col(m, 'id', 'integer', pk: true)]);
    final b = table(m, 'b', [col(m, 'id', 'integer', pk: true)]);
    for (final t in [a, b]) {
      t.indexes.add(ConstraintDef(id: m.allocateId(), nameMode: NameMode.manual, name: 'same', columnIds: [t.columns[0].id]));
    }
    expect(hasMsg(ModelValidator(m).validate().errors, '制約名「same」'), isTrue);
  });

  test('出力先パス: 出力フォルダ・ファイル名の既定(9.6-1)', () {
    final m = ErModel.empty();
    String p(String? f) => resolveOutputPath(model: m, peroFilePath: f, documentsDir: r'C:\docs', extension: 'sql');
    expect(p(null), r'C:\docs\無題.sql');
    expect(p(r'C:\w\model.pero'), r'C:\w\model.sql');
    m.properties.outputFolder = r'D:\out';
    m.properties.outputFileName = 'x';
    expect(p(r'C:\w\model.pero'), r'D:\out\x.sql');
  });
}
