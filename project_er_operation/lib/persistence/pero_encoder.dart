import 'dart:convert';

import '../model/model.dart';

/// 現行のフォーマットバージョン。
const int currentFormatVersion = 2;

/// `.pero` の保存形式(付録A)。スキーマを明示的に定義した実装(11.4)。
/// キーの順は付録Aのとおり。
class PeroEncoder {
  static String encode(ErModel m) =>
      '${const JsonEncoder.withIndent('  ').convert(toMap(m))}\n';

  /// 差分検出やコマンド引数用の、インデントなしJSON。
  static String encodeCompact(Object? o) => jsonEncode(o);

  static Map<String, Object?> toMap(ErModel m) => {
        'formatVersion': currentFormatVersion,
        'appVersion': m.appVersion,
        'id': m.id,
        'nextId': m.nextId,
        'properties': {
          'outputFileName': m.properties.outputFileName,
          'outputFolder': m.properties.outputFolder,
          'targetDb': m.properties.targetDb.wire,
          'postPath': m.properties.postPath,
          'startQuery': m.properties.startQuery,
          'endQuery': m.properties.endQuery,
          'schema': m.properties.schema,
          'includeSchema': m.properties.includeSchema,
        },
        'types': m.types.map(typeToMap).toList(),
        'methods': m.methods.map(methodToMap).toList(),
        'commonColumnPatterns': m.patterns.map(patternToMap).toList(),
        'entities': m.entities.map(entityToMap).toList(),
        'relationships': m.relationships.map(relationshipToMap).toList(),
        'diagrams': m.diagrams.map(diagramToMap).toList(),
        ...m.unknownKeys,
      };

  static Map<String, Object?> _perDb(Map<DbKind, String> v) =>
      {for (final d in DbKind.values) d.wire: v[d] ?? ''};

  static Map<String, Object?> typeToMap(DataType t) => {
        'id': t.id,
        'displayName': t.displayName,
        'paramKind': t.paramKind.wire,
        'defaultParams': {
          if (t.paramKind == ParamKind.length) 'length': t.defaultLength,
          if (t.paramKind == ParamKind.precisionScale) ...{
            'precision': t.defaultPrecision,
            'scale': t.defaultScale,
          },
        },
        'category': t.category.wire,
        'physical': _perDb(t.physical),
        'kind': t.kind.wire,
        'fields': [
          for (final f in t.fields)
            {
              'name': f.name,
              'typeId': f.typeId,
              'length': f.length,
              'precision': f.precision,
              'scale': f.scale,
            }
        ],
        'enumValues': t.enumValues,
      };

  static Map<String, Object?> methodToMap(MethodDef x) => {
        'id': x.id,
        'kind': x.kind.wire,
        'name': x.name,
        'external': x.external,
        'call': _perDb(x.call),
        'bodies': _perDb(x.bodies),
        'comment': x.comment,
        'args': x.args,
        'dependsOnTableIds': x.dependsOnTableIds,
      };

  static Map<String, Object?> columnToMap(ColumnDef c, {required bool withPk}) => {
        'id': c.id,
        'logicalName': c.logicalName,
        'physicalName': c.physicalName,
        'typeId': c.typeId,
        'length': c.length,
        'precision': c.precision,
        'scale': c.scale,
        if (withPk) 'pk': c.pk,
        'notNull': c.notNull,
        'defaultKind': c.defaultKind.wire,
        'defaultValue': c.defaultValue,
        'defaultMethodId': c.defaultMethodId,
        'defaultExpression': c.defaultExpression,
        'comment': c.comment,
      };

  static Map<String, Object?> patternToMap(CommonColumnPattern p) => {
        'id': p.id,
        'name': p.name,
        'enabled': p.enabled,
        'include': p.include,
        'exclude': p.exclude,
        'position': p.position.wire,
        'columns': p.columns.map((c) => columnToMap(c, withPk: false)).toList(),
      };

  static Map<String, Object?> constraintToMap(ConstraintDef c) => {
        'id': c.id,
        'nameMode': c.nameMode.wire,
        'name': c.name,
        'columnIds': c.columnIds,
        'nullsNotDistinct': c.nullsNotDistinct,
      };

  static Map<String, Object?> checkToMap(CheckDef c) =>
      {'id': c.id, 'nameMode': c.nameMode.wire, 'name': c.name, 'expression': c.expression};

