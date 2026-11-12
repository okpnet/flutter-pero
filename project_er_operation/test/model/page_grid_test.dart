import 'package:flutter_test/flutter_test.dart';
import 'package:project_er_operation/command/command.dart';
import 'package:project_er_operation/model/model.dart';

import '../support/sample_models.dart';

void main() {
  // A4横: 1123 x 794
  late ErModel m;
  late Diagram d;
  late CommandHistory h;
  late TableEntity t;

  setUp(() {
    m = ErModel.empty(pageSize: PageSize.a4);
    d = m.diagrams.first;
    t = table(m, 't', [col(m, 'id', 'integer', pk: true)], x: 100, y: 100);
    h = CommandHistory(CommandContext(m, () => EntityLayouter(m)));
  });

  Box box() => EntityLayouter(m).boxOf(d.placementOf(t.id)!);

  test('用紙サイズ表(5.2-2)', () {
    expect(pageDimensions(PageSize.a0, Orientation.portrait), (3179.0, 4494.0));
    expect(pageDimensions(PageSize.a3, Orientation.landscape), (1587.0, 1123.0));
    expect(pageDimensions(PageSize.a4, Orientation.landscape), (1123.0, 794.0));
    expect(pageDimensions(PageSize.a4, Orientation.portrait), (794.0, 1123.0));
  });

  test('右へはみ出すと、収まるまで列を追加する', () {
    h.execute(MovePlacementsCommand(d.id, {t.id: [1100, 100]}));
    expect(d.pageCols, 2);
    expect(d.pageRows, 1);
    h.execute(MovePlacementsCommand(d.id, {t.id: [1123 * 2 + 10.0, 100]}));
    // 3列目が必要になるが、左の2列は空なので削除され(中抜けを作らない)、座標は平行移動される
    expect(d.pageCols, 1);
    expect(d.placementOf(t.id)!.x, 10);
  });

  test('下へはみ出すと行を追加し、端が空になれば削除する(最低1×1)', () {
    h.execute(MovePlacementsCommand(d.id, {t.id: [100, 780]}));
    expect(d.pageRows, 2);
    h.execute(MovePlacementsCommand(d.id, {t.id: [100, 100]}));
    expect(d.pageRows, 1);
    expect(d.pageCols, 1);
  });

  test('左・上へ移動して追加した場合は、すべての配置を平行移動して原点を維持する', () {
    final other = table(m, 'o', [col(m, 'id', 'integer', pk: true)], x: 300, y: 300);
    h.execute(MovePlacementsCommand(d.id, {t.id: [-50, -60]}));
    expect(d.pageCols, 2);
    expect(d.pageRows, 2);
    // 追加したページの幅(高さ)だけ全配置を平行移動。見た目の相対位置は不変
    expect(d.placementOf(t.id)!.x, 1123 - 50);
    expect(d.placementOf(t.id)!.y, 794 - 60);
    expect(d.placementOf(other.id)!.x, 300 + 1123);
    expect(d.placementOf(other.id)!.y, 300 + 794);
  });

  test('左端の列が空になれば削除し、座標をページ幅だけ戻す', () {
    h.execute(MovePlacementsCommand(d.id, {t.id: [-50, 100]}));
    expect(d.pageCols, 2);
    final x = d.placementOf(t.id)!.x;
    h.execute(MovePlacementsCommand(d.id, {t.id: [x + 100, 100]}));
    expect(d.pageCols, 1);
    expect(d.placementOf(t.id)!.x, x + 100 - 1123);
  });

  test('矩形が複数ページにまたがることを許す。中抜けは作らない', () {
    final a = table(m, 'a', [col(m, 'id', 'integer')], x: 0, y: 0);
    final b = table(m, 'b', [col(m, 'id', 'integer')], x: 2300, y: 0);
    h.execute(MovePlacementsCommand(d.id, {a.id: [0, 0], b.id: [2300, 0]}));
    expect(d.pageCols, 3);
    final w = box().width;
    h.execute(MovePlacementsCommand(d.id, {a.id: [1123 - w / 2, 0]}));
    expect(d.pageCols, 3); // 1列目と2列目にまたがり、3列目にbがある
  });

  test('用紙サイズ・向きの変更は座標を変えずグリッドを再計算する', () {
    h.execute(MovePlacementsCommand(d.id, {t.id: [1100, 100]}));
    expect(d.pageCols, 2);
    h.execute(UpdateDiagramPageCommand(d.id, PageSize.a3, Orientation.landscape));
    expect(d.placementOf(t.id)!.x, 1100);
    expect(d.pageCols, 1);
  });

  test('配置を外す/モデルから削除してもページを再計算する', () {
    h.execute(MovePlacementsCommand(d.id, {t.id: [1100, 100]}));
    h.execute(RemovePlacementsCommand(d.id, [t.id]));
    expect(d.pageCols, 1);
    expect(m.entityById(t.id), isNotNull); // エンティティはモデルに残る
  });

  test('ロック中のエンティティは移動しない', () {
    t.locked = true;
    h.execute(MovePlacementsCommand(d.id, {t.id: [500, 500]}));
    expect(d.placementOf(t.id)!.x, 100);
    expect(() => h.execute(RemovePlacementsCommand(d.id, [t.id])), throwsA(isA<CommandException>()));
  });
}
