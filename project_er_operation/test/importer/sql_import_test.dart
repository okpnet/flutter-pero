import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:project_er_operation/command/command.dart';
import 'package:project_er_operation/generation/generation.dart';
import 'package:project_er_operation/importer/importer.dart';
import 'package:project_er_operation/model/model.dart';
import 'package:project_er_operation/persistence/persistence.dart';
import 'package:project_er_operation/runner/runner.dart';

import 'package:project_er_operation/dialog/dialog.dart';

import '../support/post_models.dart';
import '../support/post_support.dart';

const sql = r'''
-- コメント
CREATE TYPE color AS ENUM ('red', 'green');
CREATE TABLE parent (
  id serial PRIMARY KEY,
  name varchar(50) NOT NULL DEFAULT 'x',
  created timestamp DEFAULT now(),
  price numeric(10,2)
);
CREATE TABLE child (
  id integer NOT NULL,
  parent_id integer NOT NULL,
  note text DEFAULT '',
  c color
);
ALTER TABLE ONLY child ADD CONSTRAINT child_pkey PRIMARY KEY (id);
ALTER TABLE ONLY child ADD CONSTRAINT child_fk FOREIGN KEY (parent_id) REFERENCES parent(id) ON DELETE CASCADE;
ALTER TABLE ONLY child ADD CONSTRAINT child_uq UNIQUE (note);
CREATE INDEX child_idx ON child (parent_id);
CREATE FUNCTION touch() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN NEW.note := 'a;b'; RETURN NEW; END; $$;
CREATE TRIGGER child_trg BEFORE INSERT OR UPDATE ON child FOR EACH ROW EXECUTE FUNCTION touch();
CREATE VIEW v1 AS SELECT id FROM child;
SELECT id, name FROM parent WHERE id > 1;
select 1;
SELECT * FROM child;
INSERT INTO parent (id, name) VALUES (1, 'a;b');
UPDATE parent SET name = 'z';
GRANT ALL ON parent TO someone;
COMMENT ON TABLE parent IS '親';
COMMENT ON COLUMN parent.name IS '名前';
''';

Future<Map<String, Object?>> runPost(List<SqlImportFile> files) {
  final script = File('post/postgresql.import.post').readAsStringSync();
  final lib = File('post/pero.lib.js').readAsStringSync();
  return runImportPost(JsPostRunner(),
      script: script, files: files, timeout: const Duration(seconds: 30), library: lib);
}

