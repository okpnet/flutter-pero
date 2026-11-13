import 'entity.dart';
import 'enums.dart';

/// メソッド(8.1)。共有リソース。ロックは持たない。
class MethodDef {
  MethodDef({
    required this.id,
    this.kind = MethodKind.function,
    this.name = '',
    this.external = false,
    Map<DbKind, String>? call,
    Map<DbKind, String>? bodies,
    this.comment = '',
    this.args = '',
    this.schema = '',
    List<int>? dependsOnTableIds,
  })  : dependsOnTableIds = dependsOnTableIds ?? [],
        call = call ?? {for (final d in DbKind.values) d: ''},
        bodies = bodies ?? {for (final d in DbKind.values) d: ''};

  final int id;
  MethodKind kind;
  String name;
  bool external;
  Map<DbKind, String> call;
  Map<DbKind, String> bodies;

  /// コメント(COMMENT ON FUNCTION で出力する。8.1-3)。
  String comment;

  /// 引数の定義(`COMMENT ON FUNCTION 名前(引数)` の括弧の内側。ファンクションのみ。8.1-3)。
  String args;

  /// スキーマ。空のときはモデルのスキーマ。トリガー・関数ビューからの呼出しと `COMMENT ON FUNCTION` で使う。外部定義には付けない(8.1-3)。
  String schema;

  /// 依存するテーブルのID。これらの作成後に定義を出力する(8.1-3)。
  List<int> dependsOnTableIds;

  /// 対象DBの呼出し式。省略時は `{名前}()`(8.1-3)。
  String callExpr(DbKind db) {
    final c = call[db] ?? '';
    return c.isEmpty ? '$name()' : c;
  }

  MethodDef copy() => MethodDef(
      id: id,
      kind: kind,
      name: name,
      external: external,
      call: Map.of(call),
      bodies: Map.of(bodies),
      comment: comment,
      args: args,
      schema: schema,
      dependsOnTableIds: List.of(dependsOnTableIds));
}

/// 共通列パターン(8.2)。
class CommonColumnPattern {
  CommonColumnPattern({
    required this.id,
    this.name = '',
    this.enabled = true,
    this.include = '^.*\$',
    this.exclude = '',
    this.position = PatternPosition.end,
    List<ColumnDef>? columns,
  }) : columns = columns ?? [];

  final int id;
  String name;
  bool enabled;
  String include;
  String exclude;
  PatternPosition position;
  List<ColumnDef> columns;

  /// 全体一致の正規表現を作る。不正ならnull。
  static RegExp? _compile(String src) {
    try {
      return RegExp('^(?:$src)\$');
    } on FormatException {
      return null;
    }
  }

  bool get isRegexValid =>
      _compile(include) != null && (exclude.isEmpty || _compile(exclude) != null);

  /// このパターンがテーブル物理名に適用されるか(大文字小文字を区別する)。
  bool appliesTo(String tablePhysicalName) {
    if (!enabled) return false;
    final inc = _compile(include);
    if (inc == null || !inc.hasMatch(tablePhysicalName)) return false;
    if (exclude.isNotEmpty) {
      final exc = _compile(exclude);
      if (exc == null) return false;
      if (exc.hasMatch(tablePhysicalName)) return false;
    }
    return true;
  }

  CommonColumnPattern copy() => CommonColumnPattern(
        id: id,
        name: name,
        enabled: enabled,
        include: include,
        exclude: exclude,
        position: position,
        columns: columns.map((c) => c.copy()).toList(),
      );
}

/// 展開された列(実列または共通列)。
class ExpandedColumn {
  ExpandedColumn(this.column, {this.patternName});
  final ColumnDef column;

  /// 共通列のとき所属するパターン名。実列はnull。
  final String? patternName;
  bool get isCommon => patternName != null;
}

/// 共通列の展開結果。
class ExpansionResult {
  ExpansionResult(this.columns, this.skipped);
  final List<ExpandedColumn> columns;

  /// 物理名の衝突で展開されなかった列(パターン名, 列)。
  final List<(String, ColumnDef)> skipped;
}
