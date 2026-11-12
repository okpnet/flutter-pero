import 'package:flutter_test/flutter_test.dart';
import 'package:project_er_operation/command/command.dart';
import 'package:project_er_operation/generation/generation.dart';
import 'package:project_er_operation/model/model.dart';

import '../support/sample_models.dart';

final _fmt = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');

void main() {
  test('エイリアスは物理名が既定で、重複する場合は連番', () {
    expect(uniqueAlias('orders', []), 'orders');
    expect(uniqueAlias('orders', ['orders']), 'orders_2');
    expect(uniqueAlias('orders', ['ORDERS', 'orders_2']), 'orders_3');
  });

  test('結合条件の初期値を、既存のリレーションシップの親列と子列の対応から提案する', () {
    final m = fullModel(); // customers(親) -> orders(子): customers.id = orders.customer_id
    final customers = m.tables.firstWhere((t) => t.physicalName == 'customers');
    final orders = m.tables.firstWhere((t) => t.physicalName == 'orders');
    final from = ViewSource(alias: 'o', entityId: orders.id);
    final j = ViewSource(alias: 'c', entityId: customers.id);
    final on = suggestJoinConditions(m, [from], j);
    expect(on.length, 1);
    expect(on.single.leftAlias, 'o');
    expect(on.single.leftColumnId, orders.columns[1].id); // 前のソースが子 → 左は子の列
    expect(on.single.rightColumnId, customers.columns[0].id);
    // 逆順(前のソースが親)
    final on2 = suggestJoinConditions(
        m, [ViewSource(alias: 'c', entityId: customers.id)], ViewSource(alias: 'o', entityId: orders.id));
    expect(on2.single.leftColumnId, customers.columns[0].id);
    expect(on2.single.rightColumnId, orders.columns[1].id);
    // 関係のないテーブル同士は提案なし
    final other = table(m, 'other', [col(m, 'id', 'integer', pk: true)]);
    expect(suggestJoinConditions(m, [from], ViewSource(alias: 'x', entityId: other.id)), isEmpty);
  });

  test('出力列名の重複はエイリアスを付けて避ける', () {
    expect(uniqueOutputName('id', 'o', []), 'id');
    expect(uniqueOutputName('id', 'o', ['ID']), 'o_id');
    expect(uniqueOutputName('id', 'o', ['id', 'o_id']), 'o_id_2');
  });

  test('エイリアス変更・ソース削除・テーブル変更が、結合条件と出力列へ反映される', () {
    final j = ViewJoinDef(
      sources: [
        ViewSource(alias: 'a', entityId: 1),
        ViewSource(alias: 'b', entityId: 2, on: [JoinOn(leftAlias: 'a', leftColumnId: 10, rightColumnId: 20)]),
      ],
      columns: [
        ViewOutputColumn(alias: 'a', columnId: 10, name: 'x'),
        ViewOutputColumn(alias: 'b', columnId: 20, name: 'y'),
      ],
    );
    renameAlias(j, 'a', 'aa');
    j.sources[0].alias = 'aa'; // ソース自身の名前の変更は呼び出し側(ダイアログ)が行う
    expect(j.sources[1].on.single.leftAlias, 'aa');
    expect(j.columns.first.alias, 'aa');
    changeSourceEntity(j, j.sources[1], 3); // b のテーブル変更 → b の条件と b の出力列を除く
    expect(j.sources[1].on, isEmpty);
    expect(j.columns.map((c) => c.alias), ['aa']);
    j.sources[1].on.add(JoinOn(leftAlias: 'aa', leftColumnId: 10, rightColumnId: 21));
    removeSource(j, 'aa'); // 左に使われている条件、出力列も除く
    expect(j.sources.map((s) => s.alias), ['b']);
    expect(j.sources.single.on, isEmpty);
    expect(j.columns, isEmpty);
  });

  test('定義の不備の検出は、生成前検証(9.5)と同じ観点', () {
    final m = fullModel();
    final orders = m.tables.firstWhere((t) => t.physicalName == 'orders');
    final customers = m.tables.firstWhere((t) => t.physicalName == 'customers');
    ViewEntity ok() => ViewEntity(
          id: 0,
          physicalName: 'v_ok',
          join: ViewJoinDef(
            sources: [
              ViewSource(alias: 'o', entityId: orders.id),
              ViewSource(alias: 'c', entityId: customers.id, on: [
                JoinOn(leftAlias: 'o', leftColumnId: orders.columns[1].id, rightColumnId: customers.columns[0].id)
              ]),
            ],
            columns: [
              ViewOutputColumn(alias: 'o', columnId: orders.columns[0].id, name: 'order_id'),
              ViewOutputColumn(alias: 'c', columnId: customers.columns[1].id, name: 'customer_name'),
            ],
          ),
        );
    expect(joinViewProblems(m, ok(), nameFormat: _fmt), isEmpty);
    // 問題のない定義を追加したモデルは、生成前検証でもエラーにならない
    final m2 = fullModel();
    final added = PeroDecoderSafe.copyOf(ok(), m2.allocateId());
    m2.entities.add(added);
    expect(ModelValidator(m2).validate().hasErrors, isFalse);

    String? first(void Function(ViewEntity v) f) {
      final v = ok();
      f(v);
      final p = joinViewProblems(m, v, nameFormat: _fmt);
      return p.isEmpty ? null : p.join(' / ');
    }

    expect(first((v) => v.physicalName = ''), contains('必須'));
    expect(first((v) => v.physicalName = 'customers'), contains('同じ物理名'));
    expect(first((v) => v.join.sources.clear()), contains('ソース'));
    expect(first((v) => v.join.columns.clear()), contains('出力列'));
    expect(first((v) => v.join.sources[1].on.clear()), contains('結合条件がありません'));
    expect(first((v) => v.join.columns[1].name = 'ORDER_ID'), contains('重複'));
    expect(first((v) => v.join.sources[1].alias = 'O'), contains('エイリアス'));
    expect(first((v) => v.join.columns[0].columnId = 999999), contains('存在しません'));
  });
}
