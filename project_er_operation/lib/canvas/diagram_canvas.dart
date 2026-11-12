import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../command/command.dart';
import '../common/common.dart';
import '../model/model.dart' hide Orientation;
import '../session/session.dart';
import 'diagram_painter.dart';
import 'geometry.dart';

/// サイドメニューからドロップする項目(3.3)。
enum SideItem { table, joinView, functionView, sqlView }

/// キャンバスから呼び出す操作(右クリックメニューなど)。
abstract class CanvasHost {
  void onAddTableAt(Offset modelPos);
  void onAddViewAt(Offset modelPos, ViewType type);
  void onFocusEntityName(int entityId);

  /// 列のドラッグで、親(ドラッグ元)の列から子(ドロップ先)へリレーションシップを作る。
  /// [targetColumnId] はドロップ先が列のとき。
  void onConnectColumns(int sourceEntityId, int sourceColumnId, int targetEntityId, int? targetColumnId);
  Future<void> onContextMenu(Offset globalPos, Offset modelPos, int? hitId);
}

/// ダイアグラムを描画し、選択・移動・パン・ズームを受け付けるキャンバス(3.4)。
/// ヒットテストはモデル座標系で自前実装する(2-11)。
class DiagramCanvas extends StatefulWidget {
  const DiagramCanvas({super.key, required this.session, required this.host});
  final EditorSession session;
  final CanvasHost host;

  @override
  State<DiagramCanvas> createState() => DiagramCanvasState();
}

enum _Mode { none, pan, drag, marquee, column }

class DiagramCanvasState extends State<DiagramCanvas> {
  final TextCache _text = TextCache();
  final FocusNode _focus = FocusNode();


  Size _size = Size.zero;
  _Mode _mode = _Mode.none;
  Offset _panLast = Offset.zero;
  Offset _dragStartModel = Offset.zero;
  Map<int, Offset> _dragOrigins = {};
  Map<int, Offset> _override = {};
  bool _dragMoved = false;
  int? _clickedId;
  bool _clickedWasSelected = false;
  Rect? _marquee;
  int? _colEntity;
  int? _colColumn;
  Rect? _colRect;
  String _colLabel = "";
  ColumnDragVisual? _colDrag;
  Offset _marqueeStart = Offset.zero;
  DateTime _lastTap = DateTime.fromMillisecondsSinceEpoch(0);
  int? _lastTapId;

  EditorSession get s => widget.session;

  @override
  void dispose() {
    _focus.dispose();

    super.dispose();
  }

  // ---- 座標変換 ----
  Offset toModel(Offset local) {
    final v = s.diagram.view;
    return Offset(v.scrollX + local.dx / v.zoom, v.scrollY + local.dy / v.zoom);
  }

  Offset localToModelFromGlobal(Offset global) {
    final box = context.findRenderObject() as RenderBox;
    return toModel(box.globalToLocal(global));
  }

  Rect _rectOfPlacement(Placement p) {
    final o = _override[p.entityId];
    final b = s.layouter.boxOf(p);
    return Rect.fromLTWH(o?.dx ?? b.left, o?.dy ?? b.top, b.width, b.height);
  }

  /// 最前面(最後に描画される)のエンティティから順にヒットテストする。
  int? _hitEntity(Offset m) {
    final ps = s.diagram.placements;
    for (var i = ps.length - 1; i >= 0; i--) {
      if (_rectOfPlacement(ps[i]).contains(m)) return ps[i].entityId;
    }
    return null;
  }

  int? _hitRelationship(Offset m) {
    final d = s.diagram;
    final rects = {for (final p in d.placements) p.entityId: _rectOfPlacement(p)};
    final segs = relationshipSegments(s.model, d, (id) => rects[id], s.layouter.headerHeight);
    final tol = 6 / d.view.zoom;
    for (final seg in segs.reversed) {
      if (seg.distanceTo(m) <= tol) return seg.relationship.id;
    }
    return null;
  }

