import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../common/common.dart';
import '../model/model.dart' hide Orientation;
import 'geometry.dart';

/// 文字描画のキャッシュ(レイアウト済みのTextPainterを再利用して性能を確保する。2-15)。
class TextCache {
  final Map<String, TextPainter> _map = {};

  TextPainter get(String text, double size, Color color,
      {String? family, FontWeight? weight, FontStyle? style, double? maxWidth}) {
    final key = '$size|${color.toARGB32()}|$family|${weight?.value}|${style?.index}|$maxWidth|$text';
    final hit = _map[key];
    if (hit != null) return hit;
    if (_map.length > 6000) _map.clear();
    final tp = TextPainter(
      text: TextSpan(
          text: text,
          style: TextStyle(
              fontSize: size, color: color, fontFamily: family, fontWeight: weight, fontStyle: style)),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth ?? double.infinity);
    return _map[key] = tp;
  }

  /// アイコン(フォントのグリフ)用。レイアウト済みのものを再利用する。
  TextPainter glyph(IconData icon, double size, Color color) {
    final key = 'glyph|${icon.fontFamily}|${icon.codePoint}|$size|${color.toARGB32()}';
    final hit = _map[key];
    if (hit != null) return hit;
    final tp = TextPainter(
      text: TextSpan(
          text: String.fromCharCode(icon.codePoint),
          style: TextStyle(fontFamily: icon.fontFamily, fontSize: size, color: color)),
      textDirection: TextDirection.ltr,
    )..layout();
    return _map[key] = tp;
  }

  void clear() => _map.clear();
}

/// エンティティ1つ分の描画結果(Picture)のキャッシュ(バッファリング。2-15)。
/// モデル・表示設定・テーマが変わると [validate] で破棄する。ドラッグ中は、同じPictureを位置だけ変えて描く。
class EntityPictureCache {
  final Map<(int, bool), ui.Picture> _pictures = {};
  Object? _key;

  /// [key] が前回と違うときは、保持している描画結果をすべて破棄する。
  void validate(Object key) {
    if (_key == key) return;
    clear();
    _key = key;
  }

  ui.Picture? get(int entityId, bool collapsed) => _pictures[(entityId, collapsed)];

  void put(int entityId, bool collapsed, ui.Picture p) {
    if (_pictures.length > 800) clear();
    _pictures[(entityId, collapsed)] = p;
  }

  int get length => _pictures.length;

  void clear() {
    for (final p in _pictures.values) {
      p.dispose();
    }
    _pictures.clear();
  }
}

/// 列のドラッグ中の表示(リレーションシップ構築。モデル座標)。
class ColumnDragVisual {
  const ColumnDragVisual({
    required this.from,
    required this.pointer,
    required this.label,
    this.targetRect,
  });

  /// ドラッグ元の列行の矩形。
  final Rect from;
  final Offset pointer;
  final String label;

  /// ドロップ先として強調する矩形(列行またはエンティティ)。
  final Rect? targetRect;
}

/// ダイアグラムの描画。画面表示と画像/PDF出力で同じPainterを使う(2-11)。
class DiagramPainter extends CustomPainter {
  DiagramPainter({
    required this.model,
    required this.diagram,
    required this.layouter,
    required this.colors,
    required this.textCache,
    this.selection = const {},
    this.positionOverride = const {},
    this.marquee,
    this.columnDrag,
    this.scale = 1.0,
    this.offset = Offset.zero,
    this.forExport = false,
    this.fontFamily,
    this.clipRect,
    this.highlights = SearchHighlights.none,
    this.pictureCache,
    this.cacheKey,
    super.repaint,
  });

  /// エンティティの描画結果のキャッシュ(画面表示のみ。画像出力では使わない)。[cacheKey] が変わると破棄する。
  final EntityPictureCache? pictureCache;
  final Object? cacheKey;

  /// これより小さい倍率では、列行を省略して見出しだけを描く(読めない大きさの文字を描かない)。
  static const double detailScale = 0.4;

  /// 検索のヒット(3.9)。画像出力には含めない。
  final SearchHighlights highlights;

