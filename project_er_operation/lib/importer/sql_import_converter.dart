import '../model/model.dart';

/// 取り込めなかった文や要素(ポストファイルが返したもの、変換で取り込めなかったもの)。
class UnparsedItem {
  const UnparsedItem({required this.kind, required this.reason, this.text = '', this.file = '', this.line = 0});

  factory UnparsedItem.fromJson(Map<String, Object?> j) => UnparsedItem(
        kind: '${j['kind'] ?? ''}',
        reason: '${j['reason'] ?? ''}',
        text: '${j['text'] ?? ''}',
        file: '${j['file'] ?? ''}',
        line: (j['line'] as num?)?.toInt() ?? 0,
      );

  /// 文や要素の種類(例 `INSERT`、`CREATE INDEX`)。
  final String kind;

  /// 取り込めない理由。
  final String reason;

  /// 元の文(コメントを含む)。
  final String text;
  final String file;
  final int line;

  /// 場所の表記(`file:line`)。
  String get where => file.isEmpty ? (line > 0 ? '$line' : '') : (line > 0 ? '$file:$line' : file);

  /// ログの1行。
  String get summary => '[$kind] $reason${where.isEmpty ? '' : ' ($where)'}';
}

/// 取り込みの結果(件数と、取り込めなかったもの)。
class ImportReport {
  int tables = 0;
  int columns = 0;
  int relationships = 0;
  int methods = 0;
  int views = 0;
  int triggers = 0;
  int types = 0;

  /// 作成したエンティティのID(テーブル、ビューの順)。
  final List<int> entityIds = [];

  /// 取り込めなかったもの。
  final List<UnparsedItem> unparsed = [];

  /// 取り込んだが、補足がある事項(型の自動追加など)。
  final List<String> notes = [];

  bool get isEmpty => tables + methods + views + types == 0;

  /// 件数の要約。
  String get summary =>
      'テーブル$tables(列$columns)、リレーションシップ$relationships、ビュー$views、関数・トリガー関数$methods、'
      'トリガー$triggers、型$types';
}

class _TypeSpec {
  _TypeSpec(this.id, {this.length, this.precision, this.scale});
  final String id;
  final int? length;
  final int? precision;
  final int? scale;
}

/// ポストファイルが返したインポート結果(付録E)を、モデルへ追加する(Builder パターン)。
/// [model] を直接変更する。既にある同名のテーブル・ビュー・関数は取り込まず、結果へ記録する。
class SqlImportConverter {
  SqlImportConverter(this.model);

  final ErModel model;
  final ImportReport report = ImportReport();

  final Map<String, TableEntity> _tables = {};
  final Map<String, ViewEntity> _views = {};
  final Map<String, MethodDef> _methods = {};
  final Map<String, DataType> _userTypes = {};
  final Map<String, DataType> _customTypes = {};
  final Map<String, MethodDef> _defaultMethods = {};
  late DbKind _dialect;

  List<Map<String, Object?>> _list(Object? v) =>
      [for (final e in (v as List? ?? const [])) Map<String, Object?>.from(e as Map)];

  void _skip(String kind, String reason, {String text = '', String file = '', int line = 0}) =>
      report.unparsed.add(UnparsedItem(kind: kind, reason: reason, text: text, file: file, line: line));

  String _where(Map<String, Object?> o) => '${o['file'] ?? ''}:${o['line'] ?? ''}';

