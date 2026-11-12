import 'dart:typed_data';
import 'dart:ui' as ui;

import '../common/common.dart';
import '../model/model.dart';
import 'diagram_painter.dart';

/// 1枚の画像の出力結果。
class RenderedPage {
  RenderedPage(this.name, this.png, this.logicalWidth, this.logicalHeight);
  final String name;
  final Uint8List png;

  /// 論理px(96dpi)での用紙/範囲の大きさ(PDFのページサイズに使う)。
  final double logicalWidth;
  final double logicalHeight;
}

class ImageExportResult {
  ImageExportResult(this.pages, this.effectiveDpi, this.dpiReduced);
  final List<RenderedPage> pages;
  final int effectiveDpi;

  /// 1辺の上限(16000px)を超えたためdpiを下げた(9.8-5)。
  final bool dpiReduced;
}

/// 現在のダイアグラムをPNGに描画する(9.8)。画面と同じPainterを倍率指定で使う(2-11)。
/// 選択の強調とページ境界線は含めない(9.8-8)。
Future<ImageExportResult> renderDiagramPng({
  required ErModel model,
  required Diagram diagram,
  required EntityLayouter layouter,
  required CanvasColors colors,
  required int dpi,
  required bool perPage,
  String? fontFamily,
}) async {
  const maxSide = 16000.0;
  final pw = diagram.pageWidth, ph = diagram.pageHeight;
  final unitW = perPage ? pw : diagram.gridWidth;
  final unitH = perPage ? ph : diagram.gridHeight;
  var scale = dpi / 96.0;
  var reduced = false;
  final longest = (unitW > unitH ? unitW : unitH) * scale;
  if (longest > maxSide) {
    scale = maxSide / (unitW > unitH ? unitW : unitH);
    reduced = true;
  }
  final cache = TextCache();
  final pages = <RenderedPage>[];

  Future<Uint8List> one(ui.Rect region) async {
    final w = (region.width * scale).round().clamp(1, 16000);
    final h = (region.height * scale).round().clamp(1, 16000);
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawRect(ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
        ui.Paint()..color = colors.tableBackground);
    final painter = DiagramPainter(
      model: model,
      diagram: diagram,
      layouter: layouter,
      colors: colors,
      textCache: cache,
      scale: scale,
      offset: region.topLeft,
      forExport: true,
      fontFamily: fontFamily,
      clipRect: region,
    );
    painter.paint(canvas, ui.Size(w.toDouble(), h.toDouble()));
    final image = await recorder.endRecording().toImage(w, h);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data!.buffer.asUint8List();
  }

  if (perPage) {
    for (var r = 0; r < diagram.pageRows; r++) {
      for (var c = 0; c < diagram.pageCols; c++) {
        final png = await one(ui.Rect.fromLTWH(c * pw, r * ph, pw, ph));
        pages.add(RenderedPage('${diagram.name}_r${r + 1}c${c + 1}.png', png, pw, ph));
      }
    }
  } else {
    pages.add(RenderedPage('${diagram.name}.png',
        await one(ui.Rect.fromLTWH(0, 0, diagram.gridWidth, diagram.gridHeight)),
        diagram.gridWidth, diagram.gridHeight));
  }
  return ImageExportResult(pages, (scale * 96).round(), reduced);
}