  final ErModel model;
  final Diagram diagram;
  final EntityLayouter layouter;
  final CanvasColors colors;
  final TextCache textCache;
  final Set<int> selection;

  /// ドラッグ中の位置(entityId -> 左上のモデル座標)。
  final Map<int, Offset> positionOverride;

  /// 矩形選択(モデル座標)。
  final Rect? marquee;

  final ColumnDragVisual? columnDrag;

  /// モデル座標→画面座標の倍率。
  final double scale;

  /// 画面に表示するモデル座標の左上。
  final Offset offset;

  /// 画像出力(選択の強調とページ境界線を含めない。9.8-8)。
  final bool forExport;
  final String? fontFamily;

  /// 描画範囲(モデル座標)。外のエンティティは省略する。nullなら全部。
  final Rect? clipRect;

  Rect rectOf(Placement p) {
    final o = positionOverride[p.entityId];
    final b = layouter.boxOf(p);
    return Rect.fromLTWH(o?.dx ?? b.left, o?.dy ?? b.top, b.width, b.height);
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.scale(scale);
    canvas.translate(-offset.dx, -offset.dy);

    final view = clipRect ??
        Rect.fromLTWH(offset.dx, offset.dy, size.width / scale, size.height / scale);

    if (!forExport) _paintBackground(canvas, view);
    if (!forExport) _paintPages(canvas);

    final rects = <int, Rect>{};
    for (final p in diagram.placements) {
      rects[p.entityId] = rectOf(p);
    }
    _paintRelationships(canvas, rects, view);
    for (final p in diagram.placements) {
      final r = rects[p.entityId]!;
      if (!r.overlaps(view.inflate(4))) continue;
      final e = model.entityById(p.entityId);
      if (e == null) continue;
      // ドラッグ中のエンティティは半透明で、ポインタの位置に表示する(ドラッグ元には何も描かない)。
      final dragging = positionOverride.containsKey(e.id) && !forExport;
      if (dragging) canvas.saveLayer(r.inflate(6), Paint()..color = const Color(0x99FFFFFF));
      _drawEntity(canvas, e, r, p.collapsed, selection.contains(e.id) && !forExport);
      if (!forExport) _paintHighlight(canvas, e, r, p.collapsed);
      if (dragging) canvas.restore();
    }
    final cd = columnDrag;
    if (!forExport && cd != null) _paintColumnDrag(canvas, cd);
    if (!forExport && marquee != null) {
      final paint = Paint()..color = colors.selection.withValues(alpha: 0.12);
      canvas.drawRect(marquee!, paint);
      canvas.drawRect(
          marquee!,
          Paint()
            ..color = colors.selection
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1 / scale);
    }
    canvas.restore();
  }

  /// リレーションシップ構築中の列の画像、元の列からの線、ドロップ先の強調。
  void _paintColumnDrag(Canvas canvas, ColumnDragVisual d) {
    final line = Paint()
      ..color = colors.selection
      ..strokeWidth = 2 / scale
      ..style = PaintingStyle.stroke;
    canvas.drawRect(d.from, line);
    canvas.drawLine(d.from.centerRight, d.pointer, line);
    if (d.targetRect != null) {
      canvas.drawRect(d.targetRect!.inflate(1), line..strokeWidth = 3 / scale);
    }
    final fs = layouter.options.fontSize;
    final tp = textCache.get(d.label, fs, colors.text, family: fontFamily);
    final chip = Rect.fromLTWH(d.pointer.dx + 8, d.pointer.dy + 8, tp.width + 16, tp.height + 8);
    canvas.saveLayer(chip.inflate(4), Paint()..color = const Color(0xCCFFFFFF));
    canvas.drawRRect(RRect.fromRectAndRadius(chip, const Radius.circular(4)),
        Paint()..color = colors.tableBackground);
    canvas.drawRRect(RRect.fromRectAndRadius(chip, const Radius.circular(4)),
        Paint()
          ..color = colors.selection
          ..style = PaintingStyle.stroke);
    tp.paint(canvas, chip.topLeft + const Offset(8, 4));
    canvas.restore();
  }

