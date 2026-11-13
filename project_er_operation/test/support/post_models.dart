import 'package:project_er_operation/command/command.dart';
import 'package:project_er_operation/model/model.dart';

import 'sample_models.dart';

CommandHistory _h(ErModel m) => CommandHistory(CommandContext(m, () => EntityLayouter(m)));

/// 1. 単純なテーブル(auto PK、NotNull、デフォルト値、コメント、予約語)
ErModel modelSimple() {
  final m = ErModel.empty();
  table(m, 'users', [
    col(m, 'id', 'auto', pk: true),
    col(m, 'name', 'varchar', length: 100, notNull: true, comment: "O'Brien's name"),
    col(m, 'status', 'varchar', length: 10, defKind: DefaultKind.value, defValue: "it's"),
    col(m, 'score', 'numeric', defKind: DefaultKind.value, defValue: '0'),
    col(m, 'active', 'boolean', defKind: DefaultKind.value, defValue: 'true'),
    col(m, 'order', 'integer'), // 予約語
  ], logical: 'ユーザー');
  m.tables.first.comment = 'ユーザー表';
  return m;
}

/// 2. 外部キー、インデックス、ユニーク、ON DELETE / ON UPDATE
ErModel modelForeignKeys() {
  final m = ErModel.empty();
  final customers = table(m, 'customers', [
    col(m, 'id', 'auto', pk: true),
    col(m, 'email', 'varchar', length: 255, notNull: true),
  ]);
  final orders = table(m, 'orders', [col(m, 'order_no', 'integer', pk: true), col(m, 'memo', 'text')]);
  customers.uniques.add(ConstraintDef(id: m.allocateId(), columnIds: [customers.columns[1].id]));
  final h = _h(m);
  final add = AddRelationshipCommand(tableAId: customers.id, tableBId: orders.id);
  h.execute(add);
  h.execute(UpdateRelationshipCommand(add.createdId!, {'onDelete': 'cascade', 'onUpdate': 'set_null'}));
  final o = m.tableById(orders.id)!;
  o.indexes.add(ConstraintDef(id: m.allocateId(), columnIds: [o.columns[1].id, o.columns[0].id]));
  o.indexes.add(ConstraintDef(
      id: m.allocateId(), nameMode: NameMode.manual, name: 'orders_by_memo', columnIds: [o.columns[2].id]));
  return m;
}

/// 3. 共通列、メソッドのデフォルト、外部定義の関数
ErModel modelCommonColumns() {
  final m = ErModel.empty();
  final now = MethodDef(
      id: m.allocateId(),
      name: 'now',
      external: true,
      call: {DbKind.postgresql: 'now()', DbKind.mysql: '', DbKind.sqlserver: '', DbKind.sqlite: ''});
  final audit = MethodDef(id: m.allocateId(), name: 'audit_user', bodies: {
    DbKind.postgresql: 'CREATE FUNCTION audit_user() RETURNS text AS \$\$ SELECT current_user \$\$ LANGUAGE sql',
    DbKind.mysql: '',
    DbKind.sqlserver: '',
    DbKind.sqlite: ''
  });
  m.methods.addAll([now, audit]);
  m.patterns.add(CommonColumnPattern(id: m.allocateId(), name: '共通', include: 'mst_.*', columns: [
    ColumnDef(
        id: m.allocateId(),
        physicalName: 'created_at',
        typeId: 'timestamp',
        notNull: true,
        defaultKind: DefaultKind.method,
        defaultMethodId: now.id),
    ColumnDef(
        id: m.allocateId(),
        physicalName: 'created_by',
        typeId: 'varchar',
        length: 50,
        defaultKind: DefaultKind.method,
        defaultMethodId: audit.id),
  ]));
  m.patterns.add(CommonColumnPattern(
      id: m.allocateId(),
      name: 'ID',
      include: 'mst_.*',
      position: PatternPosition.start,
      columns: [ColumnDef(id: m.allocateId(), physicalName: 'tenant_id', typeId: 'integer', notNull: true)]));
  final t = table(m, 'mst_item', [col(m, 'id', 'integer', pk: true), col(m, 'name', 'text')]);
  t.indexes.add(ConstraintDef(id: m.allocateId(), columnIds: [m.patterns[1].columns[0].id, t.columns[0].id]));
  table(m, 'tmp_item', [col(m, 'id', 'integer', pk: true)], x: 400);
  return m;
}