  /// 取り込みを実行する。
  ImportReport convert(Map<String, Object?> data) {
    _dialect = enumFromWire(DbKind.values, '${data['dialect'] ?? ''}') ?? DbKind.postgresql;
    for (final u in _list(data['unparsed'])) {
      report.unparsed.add(UnparsedItem.fromJson(u));
    }
    for (final t in model.types.where((t) => t.isUserDefined)) {
      _userTypes[(t.physical[DbKind.postgresql] ?? t.displayName).toLowerCase()] = t;
    }
    final newModel = model.entities.isEmpty;
    final schemas = <String>{};

    for (final t in _list(data['types'])) {
      _createType(t);
    }
    for (final f in _list(data['functions'])) {
      _function(f);
      if ('${f['schema'] ?? ''}'.isNotEmpty) schemas.add('${f['schema']}');
    }
    final tables = _list(data['tables']);
    for (final t in tables) {
      _table(t);
      if ('${t['schema'] ?? ''}'.isNotEmpty) schemas.add('${t['schema']}');
    }
    final cons = _list(data['constraints']);
    for (final c in cons.where((c) => c['kind'] == 'primaryKey')) {
      _primaryKey(c);
    }
    for (final c in cons.where((c) => c['kind'] != 'primaryKey' && c['kind'] != 'index')) {
      _constraint(c);
    }
    for (final c in cons.where((c) => c['kind'] == 'index')) {
      _index(c);
    }
    for (final v in _list(data['views'])) {
      _view(v);
      if ('${v['schema'] ?? ''}'.isNotEmpty) schemas.add('${v['schema']}');
    }
    for (final t in _list(data['triggers'])) {
      _trigger(t);
    }
    for (final c in _list(data['comments'])) {
      _comment(c);
    }
    _finish();
    // 新しいモデルで、スキーマが1つだけなら、モデルのスキーマにする(出力にスキーマを含める)。
    if (newModel && schemas.length == 1 && model.properties.schema.isEmpty) {
      model.properties.schema = schemas.first;
      model.properties.includeSchema = true;
    }
    return report;
  }

  // ---------- 名前

  String _lower(String s) => s.toLowerCase();

  bool _entityNameTaken(String name) => model.entities.any((e) => _lower(e.physicalName) == _lower(name));

  // ---------- 型

  String _nextCustomId() {
    var n = model.types.length + 1;
    while (model.types.any((t) => t.id == 'custom_$n')) {
      n++;
    }
    return 'custom_$n';
  }

  DataType _custom(String raw) {
    return _customTypes.putIfAbsent(raw.toLowerCase(), () {
      final t = DataType(
        id: _nextCustomId(),
        displayName: raw,
        category: TypeCategory.string,
        physical: {
          DbKind.postgresql: raw,
          DbKind.mysql: 'TEXT',
          DbKind.sqlserver: 'varchar(max)',
          DbKind.sqlite: 'TEXT',
        },
      );
      if (_dialect != DbKind.postgresql) t.physical[_dialect] = raw;
      model.types.add(t);
      report.notes.add('カスタム型を追加: $raw(${t.id})');
      return t;
    });
  }

  String _unquote(String s) {
    final t = s.trim();
    return t.startsWith('"') && t.endsWith('"') && t.length >= 2 ? t.substring(1, t.length - 1) : t.toLowerCase();
  }

  _TypeSpec _type(Map<String, Object?> col) {
    final direct = col['typeId'];
    if (direct is String && model.typeById(direct) != null) {
      return _TypeSpec(direct,
          length: (col['length'] as num?)?.toInt(),
          precision: (col['precision'] as num?)?.toInt(),
          scale: (col['scale'] as num?)?.toInt());
    }
    return _typeFromText('${col['type'] ?? ''}');
  }