  /// テーブルの列行(折りたたみ中・ビューは対象外)。(列ID, 行の矩形, 表示名)。
  (int, Rect, String)? _rowAt(int entityId, Offset m) {
    final e = s.model.entityById(entityId);
    final p = s.diagram.placementOf(entityId);
    if (e is! TableEntity || p == null || p.collapsed) return null;
    final r = _rectOfPlacement(p);
    final l = s.layouter;
    final i = ((m.dy - (r.top + l.headerHeight)) / l.rowHeight).floor();
    final cols = s.model.expand(e).columns;
    if (m.dy < r.top + l.headerHeight || i < 0 || i >= cols.length) return null;
    final c = cols[i].column;
    final top = r.top + l.headerHeight + i * l.rowHeight;
    return (c.id, Rect.fromLTWH(r.left, top, r.width, l.rowHeight), '${c.physicalName}  ${s.model.typeLabel(c)}');
  }

  ColumnDragVisual? _colVisual(Offset pointer) {
    if (_colRect == null) return null;
    Rect? target;
    final hit = _hitEntity(pointer);
    if (hit != null && hit != _colEntity && s.model.entityById(hit) is TableEntity) {
      final row = _rowAt(hit, pointer);
      target = row?.$2 ?? _rectOfPlacement(s.diagram.placementOf(hit)!);
    }
    return ColumnDragVisual(from: _colRect!, pointer: pointer, label: _colLabel, targetRect: target);
  }

  /// 折りたたみボタンの領域か(ヘッダ右端)。
  bool _hitCollapse(Offset m, int entityId) {
    final p = s.diagram.placementOf(entityId);
    if (p == null) return false;
    final r = _rectOfPlacement(p);
    return m.dx >= r.right - DiagramPainter.collapseButtonWidth &&
        m.dy <= r.top + s.layouter.headerHeight;
  }

  bool get _ctrl =>
      HardwareKeyboard.instance.isControlPressed || HardwareKeyboard.instance.isMetaPressed;
  bool get _shift => HardwareKeyboard.instance.isShiftPressed;
  bool get _alt => HardwareKeyboard.instance.isAltPressed;
  bool get _space => HardwareKeyboard.instance.isLogicalKeyPressed(LogicalKeyboardKey.space);

  // ---- スクロール・ズーム ----
  void _scrollBy(double dxModel, double dyModel) {
    final d = s.diagram;
    final z = d.view.zoom;
    final maxX = math.max(-200.0, d.gridWidth - _size.width / z + 200);
    final maxY = math.max(-200.0, d.gridHeight - _size.height / z + 200);
    s.setView(
      scrollX: (d.view.scrollX + dxModel).clamp(-200.0, maxX),
      scrollY: (d.view.scrollY + dyModel).clamp(-200.0, maxY),
    );
  }

  void zoomAt(Offset local, double newZoom) {
    final before = toModel(local);
    final z = newZoom.clamp(0.25, 4.0);
    s.setView(
      zoom: z,
      scrollX: before.dx - local.dx / z,
      scrollY: before.dy - local.dy / z,
    );
  }

  void resetZoom() => zoomAt(Offset(_size.width / 2, _size.height / 2), 1.0);

  /// 指定のエンティティが見えるようにスクロールする(3.5-4)。
  void revealEntity(int id) {
    final p = s.diagram.placementOf(id);
    if (p == null) return;
    final r = _rectOfPlacement(p);
    final z = s.diagram.view.zoom;
    s.setView(scrollX: r.center.dx - _size.width / z / 2, scrollY: r.center.dy - _size.height / z / 2);
  }

  /// 表示領域の中央のモデル座標。
  Offset get viewCenterModel => toModel(Offset(_size.width / 2, _size.height / 2));

