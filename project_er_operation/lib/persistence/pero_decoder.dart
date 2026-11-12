import 'dart:convert';

import '../model/model.dart';
import 'integrity.dart';
import 'pero_encoder.dart';

/// 読込結果。[model] がnullのときは [error] に理由がある。
class LoadResult {
  LoadResult.ok(this.model, this.repairs) : error = null, tooNew = false;
  LoadResult.fail(this.error, {this.tooNew = false})
      : model = null,
        repairs = Repairs();
  final ErModel? model;
  final Repairs repairs;
  final String? error;

  /// ファイルが現行より新しい形式のとき。
  final bool tooNew;
}

/// `.pero` の復元と、JSON構造の整合性確認(9.4)。
/// 欠落・型の不一致・値域外は標準(付録Aの既定値)に置き換え、記録する。
class PeroDecoder {
  PeroDecoder._(this._rep);
  final Repairs _rep;

  static LoadResult decode(String text) {
    Object? root;
    try {
      root = jsonDecode(text);
    } on FormatException catch (e) {
      return LoadResult.fail('JSONの構文エラー: ${e.message}');
    }
    if (root is! Map<String, dynamic>) {
      return LoadResult.fail('JSONのルートがオブジェクトではありません');
    }
    final fv = root['formatVersion'];
    if (fv is int && fv > currentFormatVersion) {
      return LoadResult.fail('このファイルは新しい形式(formatVersion $fv)です。アプリを更新してください',
          tooNew: true);
    }
    final rep = Repairs();
    final model = PeroDecoder._(rep)._model(root);
    final (ok, r2) = IntegrityRepairer.repairAll(model);
    rep.addAll(r2);
    if (!ok) return LoadResult.fail('整合性を回復できませんでした');
    return LoadResult.ok(model, rep);
  }

  // ---- 単体要素の復元(コマンドの引数復元用) ----
  static Entity? entityFromMap(Object? m) => PeroDecoder._(Repairs())._entity(m, 'entity');
  static DataType? typeFromMap(Object? m) => PeroDecoder._(Repairs())._type(m, 'type');
  static MethodDef? methodFromMap(Object? m) => PeroDecoder._(Repairs())._method(m, 'method');
  static CommonColumnPattern? patternFromMap(Object? m) =>
      PeroDecoder._(Repairs())._pattern(m, 'pattern');

  // ---- 読み取りヘルパ ----
  Map<String, dynamic> _obj(Object? v, String path) {
    if (v is Map<String, dynamic>) return v;
    _rep.add('$path: オブジェクトでないため既定値に置換');
    return {};
  }

  List<Object?> _list(Object? v, String path) {
    if (v is List) return v;
    if (v != null) _rep.add('$path: 配列でないため空に置換');
    return [];
  }

  String _str(Map<String, dynamic> m, String k, String path, [String def = '']) {
    final v = m[k];
    if (v is String) return v;
    _rep.add('$path.$k: ${m.containsKey(k) ? '型の不一致' : '欠落'}のため既定値に置換');
    return def;
  }

  bool _bool(Map<String, dynamic> m, String k, String path, bool def) {
    final v = m[k];
    if (v is bool) return v;
    _rep.add('$path.$k: ${m.containsKey(k) ? '型の不一致' : '欠落'}のため既定値に置換');
    return def;
  }

  int? _intOrNull(Map<String, dynamic> m, String k, String path) {
    final v = m[k];
    if (v == null) return null;
    if (v is int) return v;
    if (v is double && v == v.roundToDouble()) return v.toInt();
    _rep.add('$path.$k: 型の不一致のためnullに置換');
    return null;
  }

  int? _id(Map<String, dynamic> m, String path) {
    final v = m['id'];
    if (v is int && v > 0) return v;
    _rep.add('$path.id: 不正なIDのため項目を削除');
    return null;
  }

  double _num(Map<String, dynamic> m, String k, String path, double def,
      {double? min, double? max}) {
    final v = m[k];
    if (v is num) {
      final d = v.toDouble();
      if ((min == null || d >= min) && (max == null || d <= max)) return d;
      _rep.add('$path.$k: 値域外のため既定値に置換');
      return def;
    }
    _rep.add('$path.$k: ${m.containsKey(k) ? '型の不一致' : '欠落'}のため既定値に置換');
    return def;
  }

