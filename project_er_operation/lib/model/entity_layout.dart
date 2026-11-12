import 'diagram.dart';
import 'entity.dart';
import 'enums.dart';
import 'er_model.dart';

/// 表示設定のうち寸法に影響するもの(10.2)。
class DisplayOptions {
  const DisplayOptions({
    this.headerLogical = true,
    this.headerPhysical = true,
    this.colLogical = true,
    this.colPhysical = true,
    this.colType = true,
    this.colDefault = false,
    this.colComment = false,
    this.fontSize = 12,
    this.headerScale = 1.2,
    this.normalScale = 1.0,
    this.supplementScale = 0.8,
  });
  final bool headerLogical;
  final bool headerPhysical;
  final bool colLogical;
  final bool colPhysical;
  final bool colType;
  final bool colDefault;
  final bool colComment;
  final double fontSize;
  final double headerScale;
  final double normalScale;
  final double supplementScale;
}

/// 列行の表示文字列。キャンバス描画と寸法計算で共用する。
class RowTexts {
  const RowTexts(
      {required this.logical,
      required this.physical,
      required this.type,
      required this.defaultText,
      required this.comment});
  final String logical;
  final String physical;
  final String type;
  final String defaultText;
  final String comment;
}

class EntityRow {
  const EntityRow({
    required this.texts,
    required this.pk,
    required this.notNull,
    required this.hasDefault,
    required this.isCommon,
    required this.isForeignKey,
  });
  final RowTexts texts;
  final bool pk;
  final bool notNull;
  final bool hasDefault;
  final bool isCommon;
  final bool isForeignKey;
}

/// エンティティの寸法と行内容を決める(6.1-7、6.6-10)。純Dartのため、
/// 文字幅は文字種による近似で求める(全角=1em、半角=0.55em)。
class EntityLayouter {
  EntityLayouter(this.model, [this.options = const DisplayOptions()]);
  final ErModel model;
  final DisplayOptions options;

  static const double minWidth = 160;
  static const double maxWidth = 480;
  static const double hPad = 8;
  static const double vPad = 4;
  static const double iconWidth = 14;

  double textWidth(String s, double scale) {
    var w = 0.0;
    for (final r in s.runes) {
      w += r < 0x250 ? 0.55 : 1.0;
    }
    return w * options.fontSize * scale;
  }

  double get headerHeight => options.fontSize * options.headerScale + 2 * vPad + 4;
  double get rowHeight => options.fontSize * options.normalScale + 2 * vPad;

  String headerText(Entity e) {
    final l = options.headerLogical, p = options.headerPhysical;
    final base = (l && p)
        ? e.displayLabel
        : l
            ? e.logicalName
            : e.physicalName;
    return e is ViewEntity ? 'VIEW $base' : base;
  }

  /// 描画する列行。ビューの列行はPK等のマークを持たない。
  List<EntityRow> rowsOf(Entity e) {
    if (e is TableEntity) {
      final fkIds = <int>{
        for (final r in model.relationships.where((r) => r.childId == e.id))
          for (final p in r.columnPairs) p.childColumnId
      };
      return [
        for (final x in model.expand(e).columns)
          EntityRow(
            texts: RowTexts(
              logical: x.column.logicalName,
              physical: x.column.physicalName,
              type: model.typeLabel(x.column),
              defaultText: _defaultText(x.column),
              comment: x.column.comment,
            ),
            pk: x.column.pk,
            notNull: x.column.notNull || x.column.pk,
            hasDefault: x.column.defaultKind != DefaultKind.none,
            isCommon: x.isCommon,
            isForeignKey: fkIds.contains(x.column.id),
          )
      ];
    }
    final v = e as ViewEntity;
    if (v.viewType == ViewType.function) {
      return [
        for (final c in v.function.columns)
          EntityRow(
            texts: RowTexts(
                logical: c.logicalName,
                physical: c.name,
                type: c.typeId,
                defaultText: '',
                comment: ''),
            pk: false,
            notNull: false,
            hasDefault: false,
            isCommon: false,
            isForeignKey: false,
          )
      ];
    }
    return [
      for (final c in v.join.columns)
        EntityRow(
          texts: RowTexts(
              logical: c.logicalName,
              physical: c.name.isNotEmpty ? c.name : (model.anyColumnById(c.columnId)?.physicalName ?? ''),
              type: _viewColType(c.columnId),
              defaultText: '',
              comment: ''),
          pk: false,
          notNull: false,
          hasDefault: false,
          isCommon: false,
          isForeignKey: false,
        )
    ];
  }

  String _viewColType(int columnId) {
    final c = model.anyColumnById(columnId);
    return c == null ? '' : model.typeLabel(c);
  }

  String _defaultText(ColumnDef c) {
    switch (c.defaultKind) {
      case DefaultKind.none:
        return '';
      case DefaultKind.value:
        return c.defaultValue;
      case DefaultKind.method:
        final m = c.defaultMethodId == null ? null : model.methodById(c.defaultMethodId!);
        return m?.name ?? '';
    }
  }

  /// 項目ごとの最大幅(列行の全行をそろえる。6.1-4)。
  List<double> columnWidths(List<EntityRow> rows) {
    double mx(double Function(EntityRow) f) =>
        rows.fold(0.0, (m, r) => f(r) > m ? f(r) : m);
    final n = options.normalScale, s = options.supplementScale;
    return [
      options.colLogical ? mx((r) => textWidth(r.texts.logical, n)) : 0,
      options.colPhysical ? mx((r) => textWidth(r.texts.physical, n)) : 0,
      options.colType ? mx((r) => textWidth(r.texts.type, n)) : 0,
      options.colDefault ? mx((r) => textWidth(r.texts.defaultText, s)) : 0,
      options.colComment ? mx((r) => textWidth(r.texts.comment, s)) : 0,
    ];
  }

  static const double itemGap = 8;

  /// (幅, 高さ)。[collapsed] のときヘッダのみ。
  (double, double) sizeOf(Entity e, {bool collapsed = false}) {
    final rows = rowsOf(e);
    final headerW = textWidth(headerText(e), options.headerScale) + iconWidth * 2;
    final widths = columnWidths(rows);
    var rowW = iconWidth * 3; // PK, NotNull, デフォルトありのアイコン
    for (final w in widths) {
      if (w > 0) rowW += w + itemGap;
    }
    var w = (rowW > headerW ? rowW : headerW) + hPad * 2;
    w = w.clamp(minWidth, maxWidth);
    final h = headerHeight + (collapsed ? 0 : rows.length * rowHeight);
    return (w.ceilToDouble(), h.ceilToDouble());
  }

  Box boxOf(Placement p) {
    final e = model.entityById(p.entityId);
    if (e == null) return Box(p.x, p.y, 0, 0);
    final (w, h) = sizeOf(e, collapsed: p.collapsed);
    return Box(p.x, p.y, w, h);
  }

  (double, double) placementSize(Placement p) {
    final b = boxOf(p);
    return (b.width, b.height);
  }
}
