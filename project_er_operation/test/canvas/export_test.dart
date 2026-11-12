import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:project_er_operation/canvas/canvas.dart';
import 'package:project_er_operation/common/common.dart';
import 'package:project_er_operation/model/model.dart' hide Orientation;

import '../support/sample_models.dart';

Future<ImageExportResult> render(WidgetTester tester, ErModel m, {required int dpi, required bool perPage}) async {
  final d = m.diagrams.first;
  return (await tester.runAsync(() => renderDiagramPng(
        model: m,
        diagram: d,
        layouter: EntityLayouter(m),
        colors: CanvasColors.light,
        dpi: dpi,
        perPage: perPage,
      )))!;
}

Future<ui.Image> decode(WidgetTester tester, Uint8List png) async => (await tester.runAsync(() async {
      final codec = await ui.instantiateImageCodec(png);
      return (await codec.getNextFrame()).image;
    }))!;

int count(String haystack, RegExp re) => re.allMatches(haystack).length;

void main() {
  late ErModel m;
  setUp(() {
    m = ErModel.empty(pageSize: PageSize.a4); // 横: 1123 x 794
    final d = m.diagrams.first;
    d.pageCols = 2; // 2ページ(1行2列)
    table(m, 'a', [col(m, 'id', 'integer', pk: true)], x: 100, y: 100);
    table(m, 'b', [col(m, 'id', 'integer', pk: true)], x: 1300, y: 100);
  });

  testWidgets('PNG: 用紙ページごとは1ページ=1枚(ファイル名はダイアグラム名_r行c列)、大きさは 論理px×dpi÷96', (tester) async {
    final r = await render(tester, m, dpi: 96, perPage: true);
    expect(r.pages.map((p) => p.name), ['ダイアグラム1_r1c1.png', 'ダイアグラム1_r1c2.png']);
    expect(r.dpiReduced, isFalse);
    final img = await decode(tester, r.pages.first.png);
    expect((img.width, img.height), (1123, 794));
    final r2 = await render(tester, m, dpi: 192, perPage: true); // 2倍
    final img2 = await decode(tester, r2.pages.first.png);
    expect((img2.width, img2.height), (2246, 1588));
  });

  testWidgets('PNG: 全体を1枚はグリッド全体の大きさ', (tester) async {
    final r = await render(tester, m, dpi: 96, perPage: false);
    expect(r.pages.length, 1);
    final img = await decode(tester, r.pages.single.png);
    expect((img.width, img.height), (1123 * 2, 794));
  });

  testWidgets('PDF: 用紙ページごとは1ページ=PDFの1ページ。ページの大きさは用紙サイズ(pt)', (tester) async {
    final r = await render(tester, m, dpi: 100, perPage: true);
    final pdf = (await tester.runAsync(() => buildPdf(r.pages, title: 'テスト')))!;
    final text = String.fromCharCodes(pdf);
    expect(text.startsWith('%PDF-'), isTrue);
    expect(text.trimRight().endsWith('%%EOF'), isTrue);
    expect(count(text, RegExp(r'/Type\s*/Page(?![s\w])')), 2);
    // A4横: 1123px×0.75 = 842.25pt, 794px×0.75 = 595.5pt
    expect(text, matches(RegExp(r'/MediaBox\s*\[\s*0\s+0\s+842\.2\d*\s+595\.5')));
  });

  testWidgets('PDF: 全体を1枚は1ページで、グリッド全体の大きさ', (tester) async {
    final r = await render(tester, m, dpi: 100, perPage: false);
    final pdf = (await tester.runAsync(() => buildPdf(r.pages)))!;
    final text = String.fromCharCodes(pdf);
    expect(count(text, RegExp(r'/Type\s*/Page(?![s\w])')), 1);
    expect(text, matches(RegExp(r'/MediaBox\s*\[\s*0\s+0\s+1684\.5')));
  });

  testWidgets('PDF: 大きすぎるページは上限(14400pt)に収める', (tester) async {
    final big = RenderedPage('x.png', Uint8List.fromList(const [0]), 40000, 20000);
    // 画像が不正でも上限の計算だけを検証できるよう、1x1のPNGを使う
    final png = (await tester.runAsync(() async {
      final rec = ui.PictureRecorder();
      ui.Canvas(rec).drawRect(const ui.Rect.fromLTWH(0, 0, 1, 1), ui.Paint());
      final img = await rec.endRecording().toImage(1, 1);
      return (await img.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
    }))!;
    final pdf = (await tester.runAsync(() => buildPdf([RenderedPage(big.name, png, 40000, 20000)])))!;
    expect(String.fromCharCodes(pdf), matches(RegExp(r'/MediaBox\s*\[\s*0\s+0\s+14400(\.0+)?\s+7200')));
  });
}
