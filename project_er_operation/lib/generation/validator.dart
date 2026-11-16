import '../model/model.dart';

class ValidationIssue {
  const ValidationIssue(this.message, {this.entityId});
  final String message;
  final int? entityId;
  @override
  String toString() => message;
}

class ValidationResult {
  final List<ValidationIssue> errors = [];
  final List<ValidationIssue> warnings = [];
  bool get hasErrors => errors.isNotEmpty;
}

/// PostgreSQLの予約語(アプリ内蔵のリスト。9.5-2-5)。
const Set<String> postgresqlReservedWords = {
  'all', 'analyse', 'analyze', 'and', 'any', 'array', 'as', 'asc', 'asymmetric', 'both',
  'case', 'cast', 'check', 'collate', 'column', 'constraint', 'create', 'current_catalog',
  'current_date', 'current_role', 'current_time', 'current_timestamp', 'current_user',
  'default', 'deferrable', 'desc', 'distinct', 'do', 'else', 'end', 'except', 'false', 'fetch',
  'for', 'foreign', 'from', 'grant', 'group', 'having', 'in', 'initially', 'intersect', 'into',
  'lateral', 'leading', 'limit', 'localtime', 'localtimestamp', 'not', 'null', 'offset', 'on',
  'only', 'or', 'order', 'placing', 'primary', 'references', 'returning', 'select',
  'session_user', 'some', 'symmetric', 'system_user', 'table', 'then', 'to', 'trailing', 'true',
  'union', 'unique', 'user', 'using', 'variadic', 'when', 'where', 'window', 'with',
};

int identifierMaxLength(DbKind db) => switch (db) {
      DbKind.postgresql => 63,
      DbKind.mysql => 64,
      DbKind.sqlserver => 128,
      DbKind.sqlite => 1 << 30,
    };

/// 生成前検証(9.5)。
class ModelValidator {
  ModelValidator(this.model,
      {String nameFormat = r'^[A-Za-z_][A-Za-z0-9_]*$', this.pkNaming = const PkNaming()})
      : _nameRegex = _compile(nameFormat);
  final ErModel model;

  /// 主キー制約名の規則(設定。6.4-1)。
  final PkNaming pkNaming;
  final RegExp? _nameRegex;

  static RegExp? _compile(String s) {
    try {
      return RegExp(s);
    } on FormatException {
      return null;
    }
  }

  late final DbKind _db = model.properties.targetDb;
  final ValidationResult _r = ValidationResult();

  void _err(String m, [int? eid]) => _r.errors.add(ValidationIssue(m, entityId: eid));
  void _warn(String m, [int? eid]) => _r.warnings.add(ValidationIssue(m, entityId: eid));

  ValidationResult validate() {
    _checkPatterns();
    _checkUserTypes();
    _checkSchemas();
    _checkMethods();
    _checkEntityNames();
    for (final t in model.tables) {
      _checkTable(t);
    }
    for (final v in model.views) {
      _checkView(v);
    }
    _checkConstraintNames();
    for (final r in model.relationships) {
      _checkRelationship(r);
    }
    return _r;
  }

  bool _nameOk(String n) => n.isNotEmpty && (_nameRegex?.hasMatch(n) ?? true);

  void _checkName(String kind, String name, {int? eid}) {
    if (name.isEmpty) {
      _err('$kindの物理名が空です', eid);
    } else if (!_nameOk(name)) {
      _err('$kindの物理名「$name」が形式に一致しません', eid);
    } else {
      if (name.length > identifierMaxLength(_db)) {
        _warn('$kind「$name」は識別子の長さ上限(${identifierMaxLength(_db)})を超えています', eid);
      }
      if (_db == DbKind.postgresql && postgresqlReservedWords.contains(name.toLowerCase())) {
        _warn('$kind「$name」はPostgreSQLの予約語です', eid);
      }
    }
  }

  void _checkPatterns() {
    for (final p in model.patterns) {
      if (p.enabled && !p.isRegexValid) {
        _err('共通列パターン「${p.name}」の正規表現が不正です');
      }
    }
  }

