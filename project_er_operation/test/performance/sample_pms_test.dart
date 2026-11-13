import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart' hide Orientation;
import 'package:flutter_test/flutter_test.dart';
import 'package:project_er_operation/canvas/canvas.dart';
import 'package:project_er_operation/command/command.dart';
import 'package:project_er_operation/common/common.dart';
import 'package:project_er_operation/model/model.dart' hide Orientation;
import 'package:project_er_operation/generation/generation.dart';
import 'package:project_er_operation/persistence/persistence.dart';

import '../support/session_support.dart';

/// 実データ(テーブル430、列3357、リレーションシップ791)での自動配置と描画。
/// サンプルが無い環境ではスキップする。
/// サンプルは機能ごとのダイアグラムに分かれているため、430件すべてを1つのダイアグラムに集めて計測する(最も重い場合)。
ErModel loadAllInOne(File f) {
  final m = PeroDecoder.decode(f.readAsStringSync()).model!;
  final d = m.diagrams.first;
  m.diagrams
    ..clear()
    ..add(d..placements = [for (final e in m.entities) Placement(entityId: e.id)]..pageRows = 1..pageCols = 1);
  return m;
}

void main() {
  final f = File('doc/sample/pms_test.pero');
  late ErModel m;
  setUpAll(() {
    if (f.existsSync()) m = loadAllInOne(f);
  });

  test('自動配置: 全430件を重なりなく配置し、用紙ページが増える', () {
    final d = m.diagrams.first;
    expect(m.entities.length, 430);
    final layouter = EntityLayouter(m);
    final moves = computeAutoLayout(m, d, layouter, spacing: 40);
    expect(moves.length, d.placements.length);
    final history = CommandHistory(CommandContext(m, () => EntityLayouter(m)));
    history.execute(MovePlacementsCommand(d.id, moves));
    expect(d.pageRows, greaterThan(1));
    final after = EntityLayouter(m);
    final boxes = [for (final p in d.placements) after.boxOf(p)];
    var overlaps = 0;
    for (var i = 0; i < boxes.length; i++) {
      for (var j = i + 1; j < boxes.length; j++) {
        if (boxes[i].overlaps(boxes[j])) overlaps++;
      }
    }
    expect(overlaps, 0);
    history.undo();
    expect(m.diagrams.first.pageRows, 1, reason: 'Undoで要素が差し替わるため、モデルから引き直す');
  }, skip: !f.existsSync());

  test('セッション経由(保存済みファイルとして開いた状態。キャッシュへの記録を含む)でも自動配置が成功し、Undoできる', () {
    final s = newSession(model: loadAllInOne(f));
    s.filePath = 'C:/x/pms_test.pero';
    s.savedOnce = true;
    s.cache.writeBase(s.model, s.filePath!, baseText: CacheStore.baseTextOf(s.model));
    final moves = computeAutoLayout(s.model, s.diagram, s.layouter, spacing: s.settings.alignSpace);
    expect(s.run(MovePlacementsCommand(s.diagram.id, moves)), isTrue, reason: s.statusMessage);
    expect(s.diagram.pageRows, greaterThan(1));
    s.undo();
    expect(s.diagram.pageRows, 1);
  }, skip: !f.existsSync());

  test('描画: 配置し直した後の1フレーム(100% / 50% / 25%)は、キャッシュを使うと33ms(30fps)以内', () {
    final d = m.diagrams.first;
    final lay = EntityLayouter(m);
    CommandHistory(CommandContext(m, () => EntityLayouter(m)))
        .execute(MovePlacementsCommand(d.id, computeAutoLayout(m, d, lay, spacing: 40)));
    final layouter = EntityLayouter(m);
    final text = TextCache();
    final cache = EntityPictureCache();
    for (final scale in [1.0, 0.5, 0.25]) {
      final xs = <double>[];
      for (var i = 0; i < 12; i++) {
        final painter = DiagramPainter(
          model: m,
          diagram: d,
          layouter: layouter,
          colors: CanvasColors.light,
          textCache: text,
          scale: scale,
          offset: const Offset(0, 800),
          pictureCache: cache,
          cacheKey: 1,
        );
        final sw = Stopwatch()..start();
        final rec = ui.PictureRecorder();
        painter.paint(ui.Canvas(rec), const Size(1280, 760));
        rec.endRecording().dispose();
        xs.add(sw.elapsedMicroseconds / 1000);
      }
      xs.sort();
      expect(xs[xs.length ~/ 2], lessThan(33), reason: '倍率$scale: ${xs.map((x) => x.toStringAsFixed(1)).join(', ')}ms');
    }
  }, skip: !f.existsSync());

  test('サンプルの構成: 機能ごとのテーブル/ビューのダイアグラム、共通列(6列)のパターン、全エンティティが配置済みで検証エラーなし', () {
    final s = PeroDecoder.decode(f.readAsStringSync());
    expect(s.repairs.isEmpty, isTrue);
    final sm = s.model!;
    expect(sm.diagrams.length, greaterThan(20));
    expect(sm.diagrams.map((d) => d.name).toSet().length, sm.diagrams.length);
    expect(sm.diagrams.any((d) => d.name.endsWith('(テーブル)')), isTrue);
    expect(sm.diagrams.any((d) => d.name.endsWith('(ビュー)')), isTrue);
    for (final d in sm.diagrams) {
      final views = d.placements.map((p) => sm.entityById(p.entityId)).whereType<ViewEntity>().length;
      // テーブルとビューは別のダイアグラム
      expect(views == 0 || views == d.placements.length, isTrue, reason: d.name);
    }
    for (final e in sm.entities) {
      expect(sm.diagrams.where((d) => d.placementOf(e.id) != null).length, 1, reason: e.physicalName);
    }
    const common = ['symbol', 'remarks', 'update_at', 'update_user_id', 'update_user_history_id', 'remove'];
    expect(sm.patterns.first.columns.map((c) => c.physicalName), common);
    final applied = sm.tables.where((t) => sm.expand(t).columns.where((c) => c.isCommon).length >= 5).length;
    expect(applied, sm.tables.length, reason: '全テーブルに共通列が展開される');
    for (final t in sm.tables) {
      expect(t.columns.where((c) => c.physicalName == 'remarks'), isEmpty, reason: '${t.physicalName} の remarks は共通列');
    }
    expect(ModelValidator(sm).validate().hasErrors, isFalse);
  }, skip: !f.existsSync());
}
