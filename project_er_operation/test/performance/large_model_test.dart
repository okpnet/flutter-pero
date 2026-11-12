import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';
import 'package:project_er_operation/canvas/canvas.dart';
import 'package:project_er_operation/command/command.dart';
import 'package:project_er_operation/common/common.dart';
import 'package:project_er_operation/generation/generation.dart';
import 'package:project_er_operation/model/model.dart' hide Orientation;
import 'package:project_er_operation/persistence/persistence.dart';

import '../support/sample_models.dart';
import '../support/session_support.dart';

/// 性能目標(2-8): テーブル200、列の合計3000、リレーションシップ300で、
/// パン・ズーム・ドラッグが体感できる遅延なく動作する(目安30fps以上 = 1フレーム33ms以下)。
/// 計測値は環境依存のため、テストの上限は目標の数倍に緩めてある。実測値は標準出力とレポートに記録する。
ErModel largeModel() {
  final m = ErModel.empty(pageSize: PageSize.a3);
  final d = m.diagrams.first;
  const tables = 200, colsPerTable = 15; // 200 x 15 = 3000列
  final ts = <TableEntity>[];
  for (var i = 0; i < tables; i++) {
    final cols = [
      col(m, 'id', 'auto', pk: true, logical: 'ID'),
      for (var c = 1; c < colsPerTable; c++)
        col(m, 'column_$c', c % 3 == 0 ? 'varchar' : 'integer', length: 100, logical: '項目$c', notNull: c % 4 == 0),
    ];
    final t = TableEntity(id: m.allocateId(), logicalName: 'テーブル$i', physicalName: 'table_$i', columns: cols);
    m.entities.add(t);
    ts.add(t);
    // 20列 x 10行のグリッド状に配置
    d.placements.add(Placement(entityId: t.id, x: 40 + (i % 20) * 260.0, y: 40 + (i ~/ 20) * 420.0));
  }
  // 300本のリレーションシップ(親の主キー -> 子の列)
  for (var i = 0; i < 300; i++) {
    final p = ts[i % tables], c = ts[(i * 7 + 3) % tables];
    if (p.id == c.id) continue;
    m.relationships.add(Relationship(
      id: m.allocateId(),
      parentId: p.id,
      childId: c.id,
      columnPairs: [ColumnPair(parentColumnId: p.columns[0].id, childColumnId: c.columns[1 + (i % (colsPerTable - 1))].id)],
    ));
  }
  d.recalcPages((p) => (200, 400));
  return m;
}

/// 中央値(ms)。
double median(List<double> xs) => (xs.toList()..sort())[xs.length ~/ 2];

double time(void Function() f, {int n = 15}) {
  final xs = <double>[];
  for (var i = 0; i < n; i++) {
    final sw = Stopwatch()..start();
    f();
    xs.add(sw.elapsedMicroseconds / 1000.0);
  }
  return median(xs);
}

