import 'dart:convert';

import '../model/model.dart';

/// 生成用JSON(付録B)のバージョン。付録Bを変更するときに上げる。
const int postApiVersion = 2;

/// 生成用JSONを作る。生成前検証(9.5)のエラーがないモデルを前提とする。
class GenerationJsonBuilder {
  GenerationJsonBuilder(
    this.model, {
    this.pkNaming = const PkNaming(),
    this.dropBeforeCreate = false,
  });
  final ErModel model;

  /// 主キー制約名の規則(設定。6.4-1)。
  final PkNaming pkNaming;

  /// 再実行用のDROP文を付ける(設定。9.6-7)。
  final bool dropBeforeCreate;

  late final DbKind _db = model.properties.targetDb;

  String buildText({bool indent = false}) => indent
      ? const JsonEncoder.withIndent('  ').convert(build())
      : jsonEncode(build());

  Map<String, Object?> build() {
    final deferred = <int>{};
    final ordered = _orderTables(deferred);
    return {
      'apiVersion': postApiVersion,
      'targetDb': _db.wire,
      'model': {
        'outputFileName': model.properties.outputFileName,
        'startQuery': model.properties.startQuery,
        'endQuery': model.properties.endQuery,
        'dropBeforeCreate': dropBeforeCreate,
      },
      'schemas': _schemas(),
      'userTypes': _userTypes(),
      'methods': _methods(ordered),
      'tables': [for (final t in ordered) _table(t)],
      'foreignKeys': [
        for (final r in (model.relationships.toList()..sort((a, b) => a.id.compareTo(b.id))))
          _foreignKey(r, deferred.contains(r.id))
      ],
      'views': [
        for (final v in (model.views.toList()..sort((a, b) => a.id.compareTo(b.id)))) _view(v)
      ],
    };
  }

  /// メソッドの一覧。ファンクションは、本体で呼んでいる別のファンクションより後に並べ、
  /// 出力位置(afterTableId / afterViewId)も、呼んでいる先より前にならないよう引き上げる(8.1-14)。
  /// LANGUAGE sql のファンクションは、作成時に本体が検査されるため、呼出し先が先に存在する必要がある。
  List<Map<String, Object?>> _methods(List<TableEntity> ordered) {
    final views = model.views.toList()..sort((a, b) => a.id.compareTo(b.id));
    final fns = [for (final m in model.methods) if (m.kind == MethodKind.function) m];
    final nameRe = <int, RegExp>{
      for (final f in fns)
        f.id: RegExp(r'(?<![A-Za-z0-9_$])' + RegExp.escape(f.name) + r'\s*\(', caseSensitive: false),
    };
    // 呼出し先(定義を出力するファンクションのみ)
    final callees = <int, List<MethodDef>>{};
    for (final f in fns) {
      final body = f.bodies[_db] ?? '';
      callees[f.id] = [
        if (!f.external && body.trim().isNotEmpty)
          for (final g in fns)
            if (g.id != f.id &&
                !g.external &&
                (g.bodies[_db] ?? '').trim().isNotEmpty &&
                nameRe[g.id]!.hasMatch(body))
              g
      ];
    }

    int ownRank(MethodDef m) {
      final v = _afterView(m);
      if (v != null) return ordered.length + views.indexWhere((x) => x.id == v);
      final t = _afterTable(m, ordered);
      return t == null ? -1 : ordered.indexWhere((x) => x.id == t);
    }

    final rank = <int, int>{};
    final order = <MethodDef>[];
    final visiting = <int>{};
    void visit(MethodDef f) {
      if (rank.containsKey(f.id) || !visiting.add(f.id)) return;
      var r = ownRank(f);
      for (final g in callees[f.id]!) {
        visit(g);
        final gr = rank[g.id];
        if (gr != null && gr > r) r = gr;
      }
      rank[f.id] = r;
      order.add(f);
    }

    for (final f in fns) {
      visit(f);
    }
    // 位置の昇順に並べる(同じ位置の中は、呼出し先が先の順を保つ)。
    final sorted = [
      for (var i = 0; i < order.length; i++) (i, order[i]),
    ]..sort((a, b) {
        final c = rank[a.$2.id]!.compareTo(rank[b.$2.id]!);
        return c != 0 ? c : a.$1.compareTo(b.$1);
      });

    Map<String, Object?> json(MethodDef m, {int? tableId, int? viewId}) => {
          'id': m.id,
          'name': m.name,
          'kind': m.kind.wire,
          'external': m.external,
          'call': m.kind == MethodKind.function ? m.callExpr(_db) : '',
          'body': m.bodies[_db] ?? '',
          'comment': m.comment,
          'args': m.args,
          'afterTableId': tableId,
          'afterViewId': viewId,
        };

    return [
      for (final (_, f) in sorted)
        () {
          final r = rank[f.id]!;
          if (r >= ordered.length) return json(f, viewId: views[r - ordered.length].id);
          if (r >= 0) return json(f, tableId: ordered[r].id);
          return json(f);
        }(),
      for (final m in model.methods)
        if (m.kind != MethodKind.function) json(m),
    ];
  }