  void _checkUserTypes() {
    for (final t in model.types.where((t) => t.isUserDefined)) {
      final name = t.physical[_db] ?? '';
      _checkName('ユーザー定義型', name);
      if (t.kind == TypeKind.composite) {
        if (t.fields.isEmpty) _err('複合型「${t.displayName}」に項目がありません');
        final seen = <String>{};
        for (final f in t.fields) {
          _checkName('複合型「${t.displayName}」の項目', f.name);
          if (!seen.add(f.name.toLowerCase())) {
            _err('複合型「${t.displayName}」の項目名「${f.name}」が重複しています');
          }
          final ft = model.typeById(f.typeId);
          if (ft == null || (ft.physical[_db] ?? '').isEmpty) {
            _err('複合型「${t.displayName}」の項目「${f.name}」の型が存在しない、または${_db.wire}の物理名がありません');
          }
        }
      } else if (t.enumValues.isEmpty) {
        _err('列挙型「${t.displayName}」に値がありません');
      }
    }
  }

  void _checkSchemas() {
    if (!model.properties.includeSchema) return;
    final names = {
      model.properties.schema,
      for (final d in model.diagrams) d.schema,
      for (final t in model.types) t.schema,
      for (final x in model.methods) x.schema,
    }..remove('');
    for (final s in names) {
      if (!_nameOk(s)) _err('スキーマ名「$s」が形式に一致しません');
    }
    if (model.properties.schema.isEmpty && model.diagrams.any((d) => d.schema.isEmpty)) {
      _warn('出力にスキーマを含めますが、モデルのスキーマが空のため、スキーマなしで出力するエンティティがあります');
    }
  }

  void _checkMethods() {
    final seen = <String>{};
    for (final m in model.methods) {
      _checkName('メソッド', m.name);
      if (m.name.isNotEmpty && !seen.add(m.name.toLowerCase())) {
        _err('メソッド名「${m.name}」が重複しています');
      }
      for (final id in m.dependsOnTableIds) {
        if (model.entityById(id) == null) _err('メソッド「${m.name}」の依存テーブル・ビューが存在しません');
      }
    }
  }

  /// メソッドの本体チェック(参照されているときのみ。8.1-5)。
  void _checkMethodBody(MethodDef m, String usedBy, int? eid) {
    if (m.kind == MethodKind.function && m.external) return;
    if ((m.bodies[_db] ?? '').trim().isEmpty) {
      _err('メソッド「${m.name}」は$usedByから参照されていますが、${_db.wire}の本体が空です', eid);
    }
  }

  void _checkEntityNames() {
    final seen = <String, Entity>{};
    for (final e in model.entities) {
      _checkName(e is ViewEntity ? 'ビュー' : 'テーブル', e.physicalName, eid: e.id);
      final k = e.physicalName.toLowerCase();
      if (k.isNotEmpty && seen.containsKey(k)) {
        _err('エンティティの物理名「${e.physicalName}」が重複しています', e.id);
      }
      seen[k] = e;
    }
  }

  void _checkTypeUse(String typeId, String where, int eid) {
    final t = model.typeById(typeId);
    if (t == null) {
      _err('$whereの型「$typeId」が存在しません', eid);
    } else if ((t.physical[_db] ?? '').isEmpty) {
      _err('$whereの型「${t.id}」に${_db.wire}の物理名テンプレートがありません', eid);
    }
  }