  void _paintBackground(Canvas canvas, Rect view) {
    canvas.drawRect(view.inflate(1000), Paint()..color = colors.background);
    // 用紙のグリッド領域を、背景よりわずかに明るく描く
    canvas.drawRect(
        Rect.fromLTWH(0, 0, diagram.gridWidth, diagram.gridHeight),
        Paint()..color = colors.tableBackground.withValues(alpha: 0.35));
  }

  void _paintPages(Canvas canvas) {
    final paint = Paint()
      ..color = colors.pageBorder
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1 / scale;
    final w = diagram.pageWidth, h = diagram.pageHeight;
    void dashed(Offset a, Offset b) {
      const dash = 8.0, gap = 6.0;
      final len = (b - a).distance;
      final dir = (b - a) / len;
      for (var d = 0.0; d < len; d += dash + gap) {
        canvas.drawLine(a + dir * d, a + dir * math.min(d + dash, len), paint);
      }
    }

    for (var c = 0; c <= diagram.pageCols; c++) {
      dashed(Offset(c * w, 0), Offset(c * w, diagram.gridHeight));
    }
    for (var r = 0; r <= diagram.pageRows; r++) {
      dashed(Offset(0, r * h), Offset(diagram.gridWidth, r * h));
    }
  }

  // ---- リレーションシップ(IE記法。7-2) ----

  void _paintRelationships(Canvas canvas, Map<int, Rect> rects, Rect view) {
    final segs = relationshipSegments(model, diagram, (id) => rects[id], layouter.headerHeight);
    for (final s in segs) {
      final bounds = Rect.fromPoints(s.from, s.to).inflate(120);
      if (!bounds.overlaps(view)) continue;
      final selected = selection.contains(s.relationship.id) && !forExport;
      final paint = Paint()
        ..color = selected ? colors.selection : colors.relationshipLine
        ..style = PaintingStyle.stroke
        ..strokeWidth = (selected ? 2.0 : 1.2);
      final route = s.route;
      if (route != null) {
        for (var i = 1; i < route.length; i++) {
          canvas.drawLine(route[i - 1], route[i], paint);
        }
      } else {
        canvas.drawLine(s.from, s.to, paint);
      }
      final r = s.relationship;
      // 親側 / 子側の記号
      final parentEnd = s.fromIsParent ? s.from : s.to;
      final parentDir = route != null
          ? route[1] - route[0]
          : (s.fromIsParent ? (s.to - s.from) : (s.from - s.to));
      final childEnd = s.fromIsParent ? s.to : s.from;
      final childDir = route != null
          ? route[route.length - 2] - route.last
          : (s.fromIsParent ? (s.from - s.to) : (s.to - s.from));
      if (s.bothPlaced || s.fromIsParent) {
        _parentSymbol(canvas, paint, parentEnd, parentDir, r.dependency);
      }
      if (s.bothPlaced || !s.fromIsParent) {
        _childSymbol(canvas, paint, childEnd, childDir, r.childMultiplicity == Multiplicity.many);
      }
      if (!s.bothPlaced && s.label != null) {
        final tp = textCache.get(s.label!, model2Size(1.0), colors.text, family: fontFamily);
        tp.paint(canvas, Offset(s.to.dx + 4, s.to.dy - tp.height / 2));
      }
      if (r.locked) _lockIcon(canvas, s.mid);
    }
  }

  double model2Size(double scale) => layouter.options.fontSize * scale;

  Offset _unit(Offset d) => d == Offset.zero ? const Offset(1, 0) : d / d.distance;

  /// 親側: `|`(必須)または `o|`(任意)。[dir] は端点から線の内側へ向かう向き。
  void _parentSymbol(Canvas canvas, Paint paint, Offset end, Offset dir, bool required) {
    final u = _unit(dir);
    final n = Offset(-u.dy, u.dx);
    void bar(double at) =>
        canvas.drawLine(end + u * at + n * 6, end + u * at - n * 6, paint);
    bar(8);
    if (!required) {
      final fill = Paint()..color = colors.tableBackground;
      canvas.drawCircle(end + u * 15, 4, fill);
      canvas.drawCircle(end + u * 15, 4, paint);
    }
  }