  _TypeSpec _typeFromText(String raw) {
    final t = raw.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
    final user = _userTypes[_unquote(t.split('.').last)];
    if (user != null) return _TypeSpec(user.id);
    final m = RegExp(r'^([a-z ]+?)\s*(?:\((\d+)(?:\s*,\s*(\d+))?\))?$').firstMatch(t);
    if (m == null) return _TypeSpec(_custom(raw).id);
    final base = m.group(1)!;
    final a = m.group(2) == null ? null : int.parse(m.group(2)!);
    final b = m.group(3) == null ? null : int.parse(m.group(3)!);
    switch (base) {
      case 'uuid':
        return _TypeSpec('uuid');
      case 'timestamp':
      case 'timestamp without time zone':
        return _TypeSpec('timestamp');
      case 'timestamptz':
      case 'timestamp with time zone':
        return _TypeSpec('timestamptz');
      case 'boolean':
      case 'bool':
        return _TypeSpec('boolean');
      case 'varchar':
      case 'character varying':
        return a == null ? _TypeSpec('varchar_nolen') : _TypeSpec('varchar', length: a);
      case 'char':
      case 'character':
        return _TypeSpec('char', length: a ?? 1);
      case 'integer':
      case 'int':
      case 'int4':
        return _TypeSpec('integer');
      case 'smallint':
      case 'int2':
        return _TypeSpec('smallint');
      case 'bigint':
      case 'int8':
        return _TypeSpec('bigint');
      case 'decimal':
      case 'numeric':
        if (a == null) {
          report.notes.add('精度なしの numeric は numeric(18,2) にした');
          return _TypeSpec('numeric', precision: 18, scale: 2);
        }
        return _TypeSpec('numeric', precision: a, scale: b ?? 0);
      case 'real':
      case 'float4':
        return _TypeSpec('real');
      case 'double precision':
      case 'float8':
        return _TypeSpec('double');
      case 'date':
        return _TypeSpec('date');
      case 'time':
      case 'time without time zone':
        return _TypeSpec('time');
      case 'interval':
        return _TypeSpec('interval');
      case 'text':
        return _TypeSpec('text');
      case 'json':
        return _TypeSpec('json');
      case 'jsonb':
        return _TypeSpec('jsonb');
      case 'bytea':
        return _TypeSpec('bytea');
      case 'serial':
      case 'bigserial':
      case 'smallserial':
        return _TypeSpec('auto');
    }
    return _TypeSpec(_custom(raw).id);
  }

  void _createType(Map<String, Object?> t) {
    final name = '${t['name']}';
    if (_userTypes.containsKey(name.toLowerCase())) {
      _skip('CREATE TYPE', '同名の型が既にあるため取り込まない: $name', file: '${t['file'] ?? ''}', line: (t['line'] as num?)?.toInt() ?? 0);
      return;
    }
    final isEnum = t['kind'] == 'enum';
    final dt = DataType(
      id: _nextCustomId(),
      displayName: name,
      physical: {DbKind.postgresql: name, DbKind.mysql: '', DbKind.sqlserver: '', DbKind.sqlite: ''},
      kind: isEnum ? TypeKind.enumeration : TypeKind.composite,
      schema: '${t['schema'] ?? ''}',
    );
    model.types.add(dt);
    _userTypes[name.toLowerCase()] = dt;
    for (final v in (t['values'] as List? ?? const [])) {
      dt.enumValues.add('$v');
    }
    for (final f in _list(t['fields'])) {
      final spec = _typeFromText('${f['type']}');
      dt.fields.add(TypeField(
          name: '${f['name']}', typeId: spec.id, length: spec.length, precision: spec.precision, scale: spec.scale));
    }
    report.types++;
  }

  // ---------- デフォルト

  String _uniqueMethodName(String name) {
    var unique = name;
    var n = 2;
    while (model.methods.any((m) => _lower(m.name) == _lower(unique))) {
      unique = '${name}_$n';
      n++;
    }
    return unique;
  }

  MethodDef _defaultMethod(String name, String call) {
    return _defaultMethods.putIfAbsent(call, () {
      final existing = model.methods
          .where((m) => m.external && m.kind == MethodKind.function && (m.call[_dialect] ?? '') == call)
          .firstOrNull;
      if (existing != null) return existing;
      final m = MethodDef(
        id: model.allocateId(),
        kind: MethodKind.function,
        name: _uniqueMethodName(name),
        external: true,
        call: {for (final d in DbKind.values) d: d == _dialect ? call : ''},
      );
      model.methods.add(m);
      return m;
    });
  }