  T _enum<T extends Enum>(List<T> values, Map<String, dynamic> m, String k, String path, T def) {
    final e = enumFromWire(values, m[k]);
    if (e != null) return e;
    _rep.add('$path.$k: ${m.containsKey(k) ? '値域外' : '欠落'}のため既定値に置換');
    return def;
  }

  Map<DbKind, String> _perDb(Object? v, String path) {
    final m = _obj(v, path);
    return {for (final d in DbKind.values) d: _str(m, d.wire, path)};
  }

  // ---- 各要素 ----
  static const _known = {
    'formatVersion', 'appVersion', 'id', 'nextId', 'properties', 'types', 'methods',
    'commonColumnPatterns', 'entities', 'relationships', 'diagrams'
  };

  ErModel _model(Map<String, dynamic> root) {
    if (!root.containsKey('formatVersion')) {
      _rep.add('formatVersion: 欠落のため1とみなす');
    }
    final props = _obj(root['properties'], 'properties');
    final nextIdRaw = root['nextId'];
    final m = ErModel(
      id: root['id'] is int ? root['id'] as int : 1,
      nextId: nextIdRaw is int && nextIdRaw > 0 ? nextIdRaw : 1,
      appVersion: root['appVersion'] is String ? root['appVersion'] as String : '',
      properties: ModelProperties(
        outputFileName: _str(props, 'outputFileName', 'properties'),
        outputFolder: _str(props, 'outputFolder', 'properties'),
        targetDb: _enum(DbKind.values, props, 'targetDb', 'properties', DbKind.postgresql),
        postPath: _str(props, 'postPath', 'properties'),
        startQuery: _str(props, 'startQuery', 'properties'),
        endQuery: _str(props, 'endQuery', 'properties'),
      ),
    );
    if (nextIdRaw is! int) _rep.add('nextId: 不正のため再計算');
    for (final k in root.keys) {
      if (!_known.contains(k)) m.unknownKeys[k] = root[k];
    }
    var i = 0;
    for (final v in _list(root['types'], 'types')) {
      final t = _type(v, 'types[${i++}]');
      if (t != null) m.types.add(t);
    }
    i = 0;
    for (final v in _list(root['methods'], 'methods')) {
      final x = _method(v, 'methods[${i++}]');
      if (x != null) m.methods.add(x);
    }
    i = 0;
    for (final v in _list(root['commonColumnPatterns'], 'commonColumnPatterns')) {
      final x = _pattern(v, 'commonColumnPatterns[${i++}]');
      if (x != null) m.patterns.add(x);
    }
    i = 0;
    for (final v in _list(root['entities'], 'entities')) {
      final x = _entity(v, 'entities[${i++}]');
      if (x != null) m.entities.add(x);
    }
    i = 0;
    for (final v in _list(root['relationships'], 'relationships')) {
      final x = _relationship(v, 'relationships[${i++}]');
      if (x != null) m.relationships.add(x);
    }
    i = 0;
    for (final v in _list(root['diagrams'], 'diagrams')) {
      final x = _diagram(v, 'diagrams[${i++}]');
      if (x != null) m.diagrams.add(x);
    }
    return m;
  }

  DataType? _type(Object? v, String path) {
    final m = _obj(v, path);
    final id = m['id'];
    if (id is! String || id.isEmpty) {
      _rep.add('$path.id: 不正なため項目を削除');
      return null;
    }
    final params = _obj(m['defaultParams'], '$path.defaultParams');
    return DataType(
      id: id,
      displayName: _str(m, 'displayName', path, id),
      paramKind: _enum(ParamKind.values, m, 'paramKind', path, ParamKind.none),
      defaultLength: _intOrNull(params, 'length', '$path.defaultParams'),
      defaultPrecision: _intOrNull(params, 'precision', '$path.defaultParams'),
      defaultScale: _intOrNull(params, 'scale', '$path.defaultParams'),
      category: _enum(TypeCategory.values, m, 'category', path, TypeCategory.string),
      physical: _perDb(m['physical'], '$path.physical'),
      isStandard: standardTypeIds.contains(id),
    );
  }