/// 4. ビュー(結合ビュー、関数ビュー)
ErModel modelViews() {
  final m = ErModel.empty();
  final fn = MethodDef(id: m.allocateId(), name: 'recent_orders', bodies: {
    DbKind.postgresql: 'CREATE FUNCTION recent_orders(n integer) RETURNS TABLE(x integer) AS \$\$ SELECT 1 \$\$ LANGUAGE sql;',
    DbKind.mysql: '',
    DbKind.sqlserver: '',
    DbKind.sqlite: ''
  });
  m.methods.add(fn);
  final customers = table(m, 'customers', [col(m, 'id', 'integer', pk: true), col(m, 'name', 'text')]);
  final orders = table(m, 'orders', [
    col(m, 'id', 'integer', pk: true),
    col(m, 'customer_id', 'integer'),
    col(m, 'total', 'numeric'),
  ], x: 400);
  m.entities.add(ViewEntity(
    id: m.allocateId(),
    physicalName: 'v_orders',
    preQuery: '-- before view',
    postQuery: '-- after view',
    comment: '注文一覧',
    join: ViewJoinDef(
      sources: [
        ViewSource(alias: 'o', entityId: orders.id),
        ViewSource(alias: 'c', entityId: customers.id, joinType: JoinType.left, on: [
          JoinOn(leftAlias: 'o', leftColumnId: orders.columns[1].id, rightColumnId: customers.columns[0].id)
        ]),
      ],
      columns: [
        ViewOutputColumn(alias: 'o', columnId: orders.columns[0].id, name: 'order_id'),
        ViewOutputColumn(alias: 'c', columnId: customers.columns[1].id, name: 'customer_name'),
      ],
      where: 'o.total > 0',
    ),
  ));
  m.entities.add(ViewEntity(
    id: m.allocateId(),
    physicalName: 'v_recent',
    viewType: ViewType.function,
    function: ViewFunctionDef(methodId: fn.id, args: ['10'], columns: [FunctionReturnColumn(name: 'x', typeId: 'integer')]),
  ));
  return m;
}

/// 5. トリガー、開始/終了クエリ、生成前後クエリ、循環する外部キー
ErModel modelTriggersAndCycle() {
  final m = ErModel.empty();
  m.properties
    ..startQuery = 'SET client_encoding = \'UTF8\';'
    ..endQuery = '-- end of file';
  final touch = MethodDef(id: m.allocateId(), kind: MethodKind.trigger, name: 'touch_updated', bodies: {
    DbKind.postgresql: 'CREATE FUNCTION touch_updated() RETURNS trigger AS \$\$ BEGIN NEW.updated = now(); RETURN NEW; END \$\$ LANGUAGE plpgsql;',
    DbKind.mysql: '',
    DbKind.sqlserver: '',
    DbKind.sqlite: ''
  });
  m.methods.add(touch);
  final a = table(m, 'a', [col(m, 'id', 'integer', pk: true), col(m, 'b_id', 'integer'), col(m, 'updated', 'timestamp')]);
  final b = table(m, 'b', [col(m, 'id', 'integer', pk: true), col(m, 'a_id', 'integer')], x: 400);
  a.preQuery = '-- pre a';
  a.postQuery = '-- post a';
  a.triggers.add(TriggerDef(
      id: m.allocateId(),
      source: TriggerSource.public,
      methodId: touch.id,
      events: [TriggerEvent.insert, TriggerEvent.update],
      when: 'OLD.* IS DISTINCT FROM NEW.*'));
  b.triggers.add(TriggerDef(
      id: m.allocateId(),
      source: TriggerSource.public,
      methodId: touch.id,
      timing: TriggerTiming.after,
      forEach: TriggerForEach.statement));
  b.triggers.add(TriggerDef(id: m.allocateId(), inlineBodies: {
    DbKind.postgresql: 'CREATE FUNCTION {{trigger}}() RETURNS trigger AS \$\$ BEGIN RETURN NEW; END \$\$ LANGUAGE plpgsql',
    DbKind.mysql: '',
    DbKind.sqlserver: '',
    DbKind.sqlite: ''
  }));
  // a.b_id -> b.id (aが子)、b.a_id -> a.id (bが子): 循環
  m.relationships.add(Relationship(
      id: m.allocateId(),
      parentId: b.id,
      childId: a.id,
      columnPairs: [ColumnPair(parentColumnId: b.columns[0].id, childColumnId: a.columns[1].id)],
      dependency: false));
  m.relationships.add(Relationship(
      id: m.allocateId(),
      parentId: a.id,
      childId: b.id,
      columnPairs: [ColumnPair(parentColumnId: a.columns[0].id, childColumnId: b.columns[1].id)],
      dependency: false,
      onDelete: RefAction.setNull,
      onUpdate: RefAction.none));
  return m;
}