  void _setDefault(ColumnDef c, String expr) {
    final e = expr.trim();
    if (e.isEmpty || e.toLowerCase() == 'null') return;
    final cat = model.typeById(c.typeId)?.category;
    final str = RegExp(r"^('(?:[^']|'')*')(?:::[\w ]+)?$").firstMatch(e);
    if (str != null) {
      final v = str.group(1)!.substring(1, str.group(1)!.length - 1).replaceAll("''", "'");
      if (v.isEmpty) {
        // 空文字は標準メソッド empty_string で表す(6.2-4)。無ければ式のまま。
        final m = model.methods.where((m) => m.name == emptyStringMethodName).firstOrNull;
        if (m != null) {
          c.defaultKind = DefaultKind.method;
          c.defaultMethodId = m.id;
        } else {
          c.defaultKind = DefaultKind.expression;
          c.defaultExpression = e;
        }
        return;
      }
      c.defaultKind = DefaultKind.value;
      if (cat == TypeCategory.boolean) {
        final lv = v.toLowerCase();
        c.defaultValue = (lv == 't' || lv == 'true' || lv == '1') ? 'true' : 'false';
      } else {
        c.defaultValue = v;
      }
      return;
    }
    if (RegExp(r'^-?\d+(\.\d+)?$').hasMatch(e) || RegExp(r'^(true|false)$', caseSensitive: false).hasMatch(e)) {
      c.defaultKind = DefaultKind.value;
      c.defaultValue = e.toLowerCase();
      return;
    }
    final fn = RegExp(r'^(\w+)\(\)$').firstMatch(e);
    if (fn != null) {
      c.defaultKind = DefaultKind.method;
      c.defaultMethodId = _defaultMethod(fn.group(1)!.toLowerCase(), e).id;
      return;
    }
    c.defaultKind = DefaultKind.expression;
    c.defaultExpression = e;
  }

  // ---------- テーブル

  void _table(Map<String, Object?> t) {
    final name = '${t['name']}';
    if (_tables.containsKey(_lower(name)) || _entityNameTaken(name)) {
      _skip('CREATE TABLE', '同名のテーブルまたはビューが既にあるため取り込まない: $name', file: '${t['file'] ?? ''}', line: (t['line'] as num?)?.toInt() ?? 0);
      return;
    }
    final table = TableEntity(id: model.allocateId(), physicalName: name);
    for (final col in _list(t['columns'])) {
      final spec = _type(col);
      final c = ColumnDef(
        id: model.allocateId(),
        physicalName: '${col['name']}',
        typeId: spec.id,
        length: spec.length,
        precision: spec.precision,
        scale: spec.scale,
        notNull: col['notNull'] == true,
      );
      final d = col['default'];
      if (spec.id != 'auto' && d is String) _setDefault(c, d);
      if (col['primaryKey'] == true) {
        c.pk = true;
        c.notNull = true;
      }
      table.columns.add(c);
      report.columns++;
    }
    _tables[_lower(name)] = table;
    model.entities.add(table);
    report.tables++;
    report.entityIds.add(table.id);
    // 列に付いた制約(UNIQUE、CHECK、REFERENCES)は、テーブル内の制約と同じに扱う。
    for (final col in _list(t['columns'])) {
      final n = '${col['name']}';
      if (col['unique'] == true) {
        _constraint({'kind': 'unique', 'table': name, 'name': '', 'columns': [n], 'file': t['file'], 'line': t['line']});
      }
      if (col['check'] is String) {
        _constraint({'kind': 'check', 'table': name, 'name': '', 'expression': col['check'], 'file': t['file'], 'line': t['line']});
      }
      final ref = col['references'];
      if (ref is Map) {
        final refCols = '${ref['columns'] ?? ''}'.trim();
        _constraint({
          'kind': 'foreignKey',
          'table': name,
          'name': '',
          'columns': [n],
          'refTable': ref['table'],
          'refColumns': refCols.isEmpty ? null : [for (final p in refCols.split(',')) p.trim()],
          'file': t['file'],
          'line': t['line'],
        });
      }
    }
  }

  TableEntity? _tableOf(Map<String, Object?> c, String kind) {
    final name = '${c['table']}'.split('.').last.replaceAll('"', '').toLowerCase();
    final t = _tables[name];
    if (t == null) {
      _skip(kind, '対象テーブルが無い: ${c['table']}', file: '${c['file'] ?? ''}', line: (c['line'] as num?)?.toInt() ?? 0);
    }
    return t;
  }

