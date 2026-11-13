import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart' hide Orientation;
import 'package:flutter_test/flutter_test.dart';
import 'package:project_er_operation/canvas/canvas.dart';
import 'package:project_er_operation/common/common.dart';
import 'package:project_er_operation/model/model.dart' hide Orientation;

import '../support/sample_models.dart';

Future<Uint8List> render(
  WidgetTester tester,
  ErModel m, {
  EntityPictureCache? cache,
  Object cacheKey = 0,
  double scale = 1.0,
  Set<int> selection = const {},
  Map<int, Offset> override = const {},
  EntityLayouter? layouter,
  TextCache? text,
}) async {
  final rec = ui.PictureRecorder();
  DiagramPainter(
    model: m,
    diagram: m.diagrams.first,
    layouter: layouter ?? EntityLayouter(m),
    colors: CanvasColors.light,
    textCache: text ?? TextCache(),
    selection: selection,
    positionOverride: override,
    scale: scale,
    pictureCache: cache,
    cacheKey: cacheKey,
  ).paint(ui.Canvas(rec), const Size(700, 500));
  final img = await rec.endRecording().toImage(700, 500);
  final data = (await tester.runAsync(() => img.toByteData()))!;
  return data.buffer.asUint8List();
}

ErModel sample() {
  final m = ErModel.empty();
  final a = table(m, 'orders', [col(m, 'id', 'auto', pk: true, logical: 'ID'), col(m, 'name', 'varchar', length: 50, logical: '名前', defKind: DefaultKind.value, defValue: 'x')], x: 40, y: 40);
  table(m, 'items', [col(m, 'id', 'integer', pk: true), col(m, 'order_id', 'integer', notNull: true)], x: 360, y: 80);
  m.entities.firstWhere((e) => e.id == a.id).locked = true; // ロックのアイコンも含める
  return m;
}

void main() {
  testWidgets('キャッシュを使った描画は、使わない描画と同じ絵になる(初回も、2回目以降も、選択中も)', (tester) async {
    final m = sample();
    final sel = {m.entities.first.id};
    final plain = await render(tester, m, selection: sel);
    final cache = EntityPictureCache();
    final first = await render(tester, m, cache: cache, selection: sel);
    expect(cache.length, 2, reason: '2つのテーブルが保持される');
    final second = await render(tester, m, cache: cache, selection: sel);
    expect(first, plain);
    expect(second, plain);
    // 選択を外しても(同じキャッシュで)選択なしの絵になる
    expect(await render(tester, m, cache: cache), await render(tester, m));
  });

  testWidgets('ドラッグ中の位置(positionOverride)でも、キャッシュした絵を位置だけ変えて描く', (tester) async {
    final m = sample();
    final id = m.entities.first.id;
    final ov = {id: const Offset(200, 250)};
    final plain = await render(tester, m, override: ov);
    final cache = EntityPictureCache();
    await render(tester, m, cache: cache);
    expect(await render(tester, m, cache: cache, override: ov), plain);
  });

  testWidgets('cacheKey(モデル・設定・テーマの世代)が変わったら破棄して描き直す', (tester) async {
    final m = sample();
    final cache = EntityPictureCache();
    final before = await render(tester, m, cache: cache, cacheKey: 1);
    // モデルを変える(列を足す)。同じキーのままなら古い絵、キーを変えれば新しい絵。
    final t = m.tables.first;
    t.columns.add(col(m, 'extra_column', 'text', logical: '追加'));
    final stale = await render(tester, m, cache: cache, cacheKey: 1, layouter: EntityLayouter(m));
    expect(stale, before, reason: '同じ世代では保持した絵を使う(これが速度の源)');
    final fresh = await render(tester, m, cache: cache, cacheKey: 2, layouter: EntityLayouter(m));
    expect(fresh, isNot(before));
    expect(fresh, await render(tester, m));
  });

  testWidgets('折りたたみの状態ごとに別の絵を保持する', (tester) async {
    final m = sample();
    final cache = EntityPictureCache();
    final open = await render(tester, m, cache: cache);
    m.diagrams.first.placements.first.collapsed = true;
    final closed = await render(tester, m, cache: cache);
    expect(closed, isNot(open));
    expect(closed, await render(tester, m));
    expect(cache.length, 3);
  });

  testWidgets('低倍率(0.4未満)では列行を省略して見出しだけを描く。キャッシュは使わない', (tester) async {
    final m = sample();
    final cache = EntityPictureCache();
    final lod = await render(tester, m, cache: cache, scale: 0.3);
    expect(cache.length, 0);
    final detail = await render(tester, m, scale: 1.0);
    expect(lod, isNot(detail));
    // 見出しのみ: 同じ倍率で、列行を描く(0.4以上)絵とは違う。例外なく描ける。
    final mid = await render(tester, m, cache: cache, scale: 0.4);
    expect(cache.length, 2);
    expect(mid, isNot(lod));
  });

  test('アイコン(グリフ)のTextPainterは、同じ指定なら使い回す', () {
    final c = TextCache();
    final a = c.glyph(Icons.lock, 12, const Color(0xFF000000));
    expect(identical(a, c.glyph(Icons.lock, 12, const Color(0xFF000000))), isTrue);
    expect(identical(a, c.glyph(Icons.lock, 14, const Color(0xFF000000))), isFalse);
  });
}

