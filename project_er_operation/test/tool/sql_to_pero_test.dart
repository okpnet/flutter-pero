import 'package:flutter_test/flutter_test.dart';
import 'package:project_er_operation/model/model.dart';
import 'package:project_er_operation/persistence/persistence.dart';

import '../../tool/sql_to_pero.dart';

const _sql = r'''
\c test_db
CREATE TYPE tests.mood AS ENUM ('sad', 'ok');
CREATE TYPE tests.pt AS (x integer, label varchar);
CREATE OR REPLACE FUNCTION tests.touch() RETURNS trigger AS
$BODY$
BEGIN RETURN NEW; END;
$BODY$ LANGUAGE plpgsql;
CREATE OR REPLACE FUNCTION tests.count_nodes(OUT n integer) AS $$ SELECT count(*) FROM tests.node $$ LANGUAGE sql;
CREATE TABLE tests.node (
    node_id uuid default gen_random_uuid(),
    parent_id uuid default null,
    name varchar(20) default '',
    qty decimal(10,2) default 1,
    created timestamp default now(),
    due date default CURRENT_DATE + 30,
    span interval default '1 day',
    flag boolean default 'f',
    mood tests.mood
);
create unique index node_PKI on tests.node(node_id);
alter table tests.node add constraint node_PKC primary key (node_id);
alter table tests.node add constraint node_IX1 unique nulls not distinct (name, qty);
alter table tests.node add constraint node_CK1 check (qty >= 0);
alter table tests.node add constraint node_FK1 foreign key (parent_id) references tests.node (node_id) DEFERRABLE INITIALLY DEFERRED;
CREATE TRIGGER trg_node BEFORE INSERT OR UPDATE OF name, qty ON tests.node FOR EACH ROW EXECUTE FUNCTION tests.touch('80');
comment on type tests.pt is '点の型';
comment on table tests.node is 'ノード';
comment on column tests.node.name is '名前';
comment on function tests.count_nodes() is '件数';
create view tests.v_node as
-- コメント
SELECT node_id FROM tests.node;
comment on view tests.v_node is E'@omit\nビュー';
DROP VIEW IF EXISTS tests.v_node;
''';

void main() {
  late Importer imp;
  late ErModel m;

  setUpAll(() {
    imp = Importer()..run(splitSql(_sql, 'a.sql'));
    m = imp.model;
  });

  test('テーブル、列、型、主キー、コメント', () {
    final t = m.tables.single;
    expect(t.physicalName, 'node');
    expect(t.logicalName, 'ノード');
    expect(t.columns.length, 9);
    expect(t.columns.first.pk, isTrue);
    final name = t.columns.firstWhere((c) => c.physicalName == 'name');
    expect((name.typeId, name.length, name.logicalName), ('varchar', 20, '名前'));
    final qty = t.columns.firstWhere((c) => c.physicalName == 'qty');
    expect((qty.typeId, qty.precision, qty.scale), ('numeric', 10, 2));
    expect(t.columns.firstWhere((c) => c.physicalName == 'span').typeId, 'interval');
    expect(m.typeById('interval')?.isStandard, isTrue);
  });

  test('デフォルト: 空文字は標準メソッド、関数はメソッド、式は式、論理値は true/false', () {
    final t = m.tables.single;
    ColumnDef c(String n) => t.columns.firstWhere((x) => x.physicalName == n);
    final empty = m.methods.firstWhere((x) => x.name == emptyStringMethodName);
    expect((c('name').defaultKind, c('name').defaultMethodId), (DefaultKind.method, empty.id));
    expect(m.methodById(c('created').defaultMethodId!)!.name, 'now');
    expect(c('due').defaultKind, DefaultKind.expression);
    expect(c('due').defaultExpression, 'CURRENT_DATE + 30');
    expect((c('flag').defaultKind, c('flag').defaultValue), (DefaultKind.value, 'false'));
    expect(c('parent_id').defaultKind, DefaultKind.none);
  });

  test('ユーザー定義型: 列挙型と複合型', () {
    final mood = m.types.firstWhere((x) => x.displayName == 'mood');
    expect(mood.kind, TypeKind.enumeration);
    expect(mood.enumValues, ['sad', 'ok']);
    final pt = m.types.firstWhere((x) => x.displayName == 'pt');
    expect(pt.kind, TypeKind.composite);
    expect(pt.fields.map((f) => f.name), ['x', 'label']);
    expect(pt.fields.last.typeId, 'varchar_nolen'); // 長さなしの varchar
    expect(pt.comment, '点の型');
    expect(m.tables.single.columns.last.typeId, mood.id);
  });

  test('ユニーク(NULLS NOT DISTINCT)、CHECK制約。主キーと重複するユニークインデックスは取り込まない', () {
    final t = m.tables.single;
    expect(t.uniques.single.nullsNotDistinct, isTrue);
    expect(t.uniques.single.name, 'node_ix1');
    expect(t.checks.single.expression, 'qty >= 0');
  });

  test('自己参照の外部キーとDEFERRABLE', () {
    final r = m.relationships.single;
    expect(r.parentId, r.childId);
    expect(r.deferrable, Deferrable.deferred);
    expect(r.name, 'node_fk1');
    expect(r.dependency, isFalse);
  });

  test('トリガー: 引数、UPDATE OF の列', () {
    final g = m.tables.single.triggers.single;
    expect(g.args, "'80'");
    expect(g.events, [TriggerEvent.insert, TriggerEvent.update]);
    final names = g.updateColumnIds.map((id) => m.tables.single.columnById(id)!.physicalName);
    expect(names, ['name', 'qty']);
  });

  test('SQLビューとコメント(Eリテラル)、関数のコメントと依存テーブル', () {
    final v = m.views.single;
    expect(v.viewType, ViewType.sql);
    expect(v.sql.sql, contains('SELECT node_id FROM tests.node'));
    expect(v.comment, '@omit\nビュー');
    final fn = m.methods.firstWhere((x) => x.name == 'count_nodes');
    expect(fn.comment, '件数');
    expect(fn.dependsOnTableIds, [m.tables.single.id]);
    expect(m.methods.firstWhere((x) => x.name == 'touch').kind, MethodKind.trigger);
  });

  test('スキーマの設定と、取り込まなかった要素のログ(終了クエリのコメント)', () {
    expect((m.properties.schema, m.properties.includeSchema), ('tests', true));
    expect(m.properties.endQuery, contains('-- [PERO 取り込みログ]'));
    expect(m.properties.endQuery, contains('DROP VIEW IF'));
  });

  test('生成した .pero は整合性確認で修復が不要', () {
    final prep = PeroFile.prepare(m);
    expect(prep.isOk, isTrue);
    expect(prep.repairs.items, isEmpty);
  });
}
