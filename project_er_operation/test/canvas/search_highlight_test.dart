import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:project_er_operation/canvas/canvas.dart';
import 'package:project_er_operation/command/command.dart';
import 'package:project_er_operation/common/common.dart';
import 'package:project_er_operation/model/model.dart' hide Orientation;

import '../support/sample_models.dart';
import '../support/session_support.dart';

Future<ui.Image> paint(WidgetTester tester, ErModel m, SearchHighlights h, {bool forExport = false}) async {
  final rec = ui.PictureRecorder();
  final canvas = ui.Canvas(rec);
  DiagramPainter(
    model: m,
    diagram: m.diagrams.first,
    layouter: EntityLayouter(m),
    colors: CanvasColors.light,
    textCache: TextCache(),
    highlights: h,
    forExport: forExport,
  ).paint(canvas, const ui.Size(800, 600));
  return rec.endRecording().toImage(800, 600);
}

Future<int> pixel(WidgetTester tester, ui.Image img, int x, int y) async {
  final data = (await tester.runAsync(() => img.toByteData()))!;
  final i = (y * img.width + x) * 4;
  return (data.getUint8(i) << 16) | (data.getUint8(i + 1) << 8) | data.getUint8(i + 2);
}

void main() {
  testWidgets('ヒットした列行は濃く、親のテーブルは薄く、ヒットなしのテーブルはそのまま。画像出力には含めない(3.9)', (tester) async {
    final m = ErModel.empty();
    final a = table(m, 'a', [col(m, 'id', 'integer', pk: true), col(m, 'name', 'text')], x: 40, y: 40);
    table(m, 'b', [col(m, 'id', 'integer', pk: true)], x: 400, y: 40);
    final h = searchModel(m, const SearchQuery(text: 'name', scope: SearchScope.column));
    expect(h.strongRows[a.id], {1});
    final lay = EntityLayouter(m);
    final rowY = (40 + lay.headerHeight + lay.rowHeight * 1.5).round(); // 2行目の中央
    final plain = await paint(tester, m, SearchHighlights.none);
    final lit = await paint(tester, m, h);
    final exported = await paint(tester, m, h, forExport: true);
    // 濃い列行は、ハイライトなしと異なる色。ほかのテーブルは同じ色。画像出力はハイライトなしと同じ。
    expect(await pixel(tester, lit, 60, rowY), isNot(await pixel(tester, plain, 60, rowY)));
    expect(await pixel(tester, lit, 440, rowY - 20), await pixel(tester, plain, 440, rowY - 20));
    expect(await pixel(tester, exported, 60, rowY), await pixel(tester, plain, 60, rowY));
    // 親(1行目)は薄いハイライト、2行目は濃い
    final first = (40 + lay.headerHeight + lay.rowHeight * 0.5).round();
    expect(await pixel(tester, lit, 60, first), isNot(await pixel(tester, plain, 60, first)));
    expect(await pixel(tester, lit, 60, first), isNot(await pixel(tester, lit, 60, rowY)));
  });

  test('セッション: 検索条件とモデルの変更でヒットを再計算し、同じ状態ではキャッシュを使う', () {
    final s = newSession(model: fullModel());
    expect(s.highlights.isEmpty, isTrue);
    s.searchQuery = const SearchQuery(text: 'orders', scope: SearchScope.table);
    final h1 = s.highlights;
    expect(h1.strongHeaders, isNotEmpty);
    expect(identical(s.highlights, h1), isTrue);
    s.run(AddTableCommand(diagramId: s.diagram.id, x: 0, y: 0));
    expect(identical(s.highlights, h1), isFalse);
  });
}
