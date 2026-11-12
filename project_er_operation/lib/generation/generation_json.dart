import 'dart:convert';

import '../model/model.dart';

/// 生成用JSON(付録B)のバージョン。付録Bを変更するときに上げる。
const int postApiVersion = 1;

/// 生成用JSONを作る。生成前検証(9.5)のエラーがないモデルを前提とする。
class GenerationJsonBuilder {
  GenerationJsonBuilder(this.model);
  final ErModel model;

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
      },
      'methods': [
        for (final m in model.methods)
          {
            'id': m.id,
            'name': m.name,
            'kind': m.kind.wire,
            'external': m.external,
            'call': m.kind == MethodKind.function ? m.callExpr(_db) : '',
            'body': m.bodies[_db] ?? '',
          }
      ],
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
      'logicalName': t.logicalName,
      'physicalName': t.physicalName,
      'comment': t.comment,
      'preQuery': t.preQuery,
      'postQuery': t.postQuery,
      'columns': [for (final x in cols) _column(x)],
      'primaryKey': pk.isEmpty
          ? null
          : {'name': model.primaryKeyName(t), 'columns': pk.map((c) => c.physicalName).toList()},
      'indexes': [
        for (final c in t.indexes)
          {'name': model.indexName(t, c), 'columns': names(c.columnIds)}
      ],
      'uniques': [
        for (final c in t.uniques)
          {'name': model.uniqueName(t, c), 'columns': names(c.columnIds)}
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
      'parentTable': p.physicalName,
      'columns': [
        for (final pair in r.columnPairs)
          {
            'child': colName(c, pair.childColumnId),
            'parent': colName(p, pair.parentColumnId),
          }
      ],
      'onDelete': r.onDelete.sql,
      'onUpdate': r.onUpdate.sql,
      'deferred': deferred,
    };
  }

  Map<String, Object?> _view(ViewEntity v) {
    final base = <String, Object?>{
      'id': v.id,
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
      'from': {'table': model.tableById(first.entityId)?.physicalName ?? '', 'alias': first.alias},
      'joins': [
        for (final s in j.sources.skip(1))
          {
            'type': s.joinType.wire,
            'table': model.tableById(s.entityId)?.physicalName ?? '',
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
    };
  }
}