  List<ColumnDef>? _cols(TableEntity t, Object? names, Map<String, Object?> c, String kind) {
    final out = <ColumnDef>[];
    for (final n in (names as List? ?? const [])) {
      final col = t.columns.where((x) => _lower(x.physicalName) == _lower('$n')).firstOrNull;
      if (col == null) {
        _skip(kind, '列が見つからない: ${t.physicalName}.$n', file: '${c['file'] ?? ''}', line: (c['line'] as num?)?.toInt() ?? 0);
        return null;
      }
      out.add(col);
    }
    return out;
  }

  void _primaryKey(Map<String, Object?> c) {
    final t = _tableOf(c, 'PRIMARY KEY');
    if (t == null) return;
    final cols = _cols(t, c['columns'], c, 'PRIMARY KEY');
    if (cols == null) return;
    for (final col in cols) {
      col.pk = true;
      col.notNull = true;
    }
  }

  void _constraint(Map<String, Object?> c) {
    final kind = '${c['kind']}';
    final t = _tableOf(c, kind);
    if (t == null) return;
    final name = '${c['name'] ?? ''}';
    final mode = name.isEmpty ? NameMode.auto : NameMode.manual;
    switch (kind) {
      case 'unique':
        final cols = _cols(t, c['columns'], c, 'UNIQUE');
        if (cols == null) return;
        t.uniques.add(ConstraintDef(
            id: model.allocateId(),
            nameMode: mode,
            name: name,
            columnIds: cols.map((x) => x.id).toList(),
            nullsNotDistinct: c['nullsNotDistinct'] == true));
      case 'check':
        t.checks.add(CheckDef(
            id: model.allocateId(), nameMode: mode, name: name, expression: '${c['expression'] ?? ''}'.trim()));
      case 'foreignKey':
        _foreignKey(t, c, name, mode);
      default:
        _skip('制約', '未対応の制約: $kind', file: '${c['file'] ?? ''}', line: (c['line'] as num?)?.toInt() ?? 0);
    }
  }

  void _foreignKey(TableEntity child, Map<String, Object?> c, String name, NameMode mode) {
    final parent = _tables['${c['refTable']}'.split('.').last.replaceAll('"', '').toLowerCase()];
    if (parent == null) {
      _skip('FOREIGN KEY', '親テーブルが無い: $name → ${c['refTable']}', file: '${c['file'] ?? ''}', line: (c['line'] as num?)?.toInt() ?? 0);
      return;
    }
    final cc = _cols(child, c['columns'], c, 'FOREIGN KEY');
    // 親の列の指定が無いときは、親の主キー。
    final refNames = c['refColumns'] ?? [for (final x in parent.columns.where((x) => x.pk)) x.physicalName];
    final pc = _cols(parent, refNames, c, 'FOREIGN KEY');
    if (cc == null || pc == null) return;
    if (cc.isEmpty || cc.length != pc.length) {
      _skip('FOREIGN KEY', '列の数が合わない: $name', file: '${c['file'] ?? ''}', line: (c['line'] as num?)?.toInt() ?? 0);
      return;
    }
    RefAction action(Object? v) => switch ('$v') {
          'no action' => RefAction.noAction,
          'restrict' => RefAction.restrict,
          'cascade' => RefAction.cascade,
          'set null' => RefAction.setNull,
          'set default' => RefAction.setDefault,
          _ => RefAction.none,
        };
    final childPk = child.columns.where((x) => x.pk).map((x) => x.id).toSet();
    final dependency = parent != child && childPk.isNotEmpty && cc.every((x) => childPk.contains(x.id));
    final deferrable = switch ('${c['deferrable'] ?? ''}') {
      'immediate' => Deferrable.immediate,
      'deferred' => Deferrable.deferred,
      _ => Deferrable.none,
    };
    model.relationships.add(Relationship(
      id: model.allocateId(),
      parentId: parent.id,
      childId: child.id,
      columnPairs: [
        for (var i = 0; i < cc.length; i++) ColumnPair(parentColumnId: pc[i].id, childColumnId: cc[i].id)
      ],
      dependency: dependency,
      nameMode: mode,
      name: name,
      onDelete: action(c['onDelete']),
      onUpdate: action(c['onUpdate']),
      deferrable: deferrable,
    ));
    report.relationships++;
  }