  MethodDef? _method(Object? v, String path) {
    final m = _obj(v, path);
    final id = _id(m, path);
    if (id == null) return null;
    return MethodDef(
      id: id,
      kind: _enum(MethodKind.values, m, 'kind', path, MethodKind.function),
      name: _str(m, 'name', path),
      external: _bool(m, 'external', path, false),
      call: _perDb(m['call'], '$path.call'),
      bodies: _perDb(m['bodies'], '$path.bodies'),
    );
  }

  ColumnDef? _column(Object? v, String path, {required bool withPk}) {
    final m = _obj(v, path);
    final id = _id(m, path);
    if (id == null) return null;
    final typeId = m['typeId'];
    if (typeId is! String) {
      _rep.add('$path.typeId: 不正のため項目を削除');
      return null;
    }
    return ColumnDef(
      id: id,
      logicalName: _str(m, 'logicalName', path),
      physicalName: _str(m, 'physicalName', path),
      typeId: typeId,
      length: _intOrNull(m, 'length', path),
      precision: _intOrNull(m, 'precision', path),
      scale: _intOrNull(m, 'scale', path),
      pk: withPk ? _bool(m, 'pk', path, false) : false,
      notNull: _bool(m, 'notNull', path, false),
      defaultKind: _enum(DefaultKind.values, m, 'defaultKind', path, DefaultKind.none),
      defaultValue: _str(m, 'defaultValue', path),
      defaultMethodId: _intOrNull(m, 'defaultMethodId', path),
      comment: _str(m, 'comment', path),
    );
  }

  CommonColumnPattern? _pattern(Object? v, String path) {
    final m = _obj(v, path);
    final id = _id(m, path);
    if (id == null) return null;
    final cols = <ColumnDef>[];
    var i = 0;
    for (final c in _list(m['columns'], '$path.columns')) {
      final x = _column(c, '$path.columns[${i++}]', withPk: false);
      if (x != null) cols.add(x);
    }
    return CommonColumnPattern(
      id: id,
      name: _str(m, 'name', path),
      enabled: _bool(m, 'enabled', path, true),
      include: _str(m, 'include', path, '^.*\$'),
      exclude: _str(m, 'exclude', path),
      position: _enum(PatternPosition.values, m, 'position', path, PatternPosition.end),
      columns: cols,
    );
  }

  List<ConstraintDef> _constraints(Object? v, String path) {
    final out = <ConstraintDef>[];
    var i = 0;
    for (final x in _list(v, path)) {
      final p = '$path[${i++}]';
      final m = _obj(x, p);
      final id = _id(m, p);
      if (id == null) continue;
      final ids = <int>[];
      for (final c in _list(m['columnIds'], '$p.columnIds')) {
        if (c is int) {
          ids.add(c);
        } else {
          _rep.add('$p.columnIds: 不正な要素を削除');
        }
      }
      out.add(ConstraintDef(
          id: id,
          nameMode: _enum(NameMode.values, m, 'nameMode', p, NameMode.auto),
          name: _str(m, 'name', p),
          columnIds: ids));
    }
    return out;
  }

  TriggerDef? _trigger(Object? v, String path) {
    final m = _obj(v, path);
    final id = _id(m, path);
    if (id == null) return null;
    final events = <TriggerEvent>[];
    for (final e in _list(m['events'], '$path.events')) {
      final x = enumFromWire(TriggerEvent.values, e);
      if (x != null && !events.contains(x)) {
        events.add(x);
      } else {
        _rep.add('$path.events: 不正な要素を削除');
      }
    }
    if (events.isEmpty) {
      events.add(TriggerEvent.insert);
      _rep.add('$path.events: 空のため既定値に置換');
    }
    return TriggerDef(
      id: id,
      source: _enum(TriggerSource.values, m, 'source', path, TriggerSource.inline),
      methodId: _intOrNull(m, 'methodId', path),
      inlineBodies: _perDb(m['inlineBodies'], '$path.inlineBodies'),
      nameMode: _enum(NameMode.values, m, 'nameMode', path, NameMode.auto),
      name: _str(m, 'name', path),
      timing: _enum(TriggerTiming.values, m, 'timing', path, TriggerTiming.before),
      events: events,
      forEach: _enum(TriggerForEach.values, m, 'forEach', path, TriggerForEach.row),
      when: _str(m, 'when', path),
    );
  }

