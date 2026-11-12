import 'package:flutter/material.dart';

/// テーマ別の色(10.2)。
class CanvasColors {
  const CanvasColors({
    required this.background,
    required this.pageBorder,
    required this.tableBackground,
    required this.tableHeader,
    required this.viewHeader,
    required this.headerText,
    required this.text,
    required this.supplementText,
    required this.foreignKeyBackground,
    required this.relationshipLine,
    required this.selection,
  });

  final Color background;
  final Color pageBorder;
  final Color tableBackground;
  final Color tableHeader;
  final Color viewHeader;
  final Color headerText;
  final Color text;
  final Color supplementText;
  final Color foreignKeyBackground;
  final Color relationshipLine;
  final Color selection;

  static const light = CanvasColors(
    background: Color(0xFFF5F5F5),
    pageBorder: Color(0xFFBDBDBD),
    tableBackground: Color(0xFFFFFFFF),
    tableHeader: Color(0xFF1F4E79),
    viewHeader: Color(0xFF5B6B7A),
    headerText: Color(0xFFFFFFFF),
    text: Color(0xFF212121),
    supplementText: Color(0xFF757575),
    foreignKeyBackground: Color(0xFFFFF3CD),
    relationshipLine: Color(0xFF424242),
    selection: Color(0xFF1976D2),
  );

  static const dark = CanvasColors(
    background: Color(0xFF1E1E1E),
    pageBorder: Color(0xFF555555),
    tableBackground: Color(0xFF2B2B2B),
    tableHeader: Color(0xFF2F6EA5),
    viewHeader: Color(0xFF5C6F82),
    headerText: Color(0xFFFFFFFF),
    text: Color(0xFFE0E0E0),
    supplementText: Color(0xFF9E9E9E),
    foreignKeyBackground: Color(0xFF4A3F1A),
    relationshipLine: Color(0xFFBDBDBD),
    selection: Color(0xFF64B5F6),
  );

  static CanvasColors of(Brightness b) => b == Brightness.dark ? dark : light;
}
