import 'enums.dart';

/// 列(6.2)。共通列パターンの列(8.2)も同じ形を使う(pkはfalse固定)。
class ColumnDef {
  ColumnDef({
    required this.id,
    this.logicalName = '',
    this.physicalName = '',
    this.typeId = 'varchar',
    this.length,
    this.precision,
    this.scale,
    this.pk = false,
    this.notNull = false,
    this.defaultKind = DefaultKind.none,
    this.defaultValue = '',
    this.defaultMethodId,
    this.defaultExpression = '',
    this.comment = '',
  });

  final int id;
  String logicalName;
  String physicalName;
  String typeId;
  int? length;
  int? precision;
  int? scale;
  bool pk;
  bool notNull;
  DefaultKind defaultKind;
  String defaultValue;
  int? defaultMethodId;

  /// デフォルトの種別が「式」のときの式(6.2-4)。そのまま出力する。
  String defaultExpression;
  String comment;

  ColumnDef copy() => ColumnDef(
        id: id,
        logicalName: logicalName,
        physicalName: physicalName,
        typeId: typeId,
        length: length,
        precision: precision,
        scale: scale,
        pk: pk,
        notNull: notNull,
        defaultKind: defaultKind,
        defaultValue: defaultValue,
        defaultMethodId: defaultMethodId,
        defaultExpression: defaultExpression,
        comment: comment,
      );
}

/// インデックス / ユニーク制約(6.4)。
class ConstraintDef {
  ConstraintDef({
    required this.id,
    this.nameMode = NameMode.auto,
    this.name = '',
    List<int>? columnIds,
    this.nullsNotDistinct = false,
  }) : columnIds = columnIds ?? [];

  final int id;
  NameMode nameMode;
  String name;
  List<int> columnIds;

  /// ユニークのみ。NULLを同値として扱う(NULLS NOT DISTINCT。6.4-2)。
  bool nullsNotDistinct;

  ConstraintDef copy() => ConstraintDef(
      id: id,
      nameMode: nameMode,
      name: name,
      columnIds: List.of(columnIds),
      nullsNotDistinct: nullsNotDistinct);
}

/// CHECK制約(6.4-5)。
class CheckDef {
  CheckDef({
    required this.id,
    this.nameMode = NameMode.auto,
    this.name = '',
    this.expression = '',
    this.mode = CheckMode.expression,
    this.join = CheckJoin.and,
    List<CheckCondition>? conditions,
  }) : conditions = conditions ?? [];

  final int id;
  NameMode nameMode;
  String name;

  /// 記述方法。式のとき [expression] を、条件のとき [conditions] を使う(使わない方も保持する)。
  CheckMode mode;

  /// 検査式(括弧の内側)。そのまま出力する。
  String expression;

  /// 条件が複数のときの結合。
  CheckJoin join;

  /// 条件(列、演算子、値)。SQLへの変換(型に合わせた値の書き方)は、ポストファイルが行う。
  List<CheckCondition> conditions;

  CheckDef copy() => CheckDef(
      id: id,
      nameMode: nameMode,
      name: name,
      expression: expression,
      mode: mode,
      join: join,
      conditions: conditions.map((c) => c.copy()).toList());
}

/// CHECK制約の1つの条件。列は、実列または共通列(8.2)のIDで参照する。
class CheckCondition {
  CheckCondition({required this.columnId, this.operator = CheckOperator.eq, List<String>? values})
      : values = values ?? [''];

  int columnId;
  CheckOperator operator;

  /// 値(演算子により個数が決まる。[CheckOperator.valueCount])。引用符は付けずに入力する。
  List<String> values;

  CheckCondition copy() => CheckCondition(columnId: columnId, operator: operator, values: List.of(values));
}

/// トリガー(6.5)。
class TriggerDef {
  TriggerDef({
    required this.id,
    this.source = TriggerSource.inline,
    this.methodId,
    Map<DbKind, String>? inlineBodies,
    this.nameMode = NameMode.auto,
    this.name = '',
    this.timing = TriggerTiming.before,
    List<TriggerEvent>? events,
    this.forEach = TriggerForEach.row,
    this.when = '',
    this.args = '',
    List<int>? updateColumnIds,
  })  : updateColumnIds = updateColumnIds ?? [],
        inlineBodies = inlineBodies ?? {for (final d in DbKind.values) d: ''},
        events = events ?? [TriggerEvent.insert];

  final int id;
  TriggerSource source;
  int? methodId;
  Map<DbKind, String> inlineBodies;
  NameMode nameMode;
  String name;
  TriggerTiming timing;
  List<TriggerEvent> events;
  TriggerForEach forEach;
  String when;

