import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'image_exporter.dart';

/// PDFのページの大きさの上限(PDFの仕様上の最大 14400pt = 200インチ)。
const double _maxPagePoints = 14400;

/// 描画済みのページ(PNG)から、1ページ=PDFの1ページのPDFを作る(9.8)。
/// ページの大きさは、論理px(96dpi)をpt(72dpi)に換算した値(用紙サイズと一致する)。
/// 画像は画面と同じPainterの描画結果で、倍率(dpi)は [renderDiagramPng] で決まる。
Future<Uint8List> buildPdf(List<RenderedPage> pages, {String? title}) async {
  final doc = pw.Document(title: title, compress: true);
  for (final p in pages) {
    var w = p.logicalWidth * 72 / 96, h = p.logicalHeight * 72 / 96;
    final longest = w > h ? w : h;
    if (longest > _maxPagePoints) {
      final k = _maxPagePoints / longest;
      w *= k;
      h *= k;
    }
    final image = pw.MemoryImage(p.png);
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat(w, h, marginAll: 0),
      margin: pw.EdgeInsets.zero,
      build: (_) => pw.Image(image, fit: pw.BoxFit.fill),
    ));
  }
  return doc.save();
}