  void _checkTable(TableEntity t) {
    final exp = model.expand(t);
    for (final s in exp.skipped) {
      _warn('共通列 ${s.$2.physicalName}(パターン「${s.$1}」)はテーブル「${t.physicalName}」の列と衝突するため展開されません', t.id);
    }
    if (t.columns.isEmpty && exp.columns.isEmpty) _warn('テーブル「${t.physicalName}」に列がありません', t.id);
    if (t.primaryKeyColumns.isEmpty) _warn('テーブル「${t.physicalName}」に主キーがありません', t.id);

    final names = <String>{};
    var autoCount = 0;
    for (final x in exp.columns) {
      final c = x.column;
      if (!x.isCommon) {
        _checkName('列(${t.physicalName})', c.physicalName, eid: t.id);
        if (c.physicalName.isNotEmpty && !names.add(c.physicalName.toLowerCase())) {
          _err('テーブル「${t.physicalName}」の列名「${c.physicalName}」が重複しています', t.id);
        }
      }
      _checkTypeUse(c.typeId, 'テーブル「${t.physicalName}」の列「${c.physicalName}」', t.id);
      if (model.typeById(c.typeId)?.category == TypeCategory.auto) autoCount++;
      if (c.defaultKind == DefaultKind.expression && c.defaultExpression.trim().isEmpty) {
        _err('列「${t.physicalName}.${c.physicalName}」のデフォルトの式が空です', t.id);
      }
      if (c.defaultKind == DefaultKind.method) {
        final m = c.defaultMethodId == null ? null : model.methodById(c.defaultMethodId!);
        if (m == null) {
          _err('列「${t.physicalName}.${c.physicalName}」のデフォルトメソッドが存在しません', t.id);
        } else {
          _checkMethodBody(m, '列「${t.physicalName}.${c.physicalName}」', t.id);
        }
      }
    }
    if (autoCount > 1) _err('テーブル「${t.physicalName}」にauto型の列が2つ以上あります', t.id);

    final ids = exp.columns.map((c) => c.column.id).toSet();
    for (final (kind, list) in [('インデックス', t.indexes), ('ユニーク', t.uniques)]) {
      for (final c in list) {
        for (final id in c.columnIds) {
          if (!ids.contains(id)) {
            final pc = model.patternColumnById(id);
            if (pc != null) {
              _err('共通列 ${pc.physicalName} がテーブル ${t.physicalName} に展開されません($kind)', t.id);
            } else {
              _err('テーブル「${t.physicalName}」の$kindが存在しない列を参照しています', t.id);
            }
          }
        }
        if (c.nameMode == NameMode.manual) _checkName('$kind名', c.name, eid: t.id);
      }
    }

    for (final c in t.checks) {
      if (c.nameMode == NameMode.manual) _checkName('CHECK制約名', c.name, eid: t.id);
      final label = 'テーブル「${t.physicalName}」のCHECK制約「${model.checkName(t, c)}」';
      if (c.mode == CheckMode.expression) {
        if (c.expression.trim().isEmpty) _err('$labelの式が空です', t.id);
        continue;
      }
      if (c.conditions.isEmpty) _err('$labelの条件がありません', t.id);
      for (final x in c.conditions) {
        final col = exp.columns.where((e) => e.column.id == x.columnId).firstOrNull?.column;
        if (col == null) {
          final pc = model.patternColumnById(x.columnId);
          _err(
              pc != null
                  ? '共通列 ${pc.physicalName} がテーブル ${t.physicalName} に展開されません(CHECK制約)'
                  : '$labelが存在しない列を参照しています',
              t.id);
          continue;
        }
        final colCat = model.typeById(col.typeId)?.category ?? TypeCategory.string;
        if (!CheckOperator.allowedFor(colCat).contains(x.operator)) {
          _err('$labelの列「${col.physicalName}」(${colCat.wire})では、「${x.operator.label}」は使えません', t.id);
          continue;
        }
        final (lo, hi) = x.operator.valueCount;
        final n = x.values.length;
        if (n < lo || (hi != null && n > hi)) {
          _err('$labelの「${col.physicalName} ${x.operator.label}」の値の数が正しくありません', t.id);
          continue;
        }
        final cat = model.typeById(col.typeId)?.category;
        for (final v in x.values) {
          final what = '$labelの「${col.physicalName} ${x.operator.label}」の値';
          if (v.trim().isEmpty) {
            _err('$whatが空です', t.id);
          } else if (cat == TypeCategory.boolean && !RegExp(r'^(true|false|1|0)$', caseSensitive: false).hasMatch(v.trim())) {
            _err('$what「$v」は、真偽値(true / false / 1 / 0)ではありません', t.id);
          } else if ((cat == TypeCategory.number || cat == TypeCategory.auto) &&
              !RegExp(r'^[+-]?(\d+(\.\d*)?|\.\d+)([eE][+-]?\d+)?$').hasMatch(v.trim())) {
            _err('$what「$v」は、数値ではありません', t.id);
          }
        }
      }
    }

    for (final g in t.triggers) {
      final name = model.triggerName(t, g);
      if (g.nameMode == NameMode.manual) _checkName('トリガー名', name, eid: t.id);
      if (g.events.isEmpty) _err('トリガー「$name」のイベントが未選択です', t.id);
      for (final id in g.updateColumnIds) {
        if (!ids.contains(id)) {
          final pc = model.patternColumnById(id);
          _err(pc != null
              ? '共通列 ${pc.physicalName} がテーブル ${t.physicalName} に展開されません(トリガー「$name」のUPDATE列)'
              : 'トリガー「$name」のUPDATE列が存在しない列を参照しています', t.id);
        }
      }
      if (g.updateColumnIds.isNotEmpty && !g.events.contains(TriggerEvent.update)) {
        _warn('トリガー「$name」はUPDATEのイベントがないため、UPDATE列の指定は使われません', t.id);
      }
      if (g.source == TriggerSource.public) {
        final m = g.methodId == null ? null : model.methodById(g.methodId!);
        if (m == null) {
          _err('トリガー「$name」のメソッドが存在しません', t.id);
        } else {
          _checkMethodBody(m, 'トリガー「$name」', t.id);
        }
      } else if ((g.inlineBodies[_db] ?? '').trim().isEmpty) {
        _err('トリガー「$name」の${_db.wire}の本体が空です', t.id);
      }
    }
  }