  /// 子側: 1なら `|`、多なら `o<`(丸+カラスの足)。
  void _childSymbol(Canvas canvas, Paint paint, Offset end, Offset dir, bool many) {
    final u = _unit(dir);
    final n = Offset(-u.dy, u.dx);
    if (!many) {
      canvas.drawLine(end + u * 8 + n * 6, end + u * 8 - n * 6, paint);
      return;
    }
    final base = end + u * 12;
    canvas.drawLine(base, end + n * 6, paint);
    canvas.drawLine(base, end - n * 6, paint);
    canvas.drawLine(base, end, paint);
    final fill = Paint()..color = colors.tableBackground;
    canvas.drawCircle(end + u * 17, 4, fill);
    canvas.drawCircle(end + u * 17, 4, paint);
  }

  void _lockIcon(Canvas canvas, Offset at) {
    final tp = textCache.glyph(Icons.lock, 12, colors.relationshipLine);
    canvas.drawRect(Rect.fromCenter(center: at, width: 16, height: 16),
        Paint()..color = colors.background);
    tp.paint(canvas, at - Offset(tp.width / 2, tp.height / 2));
  }

  // ---- エンティティ(6.1-3〜6.1-8、6.6-10) ----

  static const double collapseButtonWidth = 18;

  /// エンティティを描く。画面表示ではキャッシュしたPictureを位置だけ変えて再生する。
  void _drawEntity(Canvas canvas, Entity e, Rect r, bool collapsed, bool selected) {
    final lod = !forExport && scale < detailScale;
    final cache = pictureCache;
    if (forExport || cache == null || lod) {
      _paintEntity(canvas, e, r, collapsed, selected, simple: lod);
      return;
    }
    cache.validate(cacheKey ?? 0);
    var pic = cache.get(e.id, collapsed);
    if (pic == null) {
      final rec = ui.PictureRecorder();
      _paintEntity(ui.Canvas(rec), e, Rect.fromLTWH(0, 0, r.width, r.height), collapsed, false);
      pic = rec.endRecording();
      cache.put(e.id, collapsed, pic);
    }
    canvas.save();
    canvas.translate(r.left, r.top);
    canvas.drawPicture(pic);
    canvas.restore();
    if (selected) {
      canvas.drawRect(
          r,
          Paint()
            ..color = colors.selection
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.5);
    }
  }