  /// 出力に使うスキーマの一覧(重複なし。出力にスキーマを含めるときのみ)。
  List<String> _schemas() {
    final out = <String>[];
    for (final e in model.entities) {
      final s = model.schemaOf(e);
      if (s.isNotEmpty && !out.contains(s)) out.add(s);
    }
    return out;
  }

  /// ユーザー定義型(複合型、列挙型)。使われる型が先になる順。対象DBの物理名があるものだけ。
  List<Map<String, Object?>> _userTypes() {
    final out = <Map<String, Object?>>[];
    final done = <String>{};
    void visit(DataType t) {
      if (!done.add(t.id)) return;
      for (final f in t.fields) {
        final d = model.typeById(f.typeId);
        if (d != null && d.isUserDefined) visit(d);
      }
      final name = t.physical[_db] ?? '';
      if (name.isEmpty) return;
      out.add({
        'name': name,
        'kind': t.kind.wire,
        'fields': [
          for (final f in t.fields)
            {
              'name': f.name,
              'type': model.typeById(f.typeId)?.expand(_db,
                      length: f.length, precision: f.precision, scale: f.scale) ??
                  '',
            }
        ],
        'values': t.enumValues,
      });
    }

    for (final t in model.types.where((t) => t.isUserDefined)) {
      visit(t);
    }
    return out;
  }

  /// ファンクションを出力する位置(ビュー)。依存にビューがあるとき、最後に作成されるビューのID(8.1-3)。
  /// ビューはテーブルの後に作成されるため、ビューへの依存があれば、テーブルへの位置より優先する。
  int? _afterView(MethodDef m) {
    final views = (model.views.toList()..sort((a, b) => a.id.compareTo(b.id)));
    int? best;
    var bestPos = -1;
    for (final id in m.dependsOnTableIds) {
      final pos = views.indexWhere((v) => v.id == id);
      if (pos > bestPos) {
        bestPos = pos;
        best = id;
      }
    }
    return best;
  }

  /// ファンクションを出力する位置。依存テーブルのうち、最後に作成されるテーブルのID(8.1-3)。
  /// ビューへの依存があるときはnull(ビューの後に出力する)。
  int? _afterTable(MethodDef m, List<TableEntity> ordered) {
    if (_afterView(m) != null) return null;
    int? best;
    var bestPos = -1;
    for (final id in m.dependsOnTableIds) {
      final pos = ordered.indexWhere((t) => t.id == id);
      if (pos > bestPos) {
        bestPos = pos;
        best = id;
      }
    }
    return best;
  }

