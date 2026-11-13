import 'package:project_er_operation/model/model.dart';

ColumnDef col(ErModel m, String phys, String typeId,
        {String logical = '',
        bool pk = false,
        bool notNull = false,
        int? length,
        DefaultKind defKind = DefaultKind.none,
        String defValue = '',
        int? defMethod,
        String defExpression = '',
        String comment = ''}) =>
    ColumnDef(
      id: m.allocateId(),
      logicalName: logical,
      physicalName: phys,
      typeId: typeId,
      length: length,
      pk: pk,
      notNull: notNull || pk,
      defaultKind: defKind,
      defaultValue: defValue,
      defaultMethodId: defMethod,
      defaultExpression: defExpression,
      comment: comment,
    );

TableEntity table(ErModel m, String phys, List<ColumnDef> cols,
    {String logical = '', bool place = true, double x = 40, double y = 40}) {
  final t = TableEntity(
      id: m.allocateId(), logicalName: logical, physicalName: phys, columns: cols);
  m.entities.add(t);
  if (place) m.diagrams.first.placements.add(Placement(entityId: t.id, x: x, y: y));
  return t;
}

/// 全種類のオブジェクトを含むモデル(保存の往復テスト用)。
ErModel fullModel() {
  final m = ErModel.empty();
  m.properties
    ..outputFileName = 'out'
    ..outputFolder = r'C:\out'
    ..startQuery = '-- start'
    ..endQuery = '-- end'
    ..schema = 'app'
    ..includeSchema = true;
  m.types.addAll([
    DataType(
        id: 'custom_2',
        displayName: 'point_t',
        physical: {DbKind.postgresql: 'point_t'},
        kind: TypeKind.composite,
        fields: [TypeField(name: 'x', typeId: 'integer'), TypeField(name: 'label', typeId: 'varchar', length: 20)]),
    DataType(
        id: 'custom_3',
        displayName: 'status_t',
        physical: {DbKind.postgresql: 'status_t'},
        kind: TypeKind.enumeration,
        enumValues: ['open', 'closed']),
  ]);
  m.types.add(DataType(
      id: 'custom_1',
      displayName: 'money',
      comment: '金額',
      schema: 'dom',
      paramKind: ParamKind.precisionScale,
      defaultPrecision: 10,
      defaultScale: 2,
      category: TypeCategory.number,
      physical: {DbKind.postgresql: 'numeric({precision},{scale})'}));
  final fn = MethodDef(
      id: m.allocateId(),
      name: 'now_utc',
      schema: 'util',
      comment: '現在のUTC時刻',
      args: '',
      call: {DbKind.postgresql: "timezone('utc', now())", DbKind.mysql: '', DbKind.sqlserver: '', DbKind.sqlite: ''},
      bodies: {DbKind.postgresql: 'CREATE FUNCTION now_utc() ...', DbKind.mysql: '', DbKind.sqlserver: '', DbKind.sqlite: ''});
  final trg = MethodDef(
      id: m.allocateId(),
      kind: MethodKind.trigger,
      name: 'touch',
      bodies: {DbKind.postgresql: 'CREATE FUNCTION touch() ...', DbKind.mysql: '', DbKind.sqlserver: '', DbKind.sqlite: ''});
  m.methods.addAll([fn, trg]);
  m.patterns.add(CommonColumnPattern(
    id: m.allocateId(),
    name: '監査列',
    include: '^.*\$',
    exclude: '^audit_.*',
    position: PatternPosition.end,
    columns: [
      ColumnDef(
          id: m.allocateId(),
          logicalName: '作成日時',
          physicalName: 'created_at',
          typeId: 'timestamp',
          notNull: true,
          defaultKind: DefaultKind.method,
          defaultMethodId: fn.id),
    ],
  ));
  final customers = table(m, 'customers', [
    col(m, 'id', 'auto', pk: true, logical: 'ID'),
    col(m, 'name', 'varchar', length: 100, notNull: true, logical: '名前', comment: '顧客名'),
  ], logical: '顧客');
  final orders = table(m, 'orders', [
    col(m, 'id', 'auto', pk: true),
    col(m, 'customer_id', 'integer', notNull: true),
    col(m, 'price', 'custom_1', defKind: DefaultKind.value, defValue: '0'),
    col(m, 'due', 'date', defKind: DefaultKind.expression, defExpression: 'CURRENT_DATE + 30'),
  ], logical: '注文', x: 400);
  fn.dependsOnTableIds = [customers.id];
  orders.checks.add(CheckDef(id: m.allocateId(), nameMode: NameMode.manual, name: 'orders_ck_price', expression: 'price >= 0'));
  orders.indexes.add(ConstraintDef(id: m.allocateId(), columnIds: [orders.columns[1].id]));
  orders.uniques.add(ConstraintDef(
      id: m.allocateId(),
      nameMode: NameMode.manual,
      name: 'orders_uq_custom',
      columnIds: [orders.columns[0].id, orders.columns[1].id],
      nullsNotDistinct: true));
  orders.triggers.add(TriggerDef(
      id: m.allocateId(),
      source: TriggerSource.public,
      methodId: trg.id,
      events: [TriggerEvent.insert, TriggerEvent.update],
      timing: TriggerTiming.after,
      args: "'80'",
      updateColumnIds: [orders.columns[2].id],
      when: 'NEW.price > 0'));
  orders.triggers.add(TriggerDef(
      id: m.allocateId(),
      inlineBodies: {for (final d in DbKind.values) d: d == DbKind.postgresql ? 'CREATE FUNCTION {{trigger}}() ...' : ''}));
  m.relationships.add(Relationship(
    id: m.allocateId(),
    parentId: customers.id,
    childId: orders.id,
    columnPairs: [ColumnPair(parentColumnId: customers.columns[0].id, childColumnId: orders.columns[1].id)],
    onDelete: RefAction.cascade,
    onUpdate: RefAction.none,
    deferrable: Deferrable.deferred,
  ));
  final joinView = ViewEntity(
    id: m.allocateId(),
    physicalName: 'v_orders',
    logicalName: '注文ビュー',
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
      where: 'o.price > 0',
    ),
  );
  m.entities.add(joinView);
  final fnView = ViewEntity(
    id: m.allocateId(),
    physicalName: 'v_fn',
    viewType: ViewType.function,
    function: ViewFunctionDef(methodId: fn.id, args: ['1', "'a'"], columns: [
      FunctionReturnColumn(name: 'x', typeId: 'integer'),
    ]),
  );
  m.entities.add(fnView);
  final sqlView = ViewEntity(
    id: m.allocateId(),
    physicalName: 'v_sql',
    comment: 'SQLビュー',
    viewType: ViewType.sql,
    sql: ViewSqlDef(sql: 'SELECT id FROM customers', columns: [FunctionReturnColumn(name: 'id', typeId: 'integer')]),
  );
  m.entities.add(sqlView);
  m.diagrams.first
    ..placements.add(Placement(entityId: joinView.id, x: 100, y: 500, collapsed: true))
    ..placements.add(Placement(entityId: fnView.id, x: 500, y: 500))
    ..placements.add(Placement(entityId: sqlView.id, x: 800, y: 500))
    ..view = DiagramView(zoom: 1.5, scrollX: 10, scrollY: 20);
  m.diagrams.add(Diagram(
      id: m.allocateId(),
      name: 'ダイアグラム2',
      pageSize: PageSize.a4,
      orientation: Orientation.portrait,
      pageRows: 2,
      pageCols: 3,
      schema: 'other'));
  return m;
}

/// ビュー定義を別IDで複製する(結合ビューの検証用)。
class PeroDecoderSafe {
  static ViewEntity copyOf(ViewEntity v, int id) => ViewEntity(
        id: id,
        physicalName: v.physicalName,
        viewType: v.viewType,
        join: v.join.copy(),
        function: v.function.copy(),
      );
}
