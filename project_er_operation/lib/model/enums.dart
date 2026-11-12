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
  method('method');

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
  function('function');

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
