import 'dart:convert';

import '../model/model.dart';
import '../persistence/persistence.dart';
import 'command_base.dart';

/// コピー対象(4.2-13)。アプリ内メモリに保持する。選択エンティティと、それらを結ぶリレーションシップ。
class ClipboardData {
  ClipboardData(this.entities, this.relationships, this.positions);

  final List<Map<String, Object?>> entities;
  final List<Map<String, Object?>> relationships;

  /// entityId -> [x, y](コピー時の現在のダイアグラム上の位置)
  final Map<int, List<double>> positions;

  bool get isEmpty => entities.isEmpty;

  factory ClipboardData.fromSelection(ErModel m, Diagram d, Iterable<int> entityIds) {
    final ids = entityIds.toSet();
    final ents = <Map<String, Object?>>[];
    final pos = <int, List<double>>{};
    for (final e in m.entities) {
      if (!ids.contains(e.id)) continue;
      ents.add(PeroEncoder.entityToMap(e));
      final p = d.placementOf(e.id);
      pos[e.id] = [p?.x ?? 0, p?.y ?? 0];
    }
    final rels = [
      for (final r in m.relationships)
        if (ids.contains(r.parentId) && ids.contains(r.childId))
          PeroEncoder.relationshipToMap(r)
    ];
    return ClipboardData(ents, rels, pos);
  }

  Map<String, Object?> toJson() => {
        'entities': entities,
        'relationships': relationships,
        'positions': {for (final e in positions.entries) '${e.key}': e.value},
      };

  factory ClipboardData.fromJson(Map<String, Object?> j) => ClipboardData(
        [for (final e in j['entities'] as List) Map<String, Object?>.from(e as Map)],
        [for (final e in j['relationships'] as List) Map<String, Object?>.from(e as Map)],
        {
          for (final e in (j['positions'] as Map).entries)
            int.parse(e.key as String): [
              for (final v in e.value as List) (v as num).toDouble()
            ]
        },
      );
}

/// 貼り付け(4.2-13)。複製はコピーと貼り付けを続けて行う。
class PasteEntitiesCommand extends ModelCommand {
  PasteEntitiesCommand({
    required this.diagramId,
    required this.data,
    this.dx = 20,
    this.dy = 20,
    this.pasteCount = 1,
  });
  final int diagramId;
  final ClipboardData data;
  final double dx;
  final double dy;

  /// 同じクリップボードを何回目に貼るか。位置のずらしを累積する。
  final int pasteCount;

  /// 実行後に設定される、貼り付けたエンティティのID。
  final List<int> createdIds = [];

  @override
  String get type => 'pasteEntities';
  @override
  Map<String, Object?> argsToJson() =>
      {'diagramId': diagramId, 'data': data.toJson(), 'dx': dx, 'dy': dy, 'pasteCount': pasteCount};

  String _uniqueName(String base, Set<String> used) {
    if (!used.contains(base.toLowerCase())) return base;
    var n = 2;
    while (used.contains('$base$n'.toLowerCase())) {
      n++;
    }
    return '$base$n';
  }