/// 6. 形式2の機能: スキーマ、ユーザー定義型、CHECK、NULLS NOT DISTINCT、DEFERRABLE、自己参照、
///    トリガーの引数とUPDATE OF、SQLビュー、依存テーブルのあるファンクション、式のデフォルト、空文字のデフォルト
ErModel modelNewFeatures() {
  final m = ErModel.empty();
  m.properties
    ..schema = 'app'
    ..includeSchema = true
    ..startQuery = 'SET search_path TO app, public;';
  m.types.addAll([
    DataType(
        id: 'custom_1',
        displayName: 'status_t',
        comment: "状態's",
        physical: {DbKind.postgresql: 'status_t'},
        kind: TypeKind.enumeration,
        enumValues: ['open', "it's closed"]),
    DataType(
        id: 'custom_2',
        displayName: 'point_t',
        schema: 'types',
        physical: {DbKind.postgresql: 'point_t'},
        kind: TypeKind.composite,
        fields: [TypeField(name: 'x', typeId: 'integer'), TypeField(name: 'label', typeId: 'varchar', length: 20)]),
  ]);
  final emptyId = m.methods.firstWhere((x) => x.name == emptyStringMethodName).id;
  final touch = MethodDef(
      id: m.allocateId(),
      kind: MethodKind.trigger,
      name: 'touch',
      schema: 'fn',
      comment: '更新日時を設定する',
      bodies: {for (final d in DbKind.values) d: d == DbKind.postgresql ? 'CREATE FUNCTION touch() RETURNS trigger AS \$\$ BEGIN RETURN NEW; END \$\$ LANGUAGE plpgsql' : ''});
  final count = MethodDef(
      id: m.allocateId(),
      name: 'count_nodes',
      comment: 'ノード数',
      args: '',
      bodies: {for (final d in DbKind.values) d: d == DbKind.postgresql ? 'CREATE FUNCTION count_nodes() RETURNS bigint AS \$\$ SELECT count(*) FROM node \$\$ LANGUAGE sql' : ''});
  m.methods.addAll([touch, count]);
  final node = table(m, 'node', [
    col(m, 'id', 'auto', pk: true),
    col(m, 'parent_id', 'integer'),
    col(m, 'name', 'varchar', length: 20, defKind: DefaultKind.method, defMethod: emptyId),
    col(m, 'qty', 'numeric'),
    col(m, 'due', 'date', defKind: DefaultKind.expression, defExpression: 'CURRENT_DATE + 30'),
    col(m, 'state', 'custom_1'),
  ], logical: 'ノード');
  node.uniques.add(ConstraintDef(
      id: m.allocateId(),
      nameMode: NameMode.manual,
      name: 'node_uq',
      columnIds: [node.columns[2].id, node.columns[3].id],
      nullsNotDistinct: true));
  node.checks.add(CheckDef(id: m.allocateId(), expression: 'qty >= 0'));
  node.checks.add(CheckDef(id: m.allocateId(), nameMode: NameMode.manual, name: 'node_state_ck', expression: "state <> 'closed' OR qty = 0"));
  node.triggers.add(TriggerDef(
      id: m.allocateId(),
      source: TriggerSource.public,
      methodId: touch.id,
      events: [TriggerEvent.insert, TriggerEvent.update],
      updateColumnIds: [node.columns[2].id, node.columns[3].id],
      args: "'80', 1"));
  count.dependsOnTableIds = [node.id];
  final viewFn = MethodDef(
      id: m.allocateId(),
      name: 'view_rows',
      bodies: {for (final d in DbKind.values) d: d == DbKind.postgresql ? 'CREATE FUNCTION view_rows() RETURNS bigint AS \$\$ SELECT count(*) FROM app.v_node \$\$ LANGUAGE sql' : ''});
  m.methods.add(viewFn);
  final h = _h(m);
  final self = AddRelationshipCommand(tableAId: node.id, tableBId: node.id);
  h.execute(self);
  h.execute(UpdateRelationshipCommand(self.createdId!, {'deferrable': 'deferred', 'onDelete': 'set_null'}));
  final other = table(m, 'other', [col(m, 'id', 'auto', pk: true), col(m, 'node_id', 'integer')], x: 500);
  m.diagrams.first.placements.removeWhere((p) => p.entityId == other.id);
  m.diagrams.add(Diagram(id: m.allocateId(), name: 'ダイアグラム2', schema: 'other')
    ..placements.add(Placement(entityId: other.id, x: 40, y: 40)));
  final fk = AddRelationshipCommand(tableAId: node.id, tableBId: other.id, parentId: node.id);
  h.execute(fk);
  h.execute(UpdateRelationshipCommand(fk.createdId!, {'deferrable': 'immediate'}));
  final v = ViewEntity(
    id: m.allocateId(),
    physicalName: 'v_node',
    comment: 'ノードのビュー',
    viewType: ViewType.sql,
    sql: ViewSqlDef(sql: 'SELECT id, name FROM app.node WHERE qty > 0;\n'),
  );
  m.entities.add(v);
  m.diagrams.first.placements.add(Placement(entityId: v.id, x: 300, y: 40));
  viewFn.dependsOnTableIds = [node.id, v.id]; // ビューへの依存は、ビューの後に出力する
  return m;
}
