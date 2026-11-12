import 'enums.dart';

/// ダイアグラム内でのエンティティ配置(位置と折りたたみ状態)。
class Placement {
  Placement({required this.entityId, this.x = 0, this.y = 0, this.collapsed = false});
  final int entityId;
  double x;
  double y;
  bool collapsed;
  Placement copy() => Placement(entityId: entityId, x: x, y: y, collapsed: collapsed);
}

class DiagramView {
  DiagramView({this.zoom = 1.0, this.scrollX = 0, this.scrollY = 0});
  double zoom;
  double scrollX;
  double scrollY;
  DiagramView copy() => DiagramView(zoom: zoom, scrollX: scrollX, scrollY: scrollY);
}

/// 論理px(96dpi)での矩形。
class Box {
  const Box(this.left, this.top, this.width, this.height);
  final double left;
  final double top;
  final double width;
  final double height;
  double get right => left + width;
  double get bottom => top + height;
  bool overlaps(Box o) =>
      left < o.right && o.left < right && top < o.bottom && o.top < bottom;
  bool contains(double px, double py) => px >= left && px <= right && py >= top && py <= bottom;
  Box shifted(double dx, double dy) => Box(left + dx, top + dy, width, height);
}

/// 用紙サイズ(5.2-2)。縦の(幅, 高さ)。
const Map<PageSize, (int, int)> _portrait = {
  PageSize.a0: (3179, 4494),
  PageSize.a1: (2245, 3179),
  PageSize.a2: (1587, 2245),
  PageSize.a3: (1123, 1587),
  PageSize.a4: (794, 1123),
};

(double, double) pageDimensions(PageSize size, Orientation o) {
  final (w, h) = _portrait[size]!;
  return o == Orientation.portrait ? (w.toDouble(), h.toDouble()) : (h.toDouble(), w.toDouble());
}

/// ダイアグラム(5.2)。
class Diagram {
  Diagram({
    required this.id,
    required this.name,
    this.pageSize = PageSize.a3,
    this.orientation = Orientation.landscape,
    this.pageRows = 1,
    this.pageCols = 1,
    List<Placement>? placements,
    DiagramView? view,
  })  : placements = placements ?? [],
        view = view ?? DiagramView();

  final int id;
  String name;
  PageSize pageSize;
  Orientation orientation;
  int pageRows;
  int pageCols;
  List<Placement> placements;
  DiagramView view;

  double get pageWidth => pageDimensions(pageSize, orientation).$1;
  double get pageHeight => pageDimensions(pageSize, orientation).$2;
  double get gridWidth => pageWidth * pageCols;
  double get gridHeight => pageHeight * pageRows;

  Placement? placementOf(int entityId) {
    for (final p in placements) {
      if (p.entityId == entityId) return p;
    }
    return null;
  }

  /// 用紙ページの増減(5.2-4)。ドロップ時に評価する。
  /// [sizeOf] は配置の矩形寸法(幅, 高さ)を返す。
  void recalcPages((double, double) Function(Placement) sizeOf) {
    final pw = pageWidth;
    final ph = pageHeight;
    Box rect(Placement p) {
      final (w, h) = sizeOf(p);
      return Box(p.x, p.y, w, h);
    }

    void shiftAll(double dx, double dy) {
      if (dx == 0 && dy == 0) return;
      for (final p in placements) {
        p.x += dx;
        p.y += dy;
      }
    }

    // 追加
    if (placements.isNotEmpty) {
      final rects = placements.map(rect).toList();
      var minX = rects.first.left, minY = rects.first.top;
      var maxX = rects.first.right, maxY = rects.first.bottom;
      for (final r in rects) {
        if (r.left < minX) minX = r.left;
        if (r.top < minY) minY = r.top;
        if (r.right > maxX) maxX = r.right;
        if (r.bottom > maxY) maxY = r.bottom;
      }
      if (minX < 0) {
        final n = (-minX / pw).ceil();
        pageCols += n;
        shiftAll(n * pw, 0);
        maxX += n * pw;
      }
      if (minY < 0) {
        final n = (-minY / ph).ceil();
        pageRows += n;
        shiftAll(0, n * ph);
        maxY += n * ph;
      }
      if (maxX > pageCols * pw) pageCols = (maxX / pw).ceil();
      if (maxY > pageRows * ph) pageRows = (maxY / ph).ceil();
    }

    // 削除(端の行/列に1つも重ならなければ)
    bool colHit(double x0, double x1) =>
        placements.any((p) {
          final r = rect(p);
          return r.right > x0 && r.left < x1;
        });
    bool rowHit(double y0, double y1) =>
        placements.any((p) {
          final r = rect(p);
          return r.bottom > y0 && r.top < y1;
        });
    while (pageCols > 1 && !colHit(0, pw)) {
      pageCols--;
      shiftAll(-pw, 0);
    }
    while (pageCols > 1 && !colHit((pageCols - 1) * pw, pageCols * pw)) {
      pageCols--;
    }
    while (pageRows > 1 && !rowHit(0, ph)) {
      pageRows--;
      shiftAll(0, -ph);
    }
    while (pageRows > 1 && !rowHit((pageRows - 1) * ph, pageRows * ph)) {
      pageRows--;
    }
    if (pageCols < 1) pageCols = 1;
    if (pageRows < 1) pageRows = 1;
  }

  Diagram copy() => Diagram(
        id: id,
        name: name,
        pageSize: pageSize,
        orientation: orientation,
        pageRows: pageRows,
        pageCols: pageCols,
        placements: placements.map((p) => p.copy()).toList(),
        view: view.copy(),
      );
}