  @override
  void apply(CommandContext ctx) {
    final m = ctx.model;
    final d = m.diagramById(diagramId);
    if (d == null) throw CommandException('ダイアグラムが存在しません');
    createdIds.clear();

    final entityMap = <int, int>{};
    final columnMap = <int, int>{};
    int remap(Map<int, int> map, Object? old) {
      final o = old as int;
      return map.putIfAbsent(o, () => m.allocateId());
    }

    // 制約名・エンティティ名の重複を避けるため、使用済みの名前を集める。
    final usedEntityNames = m.entities.map((e) => e.physicalName.toLowerCase()).toSet();
    final usedConstraintNames = <String>{
      for (final t in m.tables) ...[
        for (final c in t.indexes) m.indexName(t, c).toLowerCase(),
        for (final c in t.uniques) m.uniqueName(t, c).toLowerCase(),
        for (final g in t.triggers) m.triggerName(t, g).toLowerCase(),
      ],
      for (final r in m.relationships) m.foreignKeyName(r).toLowerCase(),
    };

    String copyConstraintName(String name) {
      final n = _uniqueName('${name}_copy', usedConstraintNames);
      usedConstraintNames.add(n.toLowerCase());
      return n;
    }

    // 先にエンティティIDを割り当てる(ビューのソース参照の付替えに使う)。
    for (final e in data.entities) {
      remap(entityMap, e['id']);
    }
    // 列のIDも先に割り当てる。
    for (final e in data.entities) {
      for (final c in (e['columns'] as List? ?? const [])) {
        remap(columnMap, (c as Map)['id']);
      }
    }

    final newEntities = <Entity>[];
    for (final src in data.entities) {
      final em = _deepCopy(src);
      final oldId = em['id'] as int;
      em['id'] = entityMap[oldId];
      em['locked'] = false;
      final phys = _uniqueName('${em['physicalName']}_copy', usedEntityNames);
      usedEntityNames.add(phys.toLowerCase());
      em['physicalName'] = phys;
      em['logicalName'] = '${em['logicalName']}のコピー';
      if (em['kind'] == 'table') {
        for (final c in (em['columns'] as List)) {
          (c as Map)['id'] = columnMap[c['id']];
        }
        for (final key in ['indexes', 'uniques']) {
          for (final c in (em[key] as List)) {
            final cm = c as Map;
            cm['id'] = m.allocateId();
            cm['columnIds'] = [for (final i in (cm['columnIds'] as List)) columnMap[i] ?? i];
            if (cm['nameMode'] == 'manual') cm['name'] = copyConstraintName('${cm['name']}');
          }
        }
        for (final g in (em['triggers'] as List)) {
          final gm = g as Map;
          gm['id'] = m.allocateId();
          if (gm['nameMode'] == 'manual') gm['name'] = copyConstraintName('${gm['name']}');
        }
      } else {
        final join = em['join'] as Map;
        for (final s in (join['sources'] as List)) {
          final sm = s as Map;
          sm['entityId'] = entityMap[sm['entityId']] ?? sm['entityId'];
          for (final o in (sm['on'] as List)) {
            final om = o as Map;
            om['leftColumnId'] = columnMap[om['leftColumnId']] ?? om['leftColumnId'];
            om['rightColumnId'] = columnMap[om['rightColumnId']] ?? om['rightColumnId'];
          }
        }
        for (final c in (join['columns'] as List)) {
          final cm = c as Map;
          cm['columnId'] = columnMap[cm['columnId']] ?? cm['columnId'];
        }
      }
      final e = PeroDecoder.entityFromMap(em);
      if (e == null) throw CommandException('貼り付けるデータが不正です');
      newEntities.add(e);
    }
    for (final e in newEntities) {
      m.entities.add(e);
      createdIds.add(e.id);
      final pos = data.positions[_oldIdOf(entityMap, e.id)] ?? [0, 0];
      d.placements.add(Placement(
          entityId: e.id, x: pos[0] + dx * pasteCount, y: pos[1] + dy * pasteCount));
    }
    for (final src in data.relationships) {
      final rm = _deepCopy(src);
      rm['id'] = m.allocateId();
      rm['locked'] = false;
      rm['parentId'] = entityMap[rm['parentId']];
      rm['childId'] = entityMap[rm['childId']];
      for (final p in (rm['columnPairs'] as List)) {
        final pm = p as Map;
        pm['parentColumnId'] = columnMap[pm['parentColumnId']] ?? pm['parentColumnId'];
        pm['childColumnId'] = columnMap[pm['childColumnId']] ?? pm['childColumnId'];
      }
      if (rm['nameMode'] == 'manual') rm['name'] = copyConstraintName('${rm['name']}');
      m.relationships.add(Relationship(
        id: rm['id'] as int,
        parentId: rm['parentId'] as int,
        childId: rm['childId'] as int,
        columnPairs: [
          for (final p in (rm['columnPairs'] as List))
            ColumnPair(
                parentColumnId: (p as Map)['parentColumnId'] as int,
                childColumnId: p['childColumnId'] as int)
        ],
        dependency: rm['dependency'] as bool? ?? true,
        childMultiplicity:
            enumFromWire(Multiplicity.values, rm['childMultiplicity']) ?? Multiplicity.many,
        nameMode: enumFromWire(NameMode.values, rm['nameMode']) ?? NameMode.auto,
        name: rm['name'] as String? ?? '',
        onDelete: enumFromWire(RefAction.values, rm['onDelete']) ?? RefAction.noAction,
        onUpdate: enumFromWire(RefAction.values, rm['onUpdate']) ?? RefAction.noAction,
      ));
    }
    ctx.recalcPages(d);
  }

  int _oldIdOf(Map<int, int> map, int newId) =>
      map.entries.firstWhere((e) => e.value == newId).key;

  static Map<String, Object?> _deepCopy(Map<String, Object?> m) =>
      Map<String, Object?>.from(
          (jsonDecode(PeroEncoder.encodeCompact(m))) as Map<String, Object?>);
}