  /// トリガー関数へ渡す引数(`EXECUTE FUNCTION f(引数)` の括弧の内側。6.5-2)。
  String args;

  /// UPDATE を限定する列(`UPDATE OF 列...`)。空のときはテーブル全体の UPDATE(6.5-2)。
  List<int> updateColumnIds;

  TriggerDef copy() => TriggerDef(
        id: id,
        source: source,
        methodId: methodId,
        inlineBodies: Map.of(inlineBodies),
        nameMode: nameMode,
        name: name,
        timing: timing,
        events: List.of(events),
        forEach: forEach,
        when: when,
        args: args,
        updateColumnIds: List.of(updateColumnIds),
      );
}

/// エンティティ(テーブルとビューの総称)。ERオブジェクトとしてIDとロックを持つ。
sealed class Entity {
  Entity({
    required this.id,
    this.logicalName = '',
    this.physicalName = '',
    this.comment = '',
    this.locked = false,
    this.preQuery = '',
    this.postQuery = '',
  });

  final int id;
  String logicalName;
  String physicalName;
  String comment;
  bool locked;
  String preQuery;
  String postQuery;

  EntityKind get kind;

  /// 「論理名（物理名）」の表示用文字列。
  String get displayLabel {
    if (logicalName.isEmpty) return physicalName;
    if (physicalName.isEmpty) return logicalName;
    return '$logicalName（$physicalName）';
  }

  Entity copy();
}

class TableEntity extends Entity {
  TableEntity({
    required super.id,
    super.logicalName,
    super.physicalName,
    super.comment,
    super.locked,
    super.preQuery,
    super.postQuery,
    List<ColumnDef>? columns,
    List<ConstraintDef>? indexes,
    List<ConstraintDef>? uniques,
    List<CheckDef>? checks,
    List<TriggerDef>? triggers,
  })  : columns = columns ?? [],
        indexes = indexes ?? [],
        uniques = uniques ?? [],
        checks = checks ?? [],
        triggers = triggers ?? [];

  List<ColumnDef> columns;
  List<ConstraintDef> indexes;
  List<ConstraintDef> uniques;
  List<CheckDef> checks;
  List<TriggerDef> triggers;

  @override
  EntityKind get kind => EntityKind.table;

  ColumnDef? columnById(int cid) {
    for (final c in columns) {
      if (c.id == cid) return c;
    }
    return null;
  }

  List<ColumnDef> get primaryKeyColumns => columns.where((c) => c.pk).toList();

  @override
  TableEntity copy() => TableEntity(
        id: id,
        logicalName: logicalName,
        physicalName: physicalName,
        comment: comment,
        locked: locked,
        preQuery: preQuery,
        postQuery: postQuery,
        columns: columns.map((c) => c.copy()).toList(),
        indexes: indexes.map((c) => c.copy()).toList(),
        uniques: uniques.map((c) => c.copy()).toList(),
        checks: checks.map((c) => c.copy()).toList(),
        triggers: triggers.map((c) => c.copy()).toList(),
      );
}

/// 結合ビューの結合条件1組。
class JoinOn {
  JoinOn({required this.leftAlias, required this.leftColumnId, required this.rightColumnId});
  String leftAlias;
  int leftColumnId;
  int rightColumnId;
  JoinOn copy() =>
      JoinOn(leftAlias: leftAlias, leftColumnId: leftColumnId, rightColumnId: rightColumnId);
}

class ViewSource {
  ViewSource({
    required this.alias,
    required this.entityId,
    this.joinType = JoinType.inner,
    List<JoinOn>? on,
  }) : on = on ?? [];
  String alias;
  int entityId;
  JoinType joinType;
  List<JoinOn> on;
  ViewSource copy() => ViewSource(
      alias: alias, entityId: entityId, joinType: joinType, on: on.map((o) => o.copy()).toList());
}

class ViewOutputColumn {
  ViewOutputColumn(
      {required this.alias, required this.columnId, this.name = '', this.logicalName = ''});
  String alias;
  int columnId;
  String name;
  String logicalName;
  ViewOutputColumn copy() =>
      ViewOutputColumn(alias: alias, columnId: columnId, name: name, logicalName: logicalName);
}

class ViewJoinDef {
  ViewJoinDef({List<ViewSource>? sources, List<ViewOutputColumn>? columns, this.where = ''})
      : sources = sources ?? [],
        columns = columns ?? [];
  List<ViewSource> sources;
  List<ViewOutputColumn> columns;
  String where;
  ViewJoinDef copy() => ViewJoinDef(
      sources: sources.map((s) => s.copy()).toList(),
      columns: columns.map((c) => c.copy()).toList(),
      where: where);
}