void main() {
  setUpAll(() => expect(prepareQuickJs(), isTrue, reason: 'flutter build windows --debug を一度実行してください'));

  test('メタ情報の role(省略はexport、importはimport、不正は無効)', () {
    final imp = parsePostMeta(File('post/postgresql.import.post').readAsStringSync())!;
    expect(imp.role, PostRole.import);
    expect(checkPostApiVersion(imp), isNull);
    expect(parsePostMeta(File('post/postgresql.post').readAsStringSync())!.role, PostRole.export);
    expect(parsePostMeta('// @post name=a b targetDb=mysql apiVersion=4 role=import')!.name, 'a b');
    expect(parsePostMeta('// @post name=a targetDb=mysql apiVersion=4 role=zzz'), isNull);
  });

  test('インポートのポストファイルは、カタログのエクスポート一覧に出ない', () {
    final c = PostCatalog.scan('post');
    expect(c.imports.map((f) => f.fileName), contains('postgresql.import.post'));
    expect(c.valid.map((f) => f.fileName), isNot(contains('postgresql.import.post')));
    expect(c.valid.map((f) => f.fileName), contains('postgresql.post'));
  });

  test('ポストファイルがSQLを解析し、INSERT/UPDATE・コマンドは解析できないものになる', () async {
    final data = await runPost([const SqlImportFile(name: 'a.sql', text: sql)]);
    expect((data['tables'] as List).length, 2);
    expect((data['functions'] as List).length, 1);
    expect((data['triggers'] as List).length, 1);
    final views = (data['views'] as List).cast<Map>();
    expect(views.map((v) => v['name']), ['v1', 'import_01', 'import_02']);
    final un = (data['unparsed'] as List).cast<Map>().map((u) => u['kind']).toList();
    expect(un, containsAll(['INSERT', 'UPDATE', 'GRANT', 'SELECT']));
    expect(un.where((k) => k == 'SELECT').length, 1); // FROM句のない select 1
  });

  test('変換: 新しいモデルへ取り込み、保存と復元の往復ができる', () async {
    final data = await runPost([const SqlImportFile(name: 'a.sql', text: sql)]);
    final model = ErModel.empty(postPath: '');
    final cmd = ImportSqlCommand(diagramId: model.diagrams.first.id, data: data);
    cmd.apply(CommandContext(model, () => EntityLayouter(model)));
    final rep = cmd.report!;
    expect(rep.tables, 2);
    expect(rep.relationships, 1);
    expect(rep.triggers, 1);
    final parent = model.tables.firstWhere((t) => t.physicalName == 'parent');
    expect(parent.comment, '親');
    expect(parent.columns.first.typeId, 'auto');
    expect(parent.columns.firstWhere((c) => c.physicalName == 'name').logicalName, '名前');
    final child = model.tables.firstWhere((t) => t.physicalName == 'child');
    expect(child.columns.firstWhere((c) => c.physicalName == 'id').pk, isTrue);
    expect(child.uniques.single.name, 'child_uq');
    expect(child.indexes.single.name, 'child_idx');
    expect(child.triggers.single.name, 'child_trg');
    final r = model.relationships.single;
    expect(r.onDelete, RefAction.cascade);
    expect(model.views.map((v) => v.physicalName), ['v1', 'import_01', 'import_02']);
    expect(model.diagrams.first.placements.length, 5);
    // 往復
    final prep = PeroFile.prepare(model);
    expect(prep.isOk, isTrue, reason: '${prep.error}');
  });

  test('追加取り込み: 同名は取り込まず、import_XX は空き番号になり、Undoで戻せる', () async {
    final data = await runPost([const SqlImportFile(name: 'a.sql', text: sql)]);
    final model = ErModel.empty(postPath: '');
    final history = CommandHistory(CommandContext(model, () => EntityLayouter(model)));
    final did = model.diagrams.first.id;
    history.execute(ImportSqlCommand(diagramId: did, data: data));
    final before = PeroEncoder.encodeCompact(PeroEncoder.toMap(model));
    final second = ImportSqlCommand(diagramId: did, data: data);
    history.execute(second);
    final rep = second.report!;
    expect(model.tables.length, 2);
    expect(rep.tables, 0);
    expect(rep.unparsed.where((u) => u.reason.contains('既にある')).length, greaterThanOrEqualTo(2));
    expect(model.views.map((v) => v.physicalName).toSet().length, model.views.length);
    expect(model.views.map((v) => v.physicalName), containsAll(['import_03', 'import_04']));
    history.undo();
    expect(PeroEncoder.encodeCompact(PeroEncoder.toMap(model)), before);
  });

  test('コマンドはシリアライズして再生できる', () async {
    final data = await runPost([const SqlImportFile(name: 'a.sql', text: sql)]);
    final model = ErModel.empty(postPath: '');
    final cmd = ImportSqlCommand(diagramId: model.diagrams.first.id, data: data);
    final again = commandFromJson(cmd.toJson()) as ImportSqlCommand;
    again.apply(CommandContext(model, () => EntityLayouter(model)));
    expect(model.tables.length, 2);
  });
  test('取り込めなかった文は、別ファイルへ保存できるテキストになる', () async {
    final data = await runPost([const SqlImportFile(name: 'a.sql', text: sql)]);
    final rep = SqlImportConverter(ErModel.empty(postPath: '')).convert(data);
    final text = unparsedAsText(rep.unparsed);
    expect(text, contains('[INSERT]'));
    expect(text, contains("INSERT INTO parent (id, name) VALUES (1, 'a;b');"));
    expect(text, contains('a.sql:'));
  });
  test('ひな形(post/template)は、そのまま動く', () async {
    final lib = File('post/pero.lib.js').readAsStringSync();
    final exp = File('post/template/export.post').readAsStringSync();
    expect(parsePostMeta(exp)!.role, PostRole.export);
    final r = await GenerationService(JsPostRunner())
        .generate(modelForeignKeys(), exp, timeout: const Duration(seconds: 20), library: lib);
    expect(r.text, contains('CREATE TABLE'));
    expect(r.text, contains('FOREIGN KEY'));
    final imp = File('post/template/import.post').readAsStringSync();
    expect(parsePostMeta(imp)!.role, PostRole.import);
    final data = await runImportPost(JsPostRunner(),
        script: imp,
        files: [const SqlImportFile(name: 't.sql', text: 'CREATE TABLE t (id integer PRIMARY KEY, n varchar(10) NOT NULL DEFAULT 1);\nSELECT * FROM t;\nINSERT INTO t VALUES (1);')],
        timeout: const Duration(seconds: 20),
        library: lib);
    expect((data['tables'] as List).length, 1);
    expect(((data['views'] as List).single as Map)['name'], 'import_01');
    expect(((data['unparsed'] as List).single as Map)['kind'], 'INSERT');
  });

  test('追加取り込み: 戻り値の表が既にモデルにあるときも、関数の依存先になり、表の後に出力される', () async {
    final model = ErModel.empty(postPath: '');
    final did = model.diagrams.first.id;
    CommandContext ctx() => CommandContext(model, () => EntityLayouter(model));
    final base = await runPost([const SqlImportFile(name: 't.sql', text: 'CREATE TABLE chg (id integer PRIMARY KEY, q integer);')]);
    ImportSqlCommand(diagramId: did, data: base).apply(ctx());
    const fn = 'CREATE OR REPLACE FUNCTION f(p_a integer, p_b integer DEFAULT NULL, OUT o integer) RETURNS chg AS \$\$ SELECT * FROM chg; \$\$ LANGUAGE sql;\n'
        "COMMENT ON FUNCTION f IS '@omit';";
    final data = await runPost([const SqlImportFile(name: 'f.sql', text: fn)]);
    ImportSqlCommand(diagramId: did, data: data).apply(ctx());
    final f = model.methods.firstWhere((m) => m.name == 'f');
    expect(f.dependsOnTableIds, [model.tables.single.id]);
    // 引数を省略した COMMENT ON FUNCTION は、CREATE FUNCTION の引数(既定値と OUT を除く)になる
    expect(f.args, 'p_a integer, p_b integer');
    final sql = await generateSql(model);
    expect(sql.indexOf('CREATE TABLE chg'), lessThan(sql.indexOf('FUNCTION f(')));
    expect(sql, contains('COMMENT ON FUNCTION f(p_a integer, p_b integer) IS'));
  });
}