  void _index(Map<String, Object?> c) {
    final t = _tableOf(c, 'CREATE INDEX');
    if (t == null) return;
    final cols = _cols(t, c['columns'], c, 'CREATE INDEX');
    if (cols == null) return;
    final ids = cols.map((x) => x.id).toList();
    final unique = c['unique'] == true;
    final pkIds = t.columns.where((x) => x.pk).map((x) => x.id).toList();
    if (unique && pkIds.length == ids.length && pkIds.toSet().containsAll(ids)) {
      report.notes.add('主キーと重複するユニークインデックスは取り込まない: ${c['name']}');
      return;
    }
    (unique ? t.uniques : t.indexes)
        .add(ConstraintDef(id: model.allocateId(), nameMode: NameMode.manual, name: '${c['name']}', columnIds: ids));
  }

  // ---------- ビュー

  String _nextImportViewName() {
    var n = 1;
    while (true) {
      final name = 'import_${n < 10 ? '0' : ''}$n';
      if (!_entityNameTaken(name)) return name;
      n++;
    }
  }

  void _view(Map<String, Object?> v) {
    final fromSelect = v['fromSelect'] == true;
    var name = '${v['name']}';
    final file = '${v['file'] ?? ''}';
    final line = (v['line'] as num?)?.toInt() ?? 0;
    final sql = '${v['sql'] ?? ''}';
    if (fromSelect) {
      // 名前は import_XX(XXは連番)。既にある名前は避けて、次の空き番号にする。
      if (_entityNameTaken(name)) name = _nextImportViewName();
    } else {
      final old = _views[_lower(name)];
      if (old != null) {
        old.sql.sql = sql; // CREATE OR REPLACE VIEW
        return;
      }
      if (_entityNameTaken(name)) {
        _skip('CREATE VIEW', '同名のテーブルまたはビューが既にあるため取り込まない: $name', file: file, line: line);
        return;
      }
    }
    final view = ViewEntity(
      id: model.allocateId(),
      physicalName: name,
      viewType: ViewType.sql,
      sql: ViewSqlDef(sql: sql),
    );
    _views[_lower(name)] = view;
    model.entities.add(view);
    report.views++;
    report.entityIds.add(view.id);
    if (fromSelect) report.notes.add('SELECT 文をビュー $name にした($file:$line)');
  }

  // ---------- 関数

  void _function(Map<String, Object?> f) {
    final name = '${f['name']}';
    final isTrigger = '${f['returns'] ?? ''}'.toLowerCase() == 'trigger';
    final existing = model.methods.where((m) => _lower(m.name) == _lower(name)).firstOrNull;
    if (existing != null) {
      _skip('CREATE FUNCTION', '同名のメソッドが既にあるため取り込まない: $name',
          file: '${f['file'] ?? ''}', line: (f['line'] as num?)?.toInt() ?? 0);
      return;
    }
    final m = MethodDef(
      id: model.allocateId(),
      kind: isTrigger ? MethodKind.trigger : MethodKind.function,
      name: name,
      schema: '${f['schema'] ?? ''}',
      bodies: {for (final d in DbKind.values) d: d == _dialect ? '${f['body'] ?? ''}' : ''},
    );
    _methods[_lower(name)] = m;
    model.methods.add(m);
    report.methods++;
  }

  // ---------- トリガー