  static Map<String, Object?> triggerToMap(TriggerDef g) => {
        'id': g.id,
        'source': g.source.wire,
        'methodId': g.methodId,
        'inlineBodies': _perDb(g.inlineBodies),
        'nameMode': g.nameMode.wire,
        'name': g.name,
        'timing': g.timing.wire,
        'events': g.events.map((e) => e.wire).toList(),
        'forEach': g.forEach.wire,
        'when': g.when,
        'args': g.args,
        'updateColumnIds': g.updateColumnIds,
      };

  static Map<String, Object?> entityToMap(Entity e) {
    if (e is TableEntity) {
      return {
        'id': e.id,
        'kind': 'table',
        'logicalName': e.logicalName,
        'physicalName': e.physicalName,
        'comment': e.comment,
        'locked': e.locked,
        'columns': e.columns.map((c) => columnToMap(c, withPk: true)).toList(),
        'indexes': e.indexes.map(constraintToMap).toList(),
        'uniques': e.uniques.map(constraintToMap).toList(),
        'checks': e.checks.map(checkToMap).toList(),
        'preQuery': e.preQuery,
        'postQuery': e.postQuery,
        'triggers': e.triggers.map(triggerToMap).toList(),
      };
    }
    final v = e as ViewEntity;
    return {
      'id': v.id,
      'kind': 'view',
      'logicalName': v.logicalName,
      'physicalName': v.physicalName,
      'comment': v.comment,
      'locked': v.locked,
      'viewType': v.viewType.wire,
      'join': {
        'sources': v.join.sources
            .map((s) => {
                  'alias': s.alias,
                  'entityId': s.entityId,
                  'joinType': s.joinType.wire,
                  'on': s.on
                      .map((o) => {
                            'leftAlias': o.leftAlias,
                            'leftColumnId': o.leftColumnId,
                            'rightColumnId': o.rightColumnId,
                          })
                      .toList(),
                })
            .toList(),
        'columns': v.join.columns
            .map((c) => {
                  'alias': c.alias,
                  'columnId': c.columnId,
                  'name': c.name,
                  'logicalName': c.logicalName,
                })
            .toList(),
        'where': v.join.where,
      },
      'function': {
        'methodId': v.function.methodId,
        'args': v.function.args,
        'columns': v.function.columns
            .map((c) => {
                  'name': c.name,
                  'logicalName': c.logicalName,
                  'typeId': c.typeId,
                  'length': c.length,
                  'precision': c.precision,
                  'scale': c.scale,
                })
            .toList(),
      },
      'sql': {
        'sql': v.sql.sql,
        'columns': v.sql.columns
            .map((c) => {
                  'name': c.name,
                  'logicalName': c.logicalName,
                  'typeId': c.typeId,
                  'length': c.length,
                  'precision': c.precision,
                  'scale': c.scale,
                })
            .toList(),
      },
      'preQuery': v.preQuery,
      'postQuery': v.postQuery,
    };
  }

  static Map<String, Object?> relationshipToMap(Relationship r) => {
        'id': r.id,
        'kind': 'relationship',
        'locked': r.locked,
        'parentId': r.parentId,
        'childId': r.childId,
        'columnPairs': r.columnPairs
            .map((p) =>
                {'parentColumnId': p.parentColumnId, 'childColumnId': p.childColumnId})
            .toList(),
        'dependency': r.dependency,
        'childMultiplicity': r.childMultiplicity.wire,
        'nameMode': r.nameMode.wire,
        'name': r.name,
        'onDelete': r.onDelete.wire,
        'onUpdate': r.onUpdate.wire,
        'deferrable': r.deferrable.wire,
      };

  static Map<String, Object?> diagramToMap(Diagram d) => {
        'id': d.id,
        'name': d.name,
        'pageSize': d.pageSize.wire,
        'orientation': d.orientation.wire,
        'pageRows': d.pageRows,
        'pageCols': d.pageCols,
        'placements': d.placements
            .map((p) => {'entityId': p.entityId, 'x': p.x, 'y': p.y, 'collapsed': p.collapsed})
            .toList(),
        'view': {'zoom': d.view.zoom, 'scrollX': d.view.scrollX, 'scrollY': d.view.scrollY},
        'schema': d.schema,
      };
}
