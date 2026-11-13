import 'package:flutter_test/flutter_test.dart';
import 'package:project_er_operation/command/command.dart';
import 'package:project_er_operation/model/model.dart';
import 'package:project_er_operation/settings/settings.dart';

import '../support/sample_models.dart';
import '../support/session_support.dart';

void main() {
  group('寸法のメモ化(描画のバッファリング)', () {
    test('同じモデルの間は、同じレイアウタを使い回し、寸法も同じ値を返す', () {
      final m = ErModel.empty();
      final t = table(m, 't', [col(m, 'id', 'integer', pk: true)]);
      final s = newSession(model: m);
      final a = s.layouter;
      expect(identical(s.layouter, a), isTrue);
      final p = s.diagram.placementOf(t.id)!;
      final box = a.boxOf(p);
      expect(identical(a.rowsOf(t), a.rowsOf(t)), isTrue, reason: '列行はメモ化される');
      expect(a.boxOf(p).height, box.height);
    });

    test('コマンド(列の追加)、Undo、Redoで作り直し、寸法が変わる', () {
      final m = ErModel.empty();
      final t = table(m, 't', [col(m, 'id', 'integer', pk: true)]);
      final s = newSession(model: m);
      final g0 = s.layoutGeneration;
      final h0 = s.layouter.boxOf(s.diagram.placementOf(t.id)!).height;
      s.run(AddColumnCommand(t.id));
      expect(s.layoutGeneration, greaterThan(g0));
      final h1 = s.layouter.boxOf(s.diagram.placementOf(t.id)!).height;
      expect(h1, greaterThan(h0), reason: '列が増えたら高さも増える(古いキャッシュを使わない)');
      s.undo();
      expect(s.layouter.boxOf(s.diagram.placementOf(t.id)!).height, h0);
      s.redo();
      expect(s.layouter.boxOf(s.diagram.placementOf(t.id)!).height, h1);
    });

    test('表示設定を差し替えると作り直す(列の項目の表示切替で幅が変わる)', () {
      final m = ErModel.empty();
      final t = table(m, 't', [col(m, 'a_very_long_physical_name_for_width', 'varchar', length: 255, comment: 'コメントのテキスト')]);
      final s = newSession(model: m);
      final w0 = s.layouter.boxOf(s.diagram.placementOf(t.id)!).width;
      s.settings = AppSettings()..colComment = true..colDefault = true;
      final w1 = s.layouter.boxOf(s.diagram.placementOf(t.id)!).width;
      expect(w1, greaterThan(w0));
    });

    test('外部キー列の判定は、リレーションシップごとに走査せず一度だけ集計する(結果は従来と同じ)', () {
      final m = fullModel();
      final lay = EntityLayouter(m);
      for (final t in m.tables) {
        final fk = {for (final r in m.relationships.where((r) => r.childId == t.id)) for (final p in r.columnPairs) p.childColumnId};
        final rows = lay.rowsOf(t);
        final cols = m.expand(t).columns;
        expect([for (final r in rows) r.isForeignKey], [for (final c in cols) fk.contains(c.column.id)]);
      }
    });
  });

  group('ズーム・スクロールの通知', () {
    test('setViewは画面全体の購読者に通知せず、viewTickだけを更新する', () {
      final s = newSession(model: fullModel());
      var all = 0, view = 0;
      s.addListener(() => all++);
      s.viewTick.addListener(() => view++);
      s.setView(scrollX: 100, scrollY: 50);
      s.setView(zoom: 2);
      expect(all, 0, reason: 'テーブルリストやプロパティを再構築しない');
      expect(view, 2);
      expect(s.diagram.view.zoom, 2);
      expect((s.diagram.view.scrollX, s.diagram.view.scrollY), (100, 50));
    });
  });
}