class FunctionReturnColumn {
  FunctionReturnColumn({
    this.name = '',
    this.logicalName = '',
    this.typeId = 'integer',
    this.length,
    this.precision,
    this.scale,
  });
  String name;
  String logicalName;
  String typeId;
  int? length;
  int? precision;
  int? scale;
  FunctionReturnColumn copy() => FunctionReturnColumn(
      name: name,
      logicalName: logicalName,
      typeId: typeId,
      length: length,
      precision: precision,
      scale: scale);
}

class ViewFunctionDef {
  ViewFunctionDef({this.methodId, List<String>? args, List<FunctionReturnColumn>? columns})
      : args = args ?? [],
        columns = columns ?? [];
  int? methodId;
  List<String> args;
  List<FunctionReturnColumn> columns;
  ViewFunctionDef copy() => ViewFunctionDef(
      methodId: methodId,
      args: List.of(args),
      columns: columns.map((c) => c.copy()).toList());
}

/// SQLビューの定義(6.6)。SELECT文をそのまま持つ。出力列は表示用に手入力する。
class ViewSqlDef {
  ViewSqlDef({this.sql = '', List<FunctionReturnColumn>? columns}) : columns = columns ?? [];

  /// `CREATE VIEW 名前 AS` の後に出力するSELECT文(末尾の `;` は不要)。
  String sql;
  List<FunctionReturnColumn> columns;

  ViewSqlDef copy() => ViewSqlDef(sql: sql, columns: columns.map((c) => c.copy()).toList());
}

class ViewEntity extends Entity {
  ViewEntity({
    required super.id,
    super.logicalName,
    super.physicalName,
    super.comment,
    super.locked,
    super.preQuery,
    super.postQuery,
    this.viewType = ViewType.join,
    ViewJoinDef? join,
    ViewFunctionDef? function,
    ViewSqlDef? sql,
  })  : join = join ?? ViewJoinDef(),
        function = function ?? ViewFunctionDef(),
        sql = sql ?? ViewSqlDef();

  ViewType viewType;
  ViewJoinDef join;
  ViewFunctionDef function;
  ViewSqlDef sql;

  @override
  EntityKind get kind => EntityKind.view;

  @override
  ViewEntity copy() => ViewEntity(
        id: id,
        logicalName: logicalName,
        physicalName: physicalName,
        comment: comment,
        locked: locked,
        preQuery: preQuery,
        postQuery: postQuery,
        viewType: viewType,
        join: join.copy(),
        function: function.copy(),
        sql: sql.copy(),
      );
}

/// リレーションシップの列対応1組(7-4)。
class ColumnPair {
  ColumnPair({required this.parentColumnId, required this.childColumnId});
  int parentColumnId;
  int childColumnId;
  ColumnPair copy() => ColumnPair(parentColumnId: parentColumnId, childColumnId: childColumnId);
}

/// リレーションシップ(7)。ERオブジェクト。
class Relationship {
  Relationship({
    required this.id,
    this.locked = false,
    required this.parentId,
    required this.childId,
    List<ColumnPair>? columnPairs,
    this.dependency = true,
    this.childMultiplicity = Multiplicity.many,
    this.nameMode = NameMode.auto,
    this.name = '',
    this.onDelete = RefAction.noAction,
    this.onUpdate = RefAction.noAction,
    this.deferrable = Deferrable.none,
  }) : columnPairs = columnPairs ?? [];

  final int id;
  bool locked;
  int parentId;
  int childId;
  List<ColumnPair> columnPairs;
  bool dependency;
  Multiplicity childMultiplicity;
  NameMode nameMode;
  String name;
  RefAction onDelete;
  RefAction onUpdate;

  /// 遅延可否(DEFERRABLE。7-4)。
  Deferrable deferrable;

  /// 参照規則を適用しない(7-6-3)。
  bool get noReferentialRule => onDelete == RefAction.none && onUpdate == RefAction.none;

  Relationship copy() => Relationship(
        id: id,
        locked: locked,
        parentId: parentId,
        childId: childId,
        columnPairs: columnPairs.map((p) => p.copy()).toList(),
        dependency: dependency,
        childMultiplicity: childMultiplicity,
        nameMode: nameMode,
        name: name,
        onDelete: onDelete,
        onUpdate: onUpdate,
        deferrable: deferrable,
      );
}
