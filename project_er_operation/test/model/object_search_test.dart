import 'package:flutter_test/flutter_test.dart';
import 'package:project_er_operation/model/model.dart';

import '../support/post_models.dart';
import '../support/sample_models.dart';

void main() {
  late ErModel m;
  late TableEntity orders;
  late TableEntity customers;
  setUp(() {
    m = fullModel();
    orders = m.tables.firstWhere((t) => t.physicalName == 'orders');
    customers = m.tables.firstWhere((t) => t.physicalName == 'customers');
  });

  SearchHighlights find(String text, {SearchScope scope = SearchScope.all, bool regex = false}) =>
      searchModel(m, SearchQuery(text: text, regex: regex, scope: scope));

  test('空の条件はヒットなし', () {
    expect(find('').isEmpty, isTrue);
  });

  test('テーブル: 名前(論理名・物理名)がヒットするとヘッダを濃く、本体を薄く。大文字小文字は区別しない', () {
    final h = find('ORDERS', scope: SearchScope.table);
    expect(h.strongHeaders, {orders.id});
    expect(h.light, contains(orders.id));
    expect(find('顧客', scope: SearchScope.table).strongHeaders, {customers.id});
    expect(find('orders', scope: SearchScope.column).strongHeaders, isEmpty); // 範囲外
  });

  test('列: 列行を濃く、親のテーブルを薄く(共通列も対象)', () {
    final h = find('customer_id', scope: SearchScope.column);
    final idx = m.expand(orders).columns.indexWhere((c) => c.column.physicalName == 'customer_id');
    expect(h.strongRows[orders.id], {idx});
    expect(h.light, {orders.id});
    expect(h.strongHeaders, isEmpty);
    final common = find('created_at', scope: SearchScope.column);
    expect(common.strongRows.keys.toSet(), containsAll({orders.id, customers.id}));
  });

  test('コメント: テーブル、列、ビューのコメント', () {
    final h = find('顧客名', scope: SearchScope.comment);
    expect(h.strongRows[customers.id], isNotEmpty);
    expect(h.light, {customers.id});
    final v = find('SQLビュー', scope: SearchScope.comment);
    expect(v.strongHeaders, {m.views.firstWhere((x) => x.physicalName == 'v_sql').id});
  });

  test('ビュー: 名前と、出力列', () {
    final j = m.views.firstWhere((v) => v.physicalName == 'v_orders');
    expect(find('v_orders', scope: SearchScope.view).strongHeaders, {j.id});
    final c = find('customer_name', scope: SearchScope.column);
    expect(c.strongRows[j.id], {1});
    expect(c.light, {j.id});
  });

  test('関数: 名前のヒットは使っている側を薄く、定義のヒットは列行・ヘッダを濃くする', () {
    final created = m.patterns.single.columns.single; // 共通列 created_at のデフォルトが now_utc
    expect(created.defaultMethodId, isNotNull);
    final fn = m.methods.firstWhere((x) => x.name == 'now_utc');
    final body = fn.bodies[DbKind.postgresql]!;
    fn.bodies[DbKind.postgresql] = 'CREATE FUNCTION f() ...'; // 本体には名前を含めない
    final byName = find('now_utc', scope: SearchScope.function);
    final fnView = m.views.firstWhere((v) => v.physicalName == 'v_fn');
    expect(byName.light, contains(fnView.id));
    expect(byName.strongHeaders, isEmpty);
    expect(byName.strongRows, isEmpty);
    fn.bodies[DbKind.postgresql] = body;
    final byBody = find('CREATE FUNCTION now_utc', scope: SearchScope.function);
    expect(byBody.strongHeaders, contains(fnView.id));
    expect(byBody.strongRows[orders.id], isNotEmpty);
  });

  test('トリガー: トリガー自身は親を薄く、中のメソッドと入力の本体は濃く', () {
    final own = find('NEW.price > 0', scope: SearchScope.trigger);
    expect(own.light, {orders.id});
    expect(own.strongHeaders, isEmpty);
    final method = find('CREATE FUNCTION touch', scope: SearchScope.trigger);
    expect(method.strongHeaders, {orders.id});
    final inline = find('{{trigger}}', scope: SearchScope.trigger);
    expect(inline.strongHeaders, {orders.id});
  });

  test('正規表現: 有効なとき使い、不正なときは invalidRegex', () {
    expect(find(r'^cust.*_id$', scope: SearchScope.column, regex: true).strongRows.containsKey(orders.id), isTrue);
    expect(find(r'^cust.*_id$', scope: SearchScope.column).isEmpty, isTrue); // 正規表現でなければ文字列として検索
    final bad = find('(', regex: true);
    expect(bad.invalidRegex, isTrue);
    expect(bad.isEmpty, isTrue);
  });

  test('範囲「全て」はすべての範囲の和。ヒット数を返す', () {
    final all = find('orders');
    expect(all.strongHeaders, contains(orders.id));
    expect(all.hitCount, greaterThanOrEqualTo(1));
    expect(find('zzzz_nothing').hitCount, 0);
  });

  test('スキーマや新機能のモデルでも検索できる', () {
    final n = modelNewFeatures();
    final h = searchModel(n, const SearchQuery(text: 'node', scope: SearchScope.table));
    expect(h.strongHeaders, isNotEmpty);
  });
}
