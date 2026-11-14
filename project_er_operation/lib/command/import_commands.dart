import 'dart:math' as math;

import '../importer/importer.dart';
import '../model/model.dart';
import 'auto_layout.dart';
import 'command_base.dart';

/// SQLインポートの結果(付録E)をモデルへ追加する(9.11)。取り込んだエンティティは、
/// 指定のダイアグラムの既存の配置の下へ置き、自動配置(9.9)で並べる。
class ImportSqlCommand extends ModelCommand {
  ImportSqlCommand({required this.diagramId, required this.data, this.spacing = 40});

  final int diagramId;

  /// ポストファイルが返したインポート結果。
  final Map<String, Object?> data;
  final double spacing;

  /// 実行結果(再生時は作られない)。
  ImportReport? report;

  @override
  String get type => 'importSql';
  @override
  Map<String, Object?> argsToJson() => {'diagramId': diagramId, 'data': data, 'spacing': spacing};

  @override
  void apply(CommandContext ctx) {
    final m = ctx.model;
    final diagram = m.diagramById(diagramId) ?? m.diagrams.first;
    final rep = SqlImportConverter(m).convert(data);
    if (rep.isEmpty) {
      throw CommandException('取り込めるテーブル・ビュー・関数・型がありませんでした');
    }
    final layouter = ctx.layouter();
    var startY = 40.0;
    for (final p in diagram.placements) {
      startY = math.max(startY, layouter.boxOf(p).bottom + spacing);
    }
    for (final id in rep.entityIds) {
      diagram.placements.add(Placement(entityId: id, x: 40, y: startY));
    }
    final moves = computeAutoLayout(m, diagram, ctx.layouter(), selected: rep.entityIds.toSet(), spacing: spacing);
    for (final p in diagram.placements) {
      final mv = moves[p.entityId];
      if (mv == null) continue;
      p.x = mv[0];
      p.y = mv[1];
    }
    ctx.recalcPages(diagram);
    report = rep;
  }
}