  void _trigger(Map<String, Object?> t) {
    final name = '${t['name']}';
    final where = _where(t);
    final tbl = _tableOf(t, 'CREATE TRIGGER');
    if (tbl == null) return;
    final fn = _methods[_lower('${t['function']}')];
    if (fn == null) {
      _skip('CREATE TRIGGER', '関数が取り込まれていない: ${t['function']}($name $where)',
          file: '${t['file'] ?? ''}', line: (t['line'] as num?)?.toInt() ?? 0);
      return;
    }
    final events = <TriggerEvent>[];
    var updateCols = <int>[];
    for (final e in _list(t['events'])) {
      final ev = switch ('${e['event']}') {
        'insert' => TriggerEvent.insert,
        'update' => TriggerEvent.update,
        'delete' => TriggerEvent.delete,
        _ => null,
      };
      if (ev == null) continue;
      if (ev == TriggerEvent.update && (e['columns'] as List? ?? const []).isNotEmpty) {
        final cols = _cols(tbl, e['columns'], t, 'CREATE TRIGGER');
        if (cols == null) return;
        updateCols = cols.map((x) => x.id).toList();
      }
      if (!events.contains(ev)) events.add(ev);
    }
    if (events.isEmpty) {
      _skip('CREATE TRIGGER', 'イベントが無い: $name $where', file: '${t['file'] ?? ''}', line: (t['line'] as num?)?.toInt() ?? 0);
      return;
    }
    final def = TriggerDef(
      id: model.allocateId(),
      source: TriggerSource.public,
      methodId: fn.id,
      nameMode: NameMode.manual,
      name: name,
      timing: '${t['timing']}' == 'after' ? TriggerTiming.after : TriggerTiming.before,
      events: events,
      forEach: '${t['forEach']}' == 'statement' ? TriggerForEach.statement : TriggerForEach.row,
      when: '${t['when'] ?? ''}',
      args: '${t['args'] ?? ''}',
      updateColumnIds: updateCols,
    );
    final at = tbl.triggers.indexWhere((x) => x.name == name);
    if (at >= 0) {
      tbl.triggers[at] = def;
    } else {
      tbl.triggers.add(def);
    }
    report.triggers++;
  }

  // ---------- コメント

  List<String> _parts(String raw) {
    final parts = <String>[];
    final buf = StringBuffer();
    var quoted = false;
    for (var i = 0; i < raw.length; i++) {
      final ch = raw[i];
      if (ch == '"') {
        quoted = !quoted;
        buf.write(ch);
      } else if (ch == '.' && !quoted) {
        parts.add(buf.toString());
        buf.clear();
      } else {
        buf.write(ch);
      }
    }
    parts.add(buf.toString());
    return parts.map((p) => _unquote(p)).toList();
  }

  void _comment(Map<String, Object?> c) {
    final kind = '${c['kind']}';
    final text = '${c['text'] ?? ''}';
    final target = '${c['target']}';
    switch (kind) {
      case 'table':
        final t = _tables[_parts(target).last];
        if (t == null) return;
        t.comment = text;
        t.logicalName = text;
      case 'column':
        final parts = _parts(target);
        if (parts.length < 2) return;
        final t = _tables[parts[parts.length - 2]];
        final col = t?.columns.where((x) => _lower(x.physicalName) == parts.last).firstOrNull;
        if (col == null) return;
        col.comment = text;
        col.logicalName = text;
      case 'view':
        final v = _views[_parts(target).last];
        if (v != null) v.comment = text;
      case 'function':
        final open = target.indexOf('(');
        final name = _parts(open < 0 ? target : target.substring(0, open)).last;
        final fn = _methods[name];
        if (fn == null) return;
        fn.comment = text;
        fn.args = open < 0 ? '' : target.substring(open + 1, target.lastIndexOf(')'));
      case 'type':
        final t = _userTypes[_parts(target).last];
        if (t != null) t.comment = text;
      default:
        _skip('COMMENT ON ${kind.toUpperCase()}', '置き場がないため取り込まない: $target');
    }
  }

  // ---------- 仕上げ

  void _finish() {
    // ファンクションの依存テーブル・ビュー(本体に現れる名前)。
    for (final fn in _methods.values.where((m) => m.kind == MethodKind.function)) {
      final words = RegExp(r'[a-z_][a-z0-9_]*')
          .allMatches((fn.bodies[_dialect] ?? '').toLowerCase())
          .map((x) => x.group(0)!)
          .toSet();
      fn.dependsOnTableIds = [
        for (final t in _tables.values) if (words.contains(_lower(t.physicalName))) t.id,
        for (final v in _views.values) if (words.contains(_lower(v.physicalName))) v.id,
      ];
    }
  }
}