  void _checkView(ViewEntity v) {
    final label = 'ビュー「${v.physicalName}」';
    if (v.viewType == ViewType.sql) {
      if (v.sql.sql.trim().isEmpty) _err('$labelのSQLが空です', v.id);
      final names = <String>{};
      for (final c in v.sql.columns) {
        _checkName('$labelの列', c.name, eid: v.id);
        if (!names.add(c.name.toLowerCase())) _err('$labelの列名「${c.name}」が重複しています', v.id);
        _checkTypeUse(c.typeId, '$labelの列「${c.name}」', v.id);
      }
      return;
    }
    if (v.viewType == ViewType.function) {
      final m = v.function.methodId == null ? null : model.methodById(v.function.methodId!);
      if (m == null) {
        _err('$labelの関数が未選択です', v.id);
      } else {
        _checkMethodBody(m, label, v.id);
      }
      if (v.function.columns.isEmpty) _err('$labelの戻り列がありません', v.id);
      final names = <String>{};
      for (final c in v.function.columns) {
        _checkName('$labelの戻り列', c.name, eid: v.id);
        if (!names.add(c.name.toLowerCase())) _err('$labelの戻り列名「${c.name}」が重複しています', v.id);
        _checkTypeUse(c.typeId, '$labelの戻り列「${c.name}」', v.id);
      }
      return;
    }
    final j = v.join;
    if (j.sources.isEmpty) _err('$labelのソースがありません', v.id);
    if (j.columns.isEmpty) _err('$labelの出力列がありません', v.id);
    final aliases = <String>{};
    for (var i = 0; i < j.sources.length; i++) {
      final s = j.sources[i];
      if (!aliases.add(s.alias.toLowerCase())) _err('$labelのエイリアス「${s.alias}」が重複しています', v.id);
      final t = model.tableById(s.entityId);
      if (t == null) {
        _err('$labelのソースが存在しません', v.id);
        continue;
      }
      if (i > 0) {
        if (s.on.isEmpty) _err('$labelの「${s.alias}」に結合条件がありません', v.id);
        for (final o in s.on) {
          final leftSrc = j.sources.where((x) => x.alias == o.leftAlias).firstOrNull;
          final leftT = leftSrc == null ? null : model.tableById(leftSrc.entityId);
          if (leftT == null || model.findExpandedColumn(leftT, o.leftColumnId) == null) {
            _err('$labelの結合条件の左の列が不正です', v.id);
          }
          if (model.findExpandedColumn(t, o.rightColumnId) == null) {
            _err('$labelの結合条件の右の列が不正です', v.id);
          }
        }
      }
    }
    final outNames = <String>{};
    for (final c in j.columns) {
      final src = j.sources.where((x) => x.alias == c.alias).firstOrNull;
      final t = src == null ? null : model.tableById(src.entityId);
      final col = t == null ? null : model.findExpandedColumn(t, c.columnId);
      if (col == null) {
        _err('$labelの出力列が参照する列が存在しません(展開されない共通列を含む)', v.id);
        continue;
      }
      final name = c.name.isNotEmpty ? c.name : col.column.physicalName;
      _checkName('$labelの出力列', name, eid: v.id);
      if (!outNames.add(name.toLowerCase())) _err('$labelの出力列名「$name」が重複しています', v.id);
    }
  }

