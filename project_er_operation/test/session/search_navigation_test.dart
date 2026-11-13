import 'package:flutter_test/flutter_test.dart';
import 'package:project_er_operation/model/model.dart';

import '../support/sample_models.dart';
import '../support/session_support.dart';

void main() {
  test('ヒットへの移動: 次/前へ循環し、配置されていないエンティティは飛ばす(3.9-16)', () {
    final m = ErModel.empty();
    final a = table(m, 'item_a', [col(m, 'id', 'integer', pk: true)]);
    final b = table(m, 'item_b', [col(m, 'id', 'integer', pk: true)], x: 300);
    final c = table(m, 'item_c', [col(m, 'id', 'integer', pk: true)], x: 600);
    table(m, 'other', [col(m, 'id', 'integer', pk: true)], x: 900);
    table(m, 'item_unplaced', [col(m, 'id', 'integer', pk: true)], place: false);
    final s = newSession(model: m);
    expect(s.moveSearch(1), isNull); // 検索条件なし
    s.searchQuery = const SearchQuery(text: 'item_', scope: SearchScope.table);
    expect(s.moveSearch(1), a.id);
    expect(s.moveSearch(1), b.id);
    expect(s.moveSearch(1), c.id);
    expect(s.moveSearch(1), a.id); // 循環
    expect(s.moveSearch(-1), c.id); // 前へも循環
    expect(s.moveSearch(-1), b.id);
    s.searchQuery = const SearchQuery(text: 'item_', scope: SearchScope.table, regex: true); // 条件が変わると先頭から
    expect(s.moveSearch(-1), c.id);
    s.searchQuery = const SearchQuery(text: 'zzz');
    expect(s.moveSearch(1), isNull);
  });

  test('別のダイアグラムに配置されたヒットへは、そのダイアグラムへ切り替えて移動する', () {
    final m = ErModel.empty();
    final a = table(m, 'here', [col(m, 'id', 'integer', pk: true)]);
    final b = table(m, 'there', [col(m, 'id', 'integer', pk: true)], place: false);
    final d2 = Diagram(id: m.allocateId(), name: 'ダイアグラム2')..placements.add(Placement(entityId: b.id, x: 50, y: 50));
    m.diagrams.add(d2);
    final s = newSession(model: m);
    s.searchQuery = const SearchQuery(text: 'e', scope: SearchScope.table); // here, there
    expect(s.moveSearch(1), a.id);
    expect(s.diagram.id, m.diagrams.first.id);
    expect(s.moveSearch(1), b.id);
    expect(s.diagram.id, d2.id);
    expect(s.moveSearch(1), a.id);
    expect(s.diagram.id, m.diagrams.first.id);
  });

  test('ダイアグラムの切替: 順に循環、n番目、範囲外は何もしない(4.5)', () {
    final m = ErModel.empty();
    m.diagrams.add(Diagram(id: m.allocateId(), name: '2'));
    m.diagrams.add(Diagram(id: m.allocateId(), name: '3'));
    final s = newSession(model: m);
    final ids = m.diagrams.map((d) => d.id).toList();
    s.cycleDiagram(1);
    expect(s.diagram.id, ids[1]);
    s.cycleDiagram(1);
    s.cycleDiagram(1);
    expect(s.diagram.id, ids[0]); // 循環
    s.cycleDiagram(-1);
    expect(s.diagram.id, ids[2]);
    s.selectDiagramAt(1);
    expect(s.diagram.id, ids[1]);
    s.selectDiagramAt(8);
    expect(s.diagram.id, ids[1]);
  });
}