  /// 親から子の順(トポロジカル順)。循環を作る外部キーは [deferred] に入れる(9.6-3)。
  List<TableEntity> _orderTables(Set<int> deferred) {
    final tables = model.tables.toList()..sort((a, b) => a.id.compareTo(b.id));
    final done = <int>{};
    final stack = <int>{};
    final out = <TableEntity>[];
    void visit(TableEntity t) {
      done.add(t.id);
      stack.add(t.id);
      final parents = model.relationships.where((r) => r.childId == t.id && r.parentId != t.id).toList()
        ..sort((a, b) => a.id.compareTo(b.id));
      for (final r in parents) {
        if (stack.contains(r.parentId)) {
          deferred.add(r.id);
        } else if (!done.contains(r.parentId)) {
          final p = model.tableById(r.parentId);
          if (p != null) visit(p);
        }
      }
      stack.remove(t.id);
      out.add(t);
    }

    for (final t in tables) {
      if (!done.contains(t.id)) visit(t);
    }
    return out;
  }

  String _typeString(ColumnDef c) =>
      model.typeById(c.typeId)?.expand(_db,
          length: c.length, precision: c.precision, scale: c.scale) ??
      '';

  String _category(String typeId) =>
      (model.typeById(typeId)?.category ?? TypeCategory.string).wire;

  Map<String, Object?> _column(ExpandedColumn x) {
    final c = x.column;
    final String call;
    if (c.defaultKind == DefaultKind.method && c.defaultMethodId != null) {
      call = model.methodById(c.defaultMethodId!)?.callExpr(_db) ?? '';
    } else {
      call = '';
    }
    return {
      'id': c.id,
      'origin': x.isCommon ? 'common' : 'table',
      'logicalName': c.logicalName,
      'physicalName': c.physicalName,
      'comment': c.comment,
      'type': _typeString(c),
      'typeCategory': _category(c.typeId),
      'notNull': c.notNull || c.pk,
      'pk': c.pk,
      'default': {
        'kind': c.defaultKind.wire,
        'value': c.defaultKind == DefaultKind.value ? c.defaultValue : '',
        'call': call,
        'expression': c.defaultKind == DefaultKind.expression ? c.defaultExpression : '',
      },
    };
  }

  Map<String, Object?> _table(TableEntity t) {
    final cols = model.expand(t).columns;
    List<String> names(List<int> ids) => [
          for (final id in ids)
            for (final x in cols)
              if (x.column.id == id) x.column.physicalName
        ];
    final pk = t.primaryKeyColumns;
    return {
      'id': t.id,
      'schema': model.schemaOf(t),
      'logicalName': t.logicalName,
      'physicalName': t.physicalName,
      'comment': t.comment,
      'preQuery': t.preQuery,
      'postQuery': t.postQuery,
      'columns': [for (final x in cols) _column(x)],
      'primaryKey': pk.isEmpty
          ? null
          : {
              'name': model.primaryKeyName(t, pkNaming),
              'columns': pk.map((c) => c.physicalName).toList()
            },
      'indexes': [
        for (final c in t.indexes)
          {'name': model.indexName(t, c), 'columns': names(c.columnIds)}
      ],
      'uniques': [
        for (final c in t.uniques)
          {
            'name': model.uniqueName(t, c),
            'columns': names(c.columnIds),
            'nullsNotDistinct': c.nullsNotDistinct,
          }
      ],
      'checks': [
        for (final c in t.checks) {'name': model.checkName(t, c), 'expression': c.expression}
      ],
      'triggers': [
        for (var i = 0; i < t.triggers.length; i++) _trigger(t, t.triggers[i], i + 1)
      ],
    };
  }

  Map<String, Object?> _trigger(TableEntity t, TriggerDef g, int order) {
    final name = model.triggerName(t, g);
    final MethodDef? m = g.source == TriggerSource.public && g.methodId != null
        ? model.methodById(g.methodId!)
        : null;
    final raw = g.source == TriggerSource.public ? (m?.bodies[_db] ?? '') : (g.inlineBodies[_db] ?? '');
    return {
      'order': order,
      'name': name,
      'timing': g.timing.wire,
      'events': g.events.map((e) => e.wire).toList(),
      'forEach': g.forEach.wire,
      'when': g.when,
      'args': g.args,
      'updateColumns': [
        for (final id in g.updateColumnIds)
          model.findExpandedColumn(t, id)?.column.physicalName ?? ''
      ],
      'methodName': m?.name,
      'body': raw.replaceAll('{{table}}', t.physicalName).replaceAll('{{trigger}}', name),
    };
  }