  void _checkConstraintNames() {
    final seen = <String>{};
    void add(String n, String kind) {
      if (n.isEmpty) return;
      if (!seen.add(n.toLowerCase())) _err('制約名「$n」($kind)が重複しています');
    }

    for (final t in model.tables) {
      if (t.primaryKeyColumns.isNotEmpty) add(model.primaryKeyName(t, pkNaming), '主キー');
      for (final c in t.checks) {
        add(model.checkName(t, c), 'CHECK');
      }
      for (final c in t.indexes) {
        add(model.indexName(t, c), 'インデックス');
      }
      for (final c in t.uniques) {
        add(model.uniqueName(t, c), 'ユニーク');
      }
      for (final g in t.triggers) {
        add(model.triggerName(t, g), 'トリガー');
      }
    }
    for (final r in model.relationships) {
      final n = model.foreignKeyName(r);
      if (r.nameMode == NameMode.manual) _checkName('外部キー名', n);
      add(n, '外部キー');
    }
  }

  void _checkRelationship(Relationship r) {
    final p = model.tableById(r.parentId), c = model.tableById(r.childId);
    final label = 'リレーションシップ「${model.foreignKeyName(r)}」';
    if (p == null || c == null) {
      _err('$labelの端点のテーブルが存在しません');
      return;
    }
    if (r.columnPairs.isEmpty) {
      _err('$labelの列対応が未割当です');
      return;
    }
    final parentIds = r.columnPairs.map((x) => x.parentColumnId).toSet();
    final pk = p.primaryKeyColumns.map((x) => x.id).toSet();
    final isKey = (pk.isNotEmpty && pk.length == parentIds.length && pk.containsAll(parentIds)) ||
        p.uniques.any((u) => u.columnIds.toSet().length == parentIds.length &&
            u.columnIds.toSet().containsAll(parentIds));
    if (!isKey) _err('$labelの親の列が主キーでもユニーク制約でもありません');
    final pe = model.expand(p), ce = model.expand(c);
    for (final pair in r.columnPairs) {
      final pc = pe.columns.where((x) => x.column.id == pair.parentColumnId).firstOrNull;
      final cc = ce.columns.where((x) => x.column.id == pair.childColumnId).firstOrNull;
      if (pc == null || cc == null) {
        _err('$labelの列対応が、存在しない列、または展開されない共通列を参照しています');
        continue;
      }
      if (pc.column.typeId != cc.column.typeId &&
          !(model.typeById(pc.column.typeId)?.category == TypeCategory.auto &&
              cc.column.typeId == 'integer')) {
        _warn('$labelの外部キー列「${cc.column.physicalName}」と親の列「${pc.column.physicalName}」の型が異なります');
      }
      for (final action in [r.onDelete, r.onUpdate]) {
        if (action == RefAction.setDefault && cc.column.defaultKind == DefaultKind.none) {
          _warn('$labelはSET DEFAULTですが、子の列「${cc.column.physicalName}」にデフォルトがありません');
        }
      }
    }
  }
}