  Entity? _entity(Object? v, String path) {
    final m = _obj(v, path);
    final id = _id(m, path);
    if (id == null) return null;
    final kind = enumFromWire(EntityKind.values, m['kind']);
    if (kind == null) {
      _rep.add('$path.kind: 不正のため項目を削除');
      return null;
    }
    final logical = _str(m, 'logicalName', path);
    final physical = _str(m, 'physicalName', path);
    final comment = _str(m, 'comment', path);
    final locked = _bool(m, 'locked', path, false);
    final pre = _str(m, 'preQuery', path);
    final post = _str(m, 'postQuery', path);
    if (kind == EntityKind.table) {
      final cols = <ColumnDef>[];
      var i = 0;
      for (final c in _list(m['columns'], '$path.columns')) {
        final x = _column(c, '$path.columns[${i++}]', withPk: true);
        if (x != null) cols.add(x);
      }
      final trig = <TriggerDef>[];
      i = 0;
      for (final g in _list(m['triggers'], '$path.triggers')) {
        final x = _trigger(g, '$path.triggers[${i++}]');
        if (x != null) trig.add(x);
      }
      return TableEntity(
        id: id,
        logicalName: logical,
        physicalName: physical,
        comment: comment,
        locked: locked,
        preQuery: pre,
        postQuery: post,
        columns: cols,
        indexes: _constraints(m['indexes'], '$path.indexes'),
        uniques: _constraints(m['uniques'], '$path.uniques'),
        triggers: trig,
      );
    }
    final vt = _enum(ViewType.values, m, 'viewType', path, ViewType.join);
    final jm = _obj(m['join'], '$path.join');
    final sources = <ViewSource>[];
    var i = 0;
    for (final s in _list(jm['sources'], '$path.join.sources')) {
      final p = '$path.join.sources[${i++}]';
      final sm = _obj(s, p);
      final eid = sm['entityId'];
      if (eid is! int) {
        _rep.add('$p.entityId: 不正のためソースを削除');
        continue;
      }
      final on = <JoinOn>[];
      for (final o in _list(sm['on'], '$p.on')) {
        final om = _obj(o, '$p.on');
        final l = om['leftColumnId'], r = om['rightColumnId'];
        if (l is! int || r is! int) {
          _rep.add('$p.on: 不正な結合条件を削除');
          continue;
        }
        on.add(JoinOn(
            leftAlias: _str(om, 'leftAlias', '$p.on'), leftColumnId: l, rightColumnId: r));
      }
      sources.add(ViewSource(
        alias: _str(sm, 'alias', p),
        entityId: eid,
        joinType: _enum(JoinType.values, sm, 'joinType', p, JoinType.inner),
        on: on,
      ));
    }
    final outCols = <ViewOutputColumn>[];
    i = 0;
    for (final c in _list(jm['columns'], '$path.join.columns')) {
      final p = '$path.join.columns[${i++}]';
      final cm = _obj(c, p);
      final cid = cm['columnId'];
      if (cid is! int) {
        _rep.add('$p.columnId: 不正のため出力列を削除');
        continue;
      }
      outCols.add(ViewOutputColumn(
          alias: _str(cm, 'alias', p),
          columnId: cid,
          name: _str(cm, 'name', p),
          logicalName: _str(cm, 'logicalName', p)));
    }
    final fm = _obj(m['function'], '$path.function');
    final fcols = <FunctionReturnColumn>[];
    i = 0;
    for (final c in _list(fm['columns'], '$path.function.columns')) {
      final p = '$path.function.columns[${i++}]';
      final cm = _obj(c, p);
      final tid = cm['typeId'];
      if (tid is! String) {
        _rep.add('$p.typeId: 不正のため戻り列を削除');
        continue;
      }
      fcols.add(FunctionReturnColumn(
        name: _str(cm, 'name', p),
        logicalName: _str(cm, 'logicalName', p),
        typeId: tid,
        length: _intOrNull(cm, 'length', p),
        precision: _intOrNull(cm, 'precision', p),
        scale: _intOrNull(cm, 'scale', p),
      ));
    }
    return ViewEntity(
      id: id,
      logicalName: logical,
      physicalName: physical,
      comment: comment,
      locked: locked,
      preQuery: pre,
      postQuery: post,
      viewType: vt,
      join: ViewJoinDef(sources: sources, columns: outCols, where: _str(jm, 'where', '$path.join')),
      function: ViewFunctionDef(
        methodId: _intOrNull(fm, 'methodId', '$path.function'),
        args: [
          for (final a in _list(fm['args'], '$path.function.args'))
            if (a is String) a
        ],
        columns: fcols,
      ),
    );
  }

