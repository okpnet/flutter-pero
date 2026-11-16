/// 列挙型。保存用JSON(付録A)の文字列表現(wire)を持つ。
library;

enum DbKind {
  postgresql('postgresql'),
  mysql('mysql'),
  sqlserver('sqlserver'),
  sqlite('sqlite');

  const DbKind(this.wire);
  final String wire;
}

enum ParamKind {
  none('none'),
  length('length'),
  precisionScale('precisionScale');

  const ParamKind(this.wire);
  final String wire;
}

enum TypeCategory {
  number('number'),
  string('string'),
  boolean('boolean'),
  datetime('datetime'),
  binary('binary'),
  json('json'),
  auto('auto');

  const TypeCategory(this.wire);
  final String wire;
}

enum DefaultKind {
  none('none'),
  value('value'),
  method('method'),
  expression('expression');

  const DefaultKind(this.wire);
  final String wire;
}

enum EntityKind {
  table('table'),
  view('view');

  const EntityKind(this.wire);
  final String wire;
}

enum MethodKind {
  function('function'),
  trigger('trigger');

  const MethodKind(this.wire);
  final String wire;
}

enum ViewType {
  join('join'),
  function('function'),
  sql('sql');

  const ViewType(this.wire);
  final String wire;
}

enum PatternPosition {
  start('start'),
  end('end');

  const PatternPosition(this.wire);
  final String wire;
}

enum TriggerSource {
  public('public'),
  inline('inline');

  const TriggerSource(this.wire);
  final String wire;
}

enum NameMode {
  auto('auto'),
  manual('manual');

  const NameMode(this.wire);
  final String wire;
}

/// CHECK制約の記述方法(6.4-6)。式は直接入力、条件は列・演算子・値で組み立てる。
enum CheckMode {
  expression('expression'),
  conditions('conditions');

  const CheckMode(this.wire);
  final String wire;
}

/// CHECK制約の条件の演算子(6.4-6)。WHEREで使える比較を選ぶ。SQLへの変換はポストファイルが行う。
enum CheckOperator {
  eq('eq', '='),
  ne('ne', '<>'),
  lt('lt', '<'),
  le('le', '<='),
  gt('gt', '>'),
  ge('ge', '>='),
  inList('in', 'IN'),
  notInList('not_in', 'NOT IN'),
  between('between', 'BETWEEN'),
  like('like', 'LIKE'),
  notLike('not_like', 'NOT LIKE'),
  isNull('is_null', 'IS NULL'),
  isNotNull('is_not_null', 'IS NOT NULL');

  const CheckOperator(this.wire, this.label);
  final String wire;

  /// 画面に表示する記号。
  final String label;

  /// 列の型のカテゴリで選べる演算子(WHEREで意味を持つ組合せだけ)。
  /// 真偽値・バイナリ・JSONは、等しいか、NULLかどうかだけ。LIKEは文字列だけ。
  static List<CheckOperator> allowedFor(TypeCategory c) => switch (c) {
        TypeCategory.boolean || TypeCategory.binary || TypeCategory.json => const [eq, ne, isNull, isNotNull],
        TypeCategory.string => values,
        _ => [for (final o in values) if (o != like && o != notLike) o],
      };

  /// 値の個数の下限と上限(上限nullは制限なし)。
  (int, int?) get valueCount => switch (this) {
        isNull || isNotNull => (0, 0),
        between => (2, 2),
        inList || notInList => (1, null),
        _ => (1, 1),
      };
}

/// 条件の結合(複数の条件)。
enum CheckJoin {
  and('AND'),
  or('OR');

  const CheckJoin(this.wire);
  final String wire;
}

enum TriggerTiming {
  before('BEFORE'),
  after('AFTER');

  const TriggerTiming(this.wire);
  final String wire;
}

enum TriggerEvent {
  insert('INSERT'),
  update('UPDATE'),
  delete('DELETE');

  const TriggerEvent(this.wire);
  final String wire;
}

enum TriggerForEach {
  row('ROW'),
  statement('STATEMENT');

  const TriggerForEach(this.wire);
  final String wire;
}

enum JoinType {
  inner('INNER'),
  left('LEFT'),
  right('RIGHT'),
  full('FULL');

  const JoinType(this.wire);
  final String wire;
}

enum Multiplicity {
  one('one'),
  many('many');

  const Multiplicity(this.wire);
  final String wire;
}

enum RefAction {
  none('none', null),
  noAction('no_action', 'NO ACTION'),
  restrict('restrict', 'RESTRICT'),
  cascade('cascade', 'CASCADE'),
  setNull('set_null', 'SET NULL'),
  setDefault('set_default', 'SET DEFAULT');

  const RefAction(this.wire, this.sql);
  final String wire;

  /// 生成用JSON(付録B)での表現。適用しないときはnull。
  final String? sql;
}

enum PageSize {
  a0('A0'),
  a1('A1'),
  a2('A2'),
  a3('A3'),
  a4('A4');

  const PageSize(this.wire);
  final String wire;
}

enum Orientation {
  landscape('landscape'),
  portrait('portrait');

  const Orientation(this.wire);
  final String wire;
}

/// wire文字列から列挙値を引く。見つからなければnull。
T? enumFromWire<T extends Enum>(List<T> values, Object? wire) {
  if (wire is! String) return null;
  for (final v in values) {
    if ((v as dynamic).wire == wire) return v;
  }
  return null;
}

/// 型の種別(6.3)。標準型とカスタム型は scalar、ユーザー定義型は composite / enumeration。
enum TypeKind {
  scalar('scalar'),
  composite('composite'),
  enumeration('enumeration');

  const TypeKind(this.wire);
  final String wire;
}

/// 外部キー制約の遅延可否(7-4)。
enum Deferrable {
  none('none', null),
  immediate('immediate', 'DEFERRABLE INITIALLY IMMEDIATE'),
  deferred('deferred', 'DEFERRABLE INITIALLY DEFERRED');

  const Deferrable(this.wire, this.sql);
  final String wire;
  final String? sql;
}