  void _paintEntity(Canvas canvas, Entity e, Rect r, bool collapsed, bool selected, {bool simple = false}) {
    final o = layouter.options;
    final isView = e is ViewEntity;
    final fs = o.fontSize;
    canvas.drawRect(r, Paint()..color = colors.tableBackground);

    final headerH = layouter.headerHeight;
    final headerRect = Rect.fromLTWH(r.left, r.top, r.width, headerH);
    canvas.drawRect(headerRect, Paint()..color = isView ? colors.viewHeader : colors.tableHeader);
    final title = layouter.headerText(e);
    final tp = textCache.get(title, fs * o.headerScale, colors.headerText,
        family: fontFamily, weight: FontWeight.bold, maxWidth: r.width - 16 - collapseButtonWidth - (e.locked ? 16 : 0));
    tp.paint(canvas, Offset(r.left + 8, r.top + (headerH - tp.height) / 2));
    // 折りたたみボタン(▼/▶)
    final btn = textCache.get(collapsed ? '▶' : '▼', fs, colors.headerText, family: fontFamily);
    btn.paint(canvas, Offset(r.right - collapseButtonWidth + 2, r.top + (headerH - btn.height) / 2));
    if (e.locked) {
      final lock = textCache.glyph(Icons.lock, fs, colors.headerText);
      lock.paint(canvas, Offset(r.right - collapseButtonWidth - 16, r.top + (headerH - lock.height) / 2));
    }

    if (!collapsed && !simple) {
      final rows = layouter.rowsOf(e);
      final widths = layouter.widthsOf(e);
      final rh = layouter.rowHeight;
      var y = r.top + headerH;
      for (final row in rows) {
        if (row.isForeignKey && !isView) {
          canvas.drawRect(Rect.fromLTWH(r.left, y, r.width, rh), Paint()..color = colors.foreignKeyBackground);
        }
        final dim = row.isCommon;
        final textColor = dim ? colors.supplementText : colors.text;
        final style = dim ? FontStyle.italic : FontStyle.normal;
        var x = r.left + EntityLayouter.hPad;
        if (!isView) {
          if (row.pk) _glyph(canvas, Icons.vpn_key, Offset(x, y + rh / 2), fs, colors.text);
          x += EntityLayouter.iconWidth;
          if (row.notNull) {
            final dot = textCache.get('●', fs * 0.7, textColor, family: fontFamily);
            dot.paint(canvas, Offset(x, y + (rh - dot.height) / 2));
          }
          x += EntityLayouter.iconWidth;
        }
        final items = [
          (o.colLogical, row.texts.logical, widths[0], o.normalScale),
          (o.colPhysical, row.texts.physical, widths[1], o.normalScale),
          (o.colType, row.texts.type, widths[2], o.normalScale),
          (o.colDefault, row.texts.defaultText, widths[3], o.supplementScale),
          (o.colComment, row.texts.comment, widths[4], o.supplementScale),
        ];
        final rightLimit = r.right - EntityLayouter.hPad - (isView ? 0 : EntityLayouter.iconWidth);
        for (final it in items) {
          if (!it.$1) continue;
          if (it.$2.isNotEmpty && x < rightLimit) {
            final t = textCache.get(it.$2, fs * it.$4,
                it.$4 < 1.0 ? colors.supplementText : textColor,
                family: fontFamily, style: style, maxWidth: math.max(10, rightLimit - x));
            t.paint(canvas, Offset(x, y + (rh - t.height) / 2));
          }
          x += it.$3 + EntityLayouter.itemGap;
        }
        if (!isView && row.hasDefault) {
          _glyph(canvas, Icons.bolt, Offset(r.right - EntityLayouter.hPad - 7, y + rh / 2), fs, colors.supplementText);
        }
        y += rh;
      }
    }

    canvas.drawRect(
        r,
        Paint()
          ..color = selected ? colors.selection : colors.pageBorder
          ..style = PaintingStyle.stroke
          ..strokeWidth = selected ? 2.5 : 1);
  }

  static const Color _hlLight = Color(0x33FFC107);
  static const Color _hlStrong = Color(0x99FF9800);

  /// 検索のヒット(3.9): 親は薄く、子(列行、ヘッダ)は濃く重ねる。
  void _paintHighlight(Canvas canvas, Entity e, Rect r, bool collapsed) {
    if (highlights.isEmpty) return;
    final headerH = layouter.headerHeight;
    if (highlights.light.contains(e.id)) canvas.drawRect(r, Paint()..color = _hlLight);
    if (highlights.strongHeaders.contains(e.id)) {
      canvas.drawRect(Rect.fromLTWH(r.left, r.top, r.width, headerH), Paint()..color = _hlStrong);
    }
    final rows = highlights.strongRows[e.id];
    if (rows != null && !collapsed) {
      final rh = layouter.rowHeight;
      for (final i in rows) {
        canvas.drawRect(Rect.fromLTWH(r.left, r.top + headerH + i * rh, r.width, rh), Paint()..color = _hlStrong);
      }
    }
    if (highlights.light.contains(e.id) || highlights.strongHeaders.contains(e.id)) {
      canvas.drawRect(
          r,
          Paint()
            ..color = const Color(0xFFFF9800)
            ..style = PaintingStyle.stroke
            ..strokeWidth = highlights.strongHeaders.contains(e.id) || rows != null ? 2 : 1);
    }
  }

  void _glyph(Canvas canvas, IconData icon, Offset center, double size, Color color) {
    final tp = textCache.glyph(icon, size, color);
    tp.paint(canvas, Offset(center.dx, center.dy - tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant DiagramPainter old) => true;
}