  // ---- ポインタ ----
  void _onDown(PointerDownEvent e) {
    _focus.requestFocus();
    final m = toModel(e.localPosition);
    if (e.buttons == kMiddleMouseButton || (e.buttons == kPrimaryButton && _space)) {
      _mode = _Mode.pan;
      _panLast = e.localPosition;
      return;
    }
    if (e.buttons == kSecondaryButton) {
      var hit = _hitEntity(m) ?? _hitRelationship(m);
      if (hit != null && !s.selection.contains(hit)) s.setSelection([hit]);
      if (hit == null) s.setSelection([]);
      widget.host.onContextMenu(e.position, m, hit);
      return;
    }
    if (e.buttons != kPrimaryButton) return;

    final hit = _hitEntity(m);
    final now = DateTime.now();
    final isDouble = now.difference(_lastTap).inMilliseconds < 350 && _lastTapId == hit && hit != null;
    _lastTap = now;
    _lastTapId = hit;
    if (hit != null) {
      if (_hitCollapse(m, hit)) {
        final p = s.diagram.placementOf(hit)!;
        s.run(SetCollapsedCommand(s.diagram.id, hit, !p.collapsed));
        return;
      }
      if (isDouble) {
        widget.host.onFocusEntityName(hit);
        return;
      }
      _clickedId = hit;
      _clickedWasSelected = s.selection.contains(hit);
      if (_shift || _ctrl) {
        final next = {...s.selection};
        if (!next.remove(hit)) next.add(hit);
        s.setSelection(next);
      } else if (!_clickedWasSelected) {
        s.setSelection([hit]);
      }
      // 本体(列)のドラッグはリレーションシップの構築。エンティティの移動はヘッダのドラッグのみ。
      final box = s.diagram.placementOf(hit)!;
      final rect = _rectOfPlacement(box);
      final inHeader = m.dy <= rect.top + s.layouter.headerHeight;
      if (!inHeader) {
        final row = _rowAt(hit, m);
        if (row != null && !(_shift || _ctrl)) {
          _mode = _Mode.column;
          _colEntity = hit;
          _colColumn = row.$1;
          _colRect = row.$2;
          _colLabel = row.$3;
          _dragMoved = false;
          _dragStartModel = m;
        }
        return;
      }
      // ドラッグの準備(ロック中は動かさない。5.3-5)
      _mode = _Mode.drag;
      _dragMoved = false;
      _dragStartModel = m;
      _dragOrigins = {
        for (final id in s.selection)
          if (s.diagram.placementOf(id) != null && !(s.model.entityById(id)?.locked ?? false))
            id: Offset(s.diagram.placementOf(id)!.x, s.diagram.placementOf(id)!.y)
      };
      _override = {};
      return;
    }
    final rel = _hitRelationship(m);
    if (rel != null) {
      if (_shift || _ctrl) {
        final next = {...s.selection};
        if (!next.remove(rel)) next.add(rel);
        s.setSelection(next);
      } else {
        s.setSelection([rel]);
      }
      return;
    }
    // 空白: 矩形選択(空白クリックで選択解除)
    if (!(_shift || _ctrl)) s.setSelection([]);
    _mode = _Mode.marquee;
    _marqueeStart = m;
    _marquee = Rect.fromPoints(m, m);
    setState(() {});
  }

  void _onMove(PointerMoveEvent e) {
    switch (_mode) {
      case _Mode.pan:
        final z = s.diagram.view.zoom;
        final d = e.localPosition - _panLast;
        _panLast = e.localPosition;
        _scrollBy(-d.dx / z, -d.dy / z);
      case _Mode.drag:
        final m = toModel(e.localPosition);
        final delta = m - _dragStartModel;
        if (!_dragMoved && delta.distance * s.diagram.view.zoom < 3) return;
        _dragMoved = true;
        final snap = s.settings.gridSnap;
        _override = {
          for (final en in _dragOrigins.entries)
            en.key: (_alt || snap <= 0)
                ? en.value + delta
                : Offset(((en.value.dx + delta.dx) / snap).round() * snap,
                    ((en.value.dy + delta.dy) / snap).round() * snap)
        };
        setState(() {});
      case _Mode.marquee:
        final m = toModel(e.localPosition);
        _marquee = Rect.fromPoints(_marqueeStart, m);
        setState(() {});
      case _Mode.column:
        final m = toModel(e.localPosition);
        if (!_dragMoved && (m - _dragStartModel).distance * s.diagram.view.zoom < 3) return;
        _dragMoved = true;
        _colDrag = _colVisual(m);
        setState(() {});
      case _Mode.none:
        break;
    }
  }

