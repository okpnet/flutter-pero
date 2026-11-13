import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_er_operation/canvas/canvas.dart';
import 'package:project_er_operation/model/model.dart' hide Orientation;
import 'package:project_er_operation/session/session.dart';

import '../support/sample_models.dart';
import '../support/session_support.dart';

class _Host implements CanvasHost {
  int? focused;
  @override
  void onAddTableAt(Offset p) {}
  @override
  void onAddViewAt(Offset p, ViewType t) {}
  @override
  void onFocusEntityName(int id) => focused = id;
  @override
  void onConnectColumns(int s, int sc, int t, int? tc) => connected = [s, sc, t, tc];
  List<int?>? connected;
  @override
  Future<void> onContextMenu(Offset g, Offset m, int? hit) async {}
}

void main() {
  late EditorSession session;
  late TableEntity a, b;
  late _Host host;

  Future<void> pumpCanvas(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: DiagramCanvas(session: session, host: host)),
    ));
  }

  setUp(() {
    final m = ErModel.empty();
    a = table(m, 'a', [col(m, 'id', 'auto', pk: true), col(m, 'name', 'text')], x: 100, y: 100);
    b = table(m, 'b', [col(m, 'id', 'auto', pk: true)], x: 500, y: 100);
    session = newSession(model: m);
    host = _Host();
  });

  Placement pl(int id) => session.diagram.placementOf(id)!;

  testWidgets('クリックで単独選択、Shiftで追加、空白クリックで解除', (tester) async {
    await pumpCanvas(tester);
    await tester.tapAt(const Offset(120, 110), kind: PointerDeviceKind.mouse);
    expect(session.selection, {a.id});
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.tapAt(const Offset(520, 110), kind: PointerDeviceKind.mouse);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    expect(session.selection, {a.id, b.id});
    await tester.tapAt(const Offset(50, 600), kind: PointerDeviceKind.mouse);
    expect(session.selection, isEmpty);
  });

  testWidgets('ドラッグ移動は10pxグリッドにスナップし、1コマンドでUndoできる', (tester) async {
    await pumpCanvas(tester);
    final g = await tester.startGesture(const Offset(120, 110), kind: PointerDeviceKind.mouse);
    await g.moveBy(const Offset(53, 27));
    await g.moveBy(const Offset(2, 3));
    await g.up();
    await tester.pump();
    expect((pl(a.id).x, pl(a.id).y), (160, 130)); // 155→160(四捨五入)、130→130
    session.undo();
    expect((pl(a.id).x, pl(a.id).y), (100, 100));
  });

  testWidgets('Alt押下中はスナップしない', (tester) async {
    await pumpCanvas(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    final g = await tester.startGesture(const Offset(120, 110), kind: PointerDeviceKind.mouse);
    await g.moveBy(const Offset(53, 27));
    await g.up();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pump();
    expect((pl(a.id).x, pl(a.id).y), (153, 127));
  });

  testWidgets('複数選択のドラッグは全て移動し、ロック中のものは動かない', (tester) async {
    await pumpCanvas(tester);
    session.setSelection([a.id, b.id]);
    session.model.entityById(b.id)!.locked = true;
    await tester.pump();
    final g = await tester.startGesture(const Offset(120, 110), kind: PointerDeviceKind.mouse);
    await g.moveBy(const Offset(40, 40));
    await g.up();
    await tester.pump();
    expect((pl(a.id).x, pl(a.id).y), (140, 140));
    expect((pl(b.id).x, pl(b.id).y), (500, 100));
  });

  testWidgets('空白のドラッグで矩形選択(一部でも含まれれば選択)', (tester) async {
    await pumpCanvas(tester);
    final g = await tester.startGesture(const Offset(30, 30), kind: PointerDeviceKind.mouse);
    await g.moveTo(const Offset(150, 150));
    await g.up();
    await tester.pump();
    expect(session.selection, {a.id});
    final g2 = await tester.startGesture(const Offset(30, 400), kind: PointerDeviceKind.mouse);
    await g2.moveTo(const Offset(800, 120));
    await g2.up();
    await tester.pump();
    expect(session.selection, {a.id, b.id});
  });

  testWidgets('折りたたみボタンでコマンドが実行される(Undo対象)', (tester) async {
    await pumpCanvas(tester);
    final r = EntityLayouter(session.model).boxOf(pl(a.id));
    await tester.tapAt(Offset(r.right - 8, r.top + 8), kind: PointerDeviceKind.mouse);
    expect(pl(a.id).collapsed, isTrue);
    session.undo();
    expect(pl(a.id).collapsed, isFalse);
  });

  testWidgets('ダブルクリックで論理名入力へフォーカスを依頼する', (tester) async {
    await pumpCanvas(tester);
    await tester.tapAt(const Offset(150, 160), kind: PointerDeviceKind.mouse);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tapAt(const Offset(150, 160), kind: PointerDeviceKind.mouse);
    expect(host.focused, a.id);
  });

  testWidgets('Ctrl+ホイールでカーソル位置中心にズーム(25〜400%)、ホイールでスクロール', (tester) async {
    await pumpCanvas(tester);
    final mouse = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(mouse.hover(const Offset(300, 300)));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendEventToBinding(mouse.scroll(const Offset(0, -100)));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    final v = session.diagram.view;
    expect(v.zoom, closeTo(1.1, 1e-9));
    expect(v.scrollX + 300 / v.zoom, closeTo(300, 1e-6)); // カーソル位置のモデル座標が不変
    for (var i = 0; i < 60; i++) {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendEventToBinding(mouse.scroll(const Offset(0, -100)));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    }
    expect(session.diagram.view.zoom, 4.0);
    session.setView(zoom: 1.0, scrollX: 0, scrollY: 0);
    await tester.sendEventToBinding(mouse.scroll(const Offset(0, 100)));
    expect(session.diagram.view.scrollY, 100);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendEventToBinding(mouse.scroll(const Offset(0, 50)));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    expect(session.diagram.view.scrollX, 50);
  });

  testWidgets('中ボタンのドラッグでパンする', (tester) async {
    await pumpCanvas(tester);
    final g = await tester.startGesture(const Offset(300, 300),
        kind: PointerDeviceKind.mouse, buttons: kMiddleMouseButton);
    await g.moveBy(const Offset(-40, -30));
    await g.up();
    expect(session.diagram.view.scrollX, 40);
    expect(session.diagram.view.scrollY, 30);
  });

  testWidgets('リレーションシップは線から6px以内でクリック選択できる', (tester) async {
    final m = session.model;
    m.relationships.add(Relationship(
        id: m.allocateId(),
        parentId: a.id,
        childId: b.id,
        columnPairs: [ColumnPair(parentColumnId: a.columns[0].id, childColumnId: b.columns[0].id)]));
    await pumpCanvas(tester);
    final ra = EntityLayouter(m).boxOf(pl(a.id)), rb = EntityLayouter(m).boxOf(pl(b.id));
    final mid = Offset((ra.right + rb.left) / 2,
        (ra.top + ra.height / 2 + rb.top + rb.height / 2) / 2);
    await tester.tapAt(mid + const Offset(0, 5), kind: PointerDeviceKind.mouse);
    expect(session.selection, {m.relationships.single.id});
    await tester.tapAt(mid + const Offset(0, 40), kind: PointerDeviceKind.mouse);
    expect(session.selection, isEmpty);
  });

  testWidgets('エンティティの移動はヘッダのドラッグのみ。本体(列)のドラッグでは動かない', (tester) async {
    await pumpCanvas(tester);
    final g = await tester.startGesture(const Offset(150, 135), kind: PointerDeviceKind.mouse); // 列行
    await g.moveBy(const Offset(40, 0));
    await g.up();
    await tester.pump();
    expect((pl(a.id).x, pl(a.id).y), (100, 100));
  });

  testWidgets('ヘッダのドラッグ中は、ドラッグしているエンティティを半透明でポインタ位置に表示し、ドラッグ元には何も描かない', (tester) async {
    final key = GlobalKey();
    tester.view.physicalSize = const Size(1000, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: RepaintBoundary(key: key, child: DiagramCanvas(session: session, host: host))),
    ));
    Future<List<int>> pixel(double x, double y) async {
      final boundary = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      return (await tester.runAsync(() async {
        final img = await boundary.toImage();
        final data = (await img.toByteData())!;
        final i = ((y.toInt() * img.width) + x.toInt()) * 4;
        return [data.getUint8(i), data.getUint8(i + 1), data.getUint8(i + 2)];
      }))!;
    }

    final before = await pixel(130, 110); // aのヘッダ(不透明)
    final g = await tester.startGesture(const Offset(120, 110), kind: PointerDeviceKind.mouse);
    await g.moveBy(const Offset(0, 300)); // 真下へ(100,400付近)
    await tester.pump();
    final origin = await pixel(130, 110); // ドラッグ元
    final moved = await pixel(130, 410); // ドラッグ中の位置
    final painter = tester.widget<CustomPaint>(find.byType(CustomPaint).last).painter as DiagramPainter;
    expect(painter.positionOverride.keys, [a.id]);
    expect(origin, isNot(before)); // ドラッグ元のヘッダは描かれない
    expect(moved, isNot(before)); // 半透明なので不透明のヘッダ色とは異なる
    expect(moved, isNot(origin)); // 背景とも異なる(エンティティが見える)
    await g.up();
    await tester.pump();
    final after = tester.widget<CustomPaint>(find.byType(CustomPaint).last).painter as DiagramPainter;
    expect(after.positionOverride, isEmpty);
  });

  testWidgets('列のドラッグでリレーションシップ構築を開始し、列にドロップすると完了する(ドラッグ中は列の画像を表示)', (tester) async {
    await pumpCanvas(tester);
    final g = await tester.startGesture(const Offset(150, 135), kind: PointerDeviceKind.mouse);
    await g.moveTo(const Offset(540, 138));
    await tester.pump();
    final painter = tester.widget<CustomPaint>(find.byType(CustomPaint).last).painter as DiagramPainter;
    expect(painter.columnDrag, isNotNull);
    expect(painter.columnDrag!.label, contains('id'));
    expect(painter.columnDrag!.targetRect, isNotNull); // ドロップ先の強調
    await g.up();
    await tester.pump();
    expect(host.connected, [a.id, a.columns[0].id, b.id, b.columns[0].id]);
    expect((pl(a.id).x, pl(a.id).y), (100, 100));
  });

  testWidgets('列のドラッグ中にダイアグラムを切り替えても続けられ、別のダイアグラムのテーブルへドロップできる(3.4-9)', (tester) async {
    final m = session.model;
    final c = table(m, 'c', [col(m, 'id', 'auto', pk: true)], x: 300, y: 300);
    // c は2つめのダイアグラムにだけ配置する
    m.diagrams.first.placements.removeWhere((p) => p.entityId == c.id);
    final d2 = Diagram(id: m.allocateId(), name: 'ダイアグラム2')..placements.add(Placement(entityId: c.id, x: 300, y: 300));
    m.diagrams.add(d2);
    await pumpCanvas(tester);
    final g = await tester.startGesture(const Offset(150, 135), kind: PointerDeviceKind.mouse);
    await g.moveTo(const Offset(300, 200));
    await tester.pump();
    final state = tester.state<DiagramCanvasState>(find.byType(DiagramCanvas));
    expect(state.columnDragPointer.value, isNotNull); // メイン画面がタブの切替に使う
    session.currentDiagramId = d2.id; // タブの上でドラッグを止めて切り替わった
    await tester.pump();
    await g.moveTo(const Offset(320, 340)); // c の列行
    await tester.pump();
    final painter = tester.widget<CustomPaint>(find.byType(CustomPaint).last).painter as DiagramPainter;
    expect(painter.columnDrag, isNotNull);
    expect(painter.columnDrag!.targetRect, isNotNull);
    await g.up();
    await tester.pump();
    expect(host.connected, [a.id, a.columns[0].id, c.id, c.columns[0].id]);
    expect(state.columnDragPointer.value, isNull);
  });

  testWidgets('エンティティ(ヘッダ)へのドロップは列未指定、空白へのドロップは何もしない', (tester) async {
    await pumpCanvas(tester);
    var g = await tester.startGesture(const Offset(150, 135), kind: PointerDeviceKind.mouse);
    await g.moveTo(const Offset(540, 110));
    await g.up();
    expect(host.connected, [a.id, a.columns[0].id, b.id, null]);
    host.connected = null;
    g = await tester.startGesture(const Offset(150, 135), kind: PointerDeviceKind.mouse);
    await g.moveTo(const Offset(300, 500));
    await g.up();
    expect(host.connected, isNull);
  });
}