void main() {
  late ErModel m;
  setUpAll(() => m = largeModel());

  test('モデルの規模(テーブル200、列3000、リレーションシップ300)', () {
    expect(m.tables.length, 200);
    expect(m.tables.fold<int>(0, (a, t) => a + t.columns.length), 3000);
    expect(m.relationships.length, greaterThanOrEqualTo(290));
  });

  test('描画1フレームの時間(100%で表示領域のみ / 25%で全体 / 選択あり)', () {
    final d = m.diagrams.first;
    final cache = TextCache();
    final layouter = EntityLayouter(m);
    double frame({required double zoom, required Offset offset, Size size = const Size(1280, 760), Set<int> sel = const {}}) {
      final painter = DiagramPainter(
        model: m,
        diagram: d,
        layouter: layouter,
        colors: CanvasColors.light,
        textCache: cache,
        scale: zoom,
        offset: offset,
        selection: sel,
      );
      return time(() {
        final rec = ui.PictureRecorder();
        painter.paint(ui.Canvas(rec), size);
        rec.endRecording().dispose();
      });
    }

    final z100 = frame(zoom: 1.0, offset: const Offset(2000, 1500));
    final z100sel = frame(zoom: 1.0, offset: const Offset(2000, 1500), sel: m.entities.take(20).map((e) => e.id).toSet());
    final z25 = frame(zoom: 0.25, offset: Offset.zero, size: const Size(1280, 760));
    // ignore: avoid_print
    print('[perf] 描画1フレーム(中央値) 100%: ${z100.toStringAsFixed(1)}ms / 選択20: ${z100sel.toStringAsFixed(1)}ms / 25%全体: ${z25.toStringAsFixed(1)}ms');
    expect(z100, lessThan(100));
    expect(z25, lessThan(200));
  });

  test('ヒットテスト・寸法計算・コマンド(ドラッグ確定)の時間', () {
    final d = m.diagrams.first;
    final layouter = EntityLayouter(m);
    final boxes = time(() {
      for (final p in d.placements) {
        layouter.boxOf(p);
      }
    });
    final segs = time(() {
      relationshipSegments(m, d, (id) {
        final p = d.placementOf(id);
        if (p == null) return null;
        final b = layouter.boxOf(p);
        return Rect.fromLTWH(b.left, b.top, b.width, b.height);
      }, layouter.headerHeight);
    });
    final h = CommandHistory(CommandContext(m, () => layouter));
    final ids = d.placements.take(10).map((p) => p.entityId).toList();
    var dx = 10.0;
    final move = time(() {
      dx += 10;
      h.execute(MovePlacementsCommand(d.id, {for (final id in ids) id: [dx, dx]}));
    }, n: 9);
    final undo = time(() {
      h.undo();
      h.redo();
    }, n: 9);
    final expand = time(() {
      for (final t in m.tables) {
        m.expand(t);
      }
    });
    // ignore: avoid_print
    print('[perf] 全エンティティの寸法: ${boxes.toStringAsFixed(1)}ms / リレーションシップの線分: ${segs.toStringAsFixed(1)}ms / '
        'ドラッグ確定(コマンド): ${move.toStringAsFixed(1)}ms / Undo+Redo: ${undo.toStringAsFixed(1)}ms / 共通列の展開(全テーブル): ${expand.toStringAsFixed(1)}ms');
    expect(boxes, lessThan(100));
    expect(segs, lessThan(150));
    expect(move, lessThan(300));
  });

  test('保存形式の変換・整合性確認・生成前検証・生成用JSONの時間', () {
    final enc = time(() => PeroEncoder.encode(m), n: 5);
    final text = PeroEncoder.encode(m);
    final dec = time(() => PeroDecoder.decode(text), n: 5);
    final val = time(() => ModelValidator(m).validate(), n: 5);
    final json = time(() => GenerationJsonBuilder(m).buildText(), n: 5);
    // ignore: avoid_print
    print('[perf] .pero ${(text.length / 1024).round()}KB 書出し: ${enc.toStringAsFixed(0)}ms / 読込+整合性確認: ${dec.toStringAsFixed(0)}ms / '
        '生成前検証: ${val.toStringAsFixed(0)}ms / 生成用JSON: ${json.toStringAsFixed(0)}ms');
    expect(enc, lessThan(2000));
    expect(dec, lessThan(3000));
  });

  test('描画: 文字レイアウトのキャッシュが空の最初のフレーム(コールド)', () {
    final d = m.diagrams.first;
    final layouter = EntityLayouter(m);
    final xs = <double>[];
    for (var i = 0; i < 5; i++) {
      final painter = DiagramPainter(
        model: m, diagram: d, layouter: layouter, colors: CanvasColors.light,
        textCache: TextCache(), scale: 0.5, offset: Offset.zero,
      );
      final sw = Stopwatch()..start();
      final rec = ui.PictureRecorder();
      painter.paint(ui.Canvas(rec), const Size(1280, 760));
      rec.endRecording().dispose();
      xs.add(sw.elapsedMicroseconds / 1000.0);
    }
    // ignore: avoid_print
    print('[perf] コールドの最初のフレーム(50%): 中央値 ${median(xs).toStringAsFixed(1)}ms / 最大 ${xs.reduce((a, b) => a > b ? a : b).toStringAsFixed(1)}ms');
    expect(median(xs), lessThan(400));
  });

  testWidgets('ウィジェット: ヘッダのドラッグ中の1ポインタ移動あたりの再構築(build+layout+paint)', (tester) async {
    tester.view.physicalSize = const Size(1280, 760);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final s = newSession(model: m);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: DiagramCanvas(session: s, host: _NoopHost()))));
    final first = s.diagram.placements.first;
    final b = EntityLayouter(s.model).boxOf(first);
    final g = await tester.startGesture(Offset(b.left + 20, b.top + 8), kind: PointerDeviceKind.mouse);
    final xs = <double>[];
    for (var i = 0; i < 30; i++) {
      final sw = Stopwatch()..start();
      await g.moveBy(const Offset(7, 5));
      await tester.pump();
      xs.add(sw.elapsedMicroseconds / 1000.0);
    }
    await g.up();
    await tester.pump();
    // ignore: avoid_print
    print('[perf] ドラッグ1移動あたり(中央値): ${median(xs).toStringAsFixed(1)}ms / 最大 ${xs.reduce((a, b) => a > b ? a : b).toStringAsFixed(1)}ms');
    expect(median(xs), lessThan(100));
  });

  testWidgets('実フォント(Windows標準の日本語フォント)での描画: コールド/ウォームの1フレーム', (tester) async {
    final f = File(r'C:\Windows\Fonts\msgothic.ttc');
    if (!f.existsSync()) {
      markTestSkipped('日本語フォントが見つからないためスキップ');
      return;
    }
    await tester.runAsync(() async {
      final loader = FontLoader('PerfJP')..addFont(Future.value(ByteData.view(f.readAsBytesSync().buffer)));
      await loader.load();
    });
    final d = m.diagrams.first;
    final layouter = EntityLayouter(m);
    final cache = TextCache();
    double frame(double zoom) {
      final painter = DiagramPainter(
        model: m, diagram: d, layouter: layouter, colors: CanvasColors.light,
        textCache: cache, scale: zoom, offset: Offset.zero, fontFamily: 'PerfJP',
      );
      final sw = Stopwatch()..start();
      final rec = ui.PictureRecorder();
      painter.paint(ui.Canvas(rec), const Size(1280, 760));
      rec.endRecording().dispose();
      return sw.elapsedMicroseconds / 1000.0;
    }

    final cold = frame(0.5);
    final warm = median([for (var i = 0; i < 9; i++) frame(0.5)]);
    final coldFull = (() {
      cache.clear();
      return frame(0.25);
    })();
    // ignore: avoid_print
    print('[perf] 実フォント(MS Gothic) 50%: コールド ${cold.toStringAsFixed(1)}ms / ウォーム ${warm.toStringAsFixed(1)}ms / 25%全体のコールド ${coldFull.toStringAsFixed(1)}ms');
    expect(warm, lessThan(100));
  });
}

class _NoopHost implements CanvasHost {
  @override
  void onAddTableAt(Offset modelPos) {}
  @override
  void onAddViewAt(Offset modelPos, ViewType type) {}
  @override
  void onFocusEntityName(int entityId) {}
  @override
  void onConnectColumns(int a, int b, int c, int? d) {}
  @override
  Future<void> onContextMenu(Offset globalPos, Offset modelPos, int? hitId) async {}
}