  void _onUp(PointerUpEvent e) {
    switch (_mode) {
      case _Mode.drag:
        if (_dragMoved && _override.isNotEmpty) {
          final moves = {for (final en in _override.entries) en.key: [en.value.dx, en.value.dy]};
          _override = {};
          s.run(MovePlacementsCommand(s.diagram.id, moves));
        } else if (!_shift && !_ctrl && _clickedWasSelected && s.selection.length > 1) {
          // ドラッグしなかったクリックは、複数選択中でも単独選択にする
          s.setSelection([_clickedId!]);
        }
        _override = {};
      case _Mode.column:
        final m = toModel(e.localPosition);
        final src = _colEntity, col = _colColumn;
        final target = _dragMoved ? _hitEntity(m) : null;
        _colDrag = null;
        _colRect = null;
        if (src != null && col != null && target != null) {
          final row = _rowAt(target, m)?.$1;
          // 同じテーブルへのドロップは自己参照。別の列行へのドロップのときだけ作る(3.4-9)。
          if (target != src || (row != null && row != col)) {
            widget.host.onConnectColumns(src, col, target, row);
          }
        }
      case _Mode.marquee:
        final r = _marquee;
        if (r != null) {
          // 矩形に一部でも含まれていれば選択する(3.4-2)
          final ids = <int>{if (_shift || _ctrl) ...s.selection};
          for (final p in s.diagram.placements) {
            if (_rectOfPlacement(p).overlaps(r)) ids.add(p.entityId);
          }
          s.setSelection(ids);
        }
        _marquee = null;
      default:
        break;
    }
    _mode = _Mode.none;
    setState(() {});
  }

  void _onSignal(PointerSignalEvent e) {
    if (e is! PointerScrollEvent) return;
    final z = s.diagram.view.zoom;
    if (_ctrl) {
      zoomAt(e.localPosition, z * (e.scrollDelta.dy > 0 ? 1 / 1.1 : 1.1));
    } else if (_shift) {
      _scrollBy(e.scrollDelta.dy / z, 0);
    } else {
      _scrollBy(e.scrollDelta.dx / z, e.scrollDelta.dy / z);
    }
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final colors = CanvasColors.of(brightness);
    return DragTarget<SideItem>(
      onAcceptWithDetails: (d) {
        final m = localToModelFromGlobal(d.offset);
        switch (d.data) {
          case SideItem.table:
            widget.host.onAddTableAt(m);
          case SideItem.joinView:
            widget.host.onAddViewAt(m, ViewType.join);
          case SideItem.functionView:
            widget.host.onAddViewAt(m, ViewType.function);
          case SideItem.sqlView:
            widget.host.onAddViewAt(m, ViewType.sql);
        }
      },
      builder: (context, _, _) => LayoutBuilder(builder: (context, c) {
        _size = c.biggest;
        final v = s.diagram.view;
        return Focus(
          focusNode: _focus,
          child: Listener(
            onPointerDown: _onDown,
            onPointerMove: _onMove,
            onPointerUp: _onUp,
            onPointerSignal: _onSignal,
            child: ClipRect(
              child: CustomPaint(
                size: c.biggest,
                painter: DiagramPainter(
                  model: s.model,
                  diagram: s.diagram,
                  layouter: s.layouter,
                  colors: colors,
                  textCache: _text,
                  selection: s.selection,
                  positionOverride: _override,
                  marquee: _marquee,
                  columnDrag: _mode == _Mode.column ? _colDrag : null,
                  scale: v.zoom,
                  offset: Offset(v.scrollX, v.scrollY),
                  fontFamily: s.settings.fontFamily.isEmpty ? null : s.settings.fontFamily,
                  highlights: s.highlights,
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}
