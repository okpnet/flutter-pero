import '../model/model.dart';

/// 自動配置(9.9)。層に分け、用紙ページ幅で折り返しながら左から右へ並べる。
/// 戻り値は entityId -> [x, y]。ロック中のエンティティは含めない(障害物として扱う)。
Map<int, List<double>> computeAutoLayout(
  ErModel model,
  Diagram diagram,
  EntityLayouter layouter, {
  Set<int> selected = const {},
  double spacing = 40,
  double margin = 40,
}) {
  final placed = diagram.placements;
  final useSel = selected.any((id) => placed.any((p) => p.entityId == id));
  final targets = [
    for (final p in placed)
      if (!useSel || selected.contains(p.entityId)) p
  ];
  final movable = [for (final p in targets) if (!(model.entityById(p.entityId)?.locked ?? false)) p];
  final movableIds = movable.map((p) => p.entityId).toSet();
  final obstacles = [
    for (final p in placed)
      if (!movableIds.contains(p.entityId)) layouter.boxOf(p)
  ];

  // 層(親から子)。循環は切って進む。
  final layer = <int, int>{};
  final visiting = <int>{};
  int layerOf(int id) {
    final known = layer[id];
    if (known != null) return known;
    if (!visiting.add(id)) return 0;
    var l = 0;
    for (final r in model.relationships) {
      if (r.childId == id && movableIds.contains(r.parentId) && r.parentId != id) {
        final pl = layerOf(r.parentId) + 1;
        if (pl > l) l = pl;
      }
    }
    visiting.remove(id);
    return layer[id] = l;
  }

  for (final p in movable) {
    layerOf(p.entityId);
  }
  final layers = <int, List<Placement>>{};
  for (final p in movable) {
    layers.putIfAbsent(layer[p.entityId]!, () => []).add(p);
  }
  String nameOf(Placement p) => model.entityById(p.entityId)?.physicalName.toLowerCase() ?? '';

  var originX = margin, originY = margin;
  if (useSel && movable.isNotEmpty) {
    originX = movable.map((p) => p.x).reduce((a, b) => a < b ? a : b);
    originY = movable.map((p) => p.y).reduce((a, b) => a < b ? a : b);
  }
  final wrapRight = originX + diagram.pageWidth - margin;

  final result = <int, List<double>>{};
  var y = originY;
  for (final key in (layers.keys.toList()..sort())) {
    final row = layers[key]!..sort((a, b) => nameOf(a).compareTo(nameOf(b)));
    var x = originX;
    var rowH = 0.0;
    for (final p in row) {
      final size = layouter.boxOf(p);
      if (x > originX && x + size.width > wrapRight) {
        x = originX;
        y += rowH + spacing;
        rowH = 0;
      }
      // 障害物(ロック中)と重ならない位置まで右へずらす。
      var moved = true;
      while (moved) {
        moved = false;
        final cand = Box(x, y, size.width, size.height);
        for (final o in obstacles) {
          final inflated = Box(o.left - spacing, o.top - spacing, o.width + 2 * spacing,
              o.height + 2 * spacing);
          if (cand.overlaps(inflated)) {
            x = o.right + spacing;
            moved = true;
            break;
          }
        }
      }
      result[p.entityId] = [x, y];
      x += size.width + spacing;
      if (size.height > rowH) rowH = size.height;
    }
    y += rowH + spacing;
  }
  return result;
}