  Relationship? _relationship(Object? v, String path) {
    final m = _obj(v, path);
    final id = _id(m, path);
    if (id == null) return null;
    final pid = m['parentId'], cid = m['childId'];
    if (pid is! int || cid is! int) {
      _rep.add('$path: 端点が不正のため項目を削除');
      return null;
    }
    final pairs = <ColumnPair>[];
    var i = 0;
    for (final p in _list(m['columnPairs'], '$path.columnPairs')) {
      final pm = _obj(p, '$path.columnPairs[${i++}]');
      final a = pm['parentColumnId'], b = pm['childColumnId'];
      if (a is! int || b is! int) {
        _rep.add('$path.columnPairs: 不正な列対応のため項目を削除');
        return null;
      }
      pairs.add(ColumnPair(parentColumnId: a, childColumnId: b));
    }
    return Relationship(
      id: id,
      locked: _bool(m, 'locked', path, false),
      parentId: pid,
      childId: cid,
      columnPairs: pairs,
      dependency: _bool(m, 'dependency', path, true),
      childMultiplicity:
          _enum(Multiplicity.values, m, 'childMultiplicity', path, Multiplicity.many),
      nameMode: _enum(NameMode.values, m, 'nameMode', path, NameMode.auto),
      name: _str(m, 'name', path),
      onDelete: _enum(RefAction.values, m, 'onDelete', path, RefAction.noAction),
      onUpdate: _enum(RefAction.values, m, 'onUpdate', path, RefAction.noAction),
    );
  }

  Diagram? _diagram(Object? v, String path) {
    final m = _obj(v, path);
    final id = _id(m, path);
    if (id == null) return null;
    final placements = <Placement>[];
    var i = 0;
    for (final p in _list(m['placements'], '$path.placements')) {
      final pp = '$path.placements[${i++}]';
      final pm = _obj(p, pp);
      final eid = pm['entityId'];
      if (eid is! int) {
        _rep.add('$pp.entityId: 不正のため配置を削除');
        continue;
      }
      placements.add(Placement(
        entityId: eid,
        x: _num(pm, 'x', pp, 0),
        y: _num(pm, 'y', pp, 0),
        collapsed: _bool(pm, 'collapsed', pp, false),
      ));
    }
    final vm = _obj(m['view'], '$path.view');
    int pageCount(String k) {
      final x = m[k];
      if (x is int && x >= 1) return x;
      _rep.add('$path.$k: ${m.containsKey(k) ? '値域外' : '欠落'}のため既定値に置換');
      return 1;
    }

    return Diagram(
      id: id,
      name: _str(m, 'name', path, 'ダイアグラム'),
      pageSize: _enum(PageSize.values, m, 'pageSize', path, PageSize.a3),
      orientation: _enum(Orientation.values, m, 'orientation', path, Orientation.landscape),
      pageRows: pageCount('pageRows'),
      pageCols: pageCount('pageCols'),
      placements: placements,
      view: DiagramView(
        zoom: _num(vm, 'zoom', '$path.view', 1.0, min: 0.25, max: 4.0),
        scrollX: _num(vm, 'scrollX', '$path.view', 0),
        scrollY: _num(vm, 'scrollY', '$path.view', 0),
      ),
    );
  }
}