  Map<String, Object?> _foreignKey(Relationship r, bool deferred) {
    final p = model.tableById(r.parentId)!, c = model.tableById(r.childId)!;
    String colName(TableEntity t, int id) =>
        model.findExpandedColumn(t, id)?.column.physicalName ?? '';
    return {
      'id': r.id,
      'name': model.foreignKeyName(r),
      'childTable': c.physicalName,
      'childSchema': model.schemaOf(c),
      'parentTable': p.physicalName,
      'parentSchema': model.schemaOf(p),
      'columns': [
        for (final pair in r.columnPairs)
          {
            'child': colName(c, pair.childColumnId),
            'parent': colName(p, pair.parentColumnId),
          }
      ],
      'onDelete': r.onDelete.sql,
      'onUpdate': r.onUpdate.sql,
      'deferrable': r.deferrable.sql,
      'deferred': deferred,
    };
  }

  Map<String, Object?> _view(ViewEntity v) {
    final base = <String, Object?>{
      'id': v.id,
      'schema': model.schemaOf(v),
      'logicalName': v.logicalName,
      'physicalName': v.physicalName,
      'comment': v.comment,
      'preQuery': v.preQuery,
      'postQuery': v.postQuery,
      'viewType': v.viewType.wire,
    };
    if (v.viewType == ViewType.function) {
      final m = v.function.methodId == null ? null : model.methodById(v.function.methodId!);
      return {
        ...base,
        'from': null,
        'joins': <Object?>[],
        'columns': <Object?>[],
        'where': '',
        'sql': null,
        'function': {
          'name': m?.name ?? '',
          'args': v.function.args,
          'columns': [
            for (final c in v.function.columns)
              {
                'name': c.name,
                'type': model.typeById(c.typeId)?.expand(_db,
                        length: c.length, precision: c.precision, scale: c.scale) ??
                    '',
                'typeCategory': _category(c.typeId),
              }
          ],
        },
      };
    }
    if (v.viewType == ViewType.sql) {
      return {
        ...base,
        'from': null,
        'joins': <Object?>[],
        'columns': <Object?>[],
        'where': '',
        'function': null,
        'sql': v.sql.sql,
      };
    }
    final j = v.join;
    TableEntity? tableOf(String alias) {
      final s = j.sources.where((x) => x.alias == alias).firstOrNull;
      return s == null ? null : model.tableById(s.entityId);
    }

    String colName(String alias, int id) {
      final t = tableOf(alias);
      return t == null ? '' : (model.findExpandedColumn(t, id)?.column.physicalName ?? '');
    }

    final first = j.sources.first;
    return {
      ...base,
      'from': {
        'table': model.tableById(first.entityId)?.physicalName ?? '',
        'schema': _schemaOfId(first.entityId),
        'alias': first.alias
      },
      'joins': [
        for (final s in j.sources.skip(1))
          {
            'type': s.joinType.wire,
            'table': model.tableById(s.entityId)?.physicalName ?? '',
            'schema': _schemaOfId(s.entityId),
            'alias': s.alias,
            'on': [
              for (final o in s.on)
                {
                  'left': '${o.leftAlias}.${colName(o.leftAlias, o.leftColumnId)}',
                  'right': '${s.alias}.${colName(s.alias, o.rightColumnId)}',
                }
            ],
          }
      ],
      'columns': [
        for (final c in j.columns)
          {
            'expr': '${c.alias}.${colName(c.alias, c.columnId)}',
            'name': c.name.isNotEmpty ? c.name : colName(c.alias, c.columnId),
          }
      ],
      'where': j.where,
      'function': null,
      'sql': null,
    };
  }

  String _schemaOfId(int entityId) {
    final e = model.entityById(entityId);
    return e == null ? '' : model.schemaOf(e);
  }
}
