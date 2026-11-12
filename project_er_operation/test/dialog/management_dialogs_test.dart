import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_er_operation/dialog/dialog.dart';
import 'package:project_er_operation/model/model.dart' hide Orientation;
import 'package:project_er_operation/panel/panel.dart';

import '../support/sample_models.dart';
import '../support/session_support.dart';

const _fmt = r'^[A-Za-z_][A-Za-z0-9_]*$';

/// ボタンからダイアログを開き、結果を [result] に入れる。
Future<void> openDialog<T>(WidgetTester tester, Future<T?> Function(BuildContext) open, void Function(T?) result) async {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (c) => Scaffold(
        body: TextButton(onPressed: () async => result(await open(c)), child: const Text('open')),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('メソッド管理: 追加して名前・本体を入力しOK。重複名はエラーで閉じない', (tester) async {
    final m = ErModel.empty();
    List<MethodDef>? out;
    await openDialog<List<MethodDef>>(tester, (c) => showMethodDialog(c, m, nameFormat: _fmt), (r) => out = r);
    await tester.tap(find.text('追加'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, '名前'), 'fn_a');
    await tester.enterText(find.widgetWithText(TextFormField, '本体(CREATE文)').first, 'CREATE FUNCTION fn_a() ...');
    await tester.tap(find.text('追加'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, '名前'), 'FN_A');
    await tester.pumpAndSettle();
    expect(find.text('同じ名前のメソッドが存在します'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(out, isNull);
    expect(find.text('メソッド管理'), findsOneWidget); // 閉じない
    // OK時のエラーは最初の不正なメソッド(先頭)を選択し直す。先頭を直す。
    await tester.enterText(find.widgetWithText(TextFormField, '名前'), 'fn_b');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(out!.map((x) => x.name), ['fn_b', 'FN_A']);
    expect(out!.first.bodies[DbKind.postgresql], 'CREATE FUNCTION fn_a() ...'); // 本体は先頭に入力したもの
    expect(out!.first.id, isNot(out!.last.id));
    expect(out!.first.id, greaterThanOrEqualTo(m.nextId));
  });

  testWidgets('メソッド管理: 参照されているメソッドの削除は警告し、関数ビューが参照していれば削除できない', (tester) async {
    final m = fullModel();
    List<MethodDef>? out;
    await openDialog<List<MethodDef>>(tester, (c) => showMethodDialog(c, m, nameFormat: _fmt), (r) => out = r);
    await tester.tap(find.text('削除'));
    await tester.pumpAndSettle();
    expect(find.text('削除できません'), findsOneWidget); // now_utc は関数ビューとデフォルトから参照されている
    await tester.tap(find.text('閉じる'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('トリガー'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('削除'));
    await tester.pumpAndSettle();
    expect(find.text('メソッドの削除'), findsOneWidget); // 確認(参照の一覧つき)
    await tester.tap(find.text('はい'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(out!.map((x) => x.name), ['now_utc']);
  });

  testWidgets('共通列パターン管理: 追加、正規表現の試験欄、一致テーブルの一覧、列の追加', (tester) async {
    final m = ErModel.empty();
    table(m, 'mst_user', [col(m, 'id', 'integer')]);
    table(m, 'tmp_user', [col(m, 'id', 'integer')]);
    List<CommonColumnPattern>? out;
    await openDialog<List<CommonColumnPattern>>(tester, (c) => showPatternDialog(c, m, nameFormat: _fmt), (r) => out = r);
    await tester.tap(find.text('追加').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, '対象フィルタ(正規表現・全体一致)'), 'mst_.*');
    await tester.pumpAndSettle();
    expect(find.textContaining('一致するテーブル(1件): mst_user'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextFormField, '試験: テーブル物理名を入力'), 'mst_a');
    await tester.pumpAndSettle();
    expect(find.text('一致'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextFormField, '試験: テーブル物理名を入力'), 'xmst_a');
    await tester.pumpAndSettle();
    expect(find.text('不一致'), findsOneWidget); // 全体一致
    // 不正な正規表現は赤表示
    await tester.enterText(find.widgetWithText(TextFormField, '対象フィルタ(正規表現・全体一致)'), '(');
    await tester.pumpAndSettle();
    expect(find.textContaining('正規表現が不正です'), findsWidgets);
    await tester.enterText(find.widgetWithText(TextFormField, '対象フィルタ(正規表現・全体一致)'), 'mst_.*');
    await tester.tap(find.text('列を追加'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(out!.single.include, 'mst_.*');
    expect(out!.single.columns.single.physicalName, 'column_1');
    expect(out!.single.columns.single.pk, isFalse);
  });

  testWidgets('型管理: カスタム型を追加し、標準型の物理名テンプレートを編集して初期値に戻せる', (tester) async {
    final m = ErModel.empty();
    (List<DataType>, Map<String, String>)? out;
    await openDialog<(List<DataType>, Map<String, String>)>(tester, (c) => showTypeManagerDialog(c, m), (r) => out = r);
    await tester.tap(find.text('カスタム型を追加'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, '表示名'), 'money');
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(out!.$1.length, standardTypes().length + 1);
    expect(out!.$1.last.id, 'custom_1');
    expect(out!.$1.last.displayName, 'money');
    expect(out!.$1.last.isStandard, isFalse);
  });

  testWidgets('関数ビュー定義: 関数未選択と戻り列なしはエラー。入力してOKで定義が返る', (tester) async {
    final m = fullModel();
    ViewEntity? out;
    await openDialog<ViewEntity>(tester, (c) => showFunctionViewDialog(c, m, nameFormat: _fmt, onManageMethods: () async {}), (r) => out = r);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text('関数を選択してください'), findsOneWidget);
    await tester.tap(find.byType(DropdownButtonFormField<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('now_utc').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text('戻り列を1つ以上入力してください'), findsOneWidget);
    await tester.tap(find.text('追加').last); // 戻り列
    await tester.pumpAndSettle();
    await tester.tap(find.text('追加').first); // 引数
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, '引数1'), '10');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(out, isNotNull);
    expect(out!.viewType, ViewType.function);
    expect(out!.function.args, ['10']);
    expect(out!.function.columns.single.name, 'column_1');
    expect(out!.function.methodId, m.methods.firstWhere((x) => x.name == 'now_utc').id);
  });

  testWidgets('トリガー編集(プロパティペイン): 追加、イベントは1つ以上、手動名の重複チェック、順の保持', (tester) async {
    tester.view.physicalSize = const Size(600, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final m = ErModel.empty();
    final t = table(m, 'users', [col(m, 'id', 'auto', pk: true)]);
    final session = newSession(model: m);
    session.setSelection([t.id]);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListenableBuilder(
          listenable: session,
          builder: (_, _) => PropertyPanel(
            session: session,
            nameFocus: FocusNode(),
            onManageMethods: () async {},
            onEditView: (_) async {},
          ),
        ),
      ),
    ));
    await tester.tap(find.widgetWithText(ChoiceChip, 'トリガー'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '追加'));
    await tester.pumpAndSettle();
    var tr = session.model.tableById(t.id)!.triggers;
    expect(tr.length, 1);
    expect(find.text('1. users_trg01'), findsOneWidget); // 自動名
    expect(tr.single.events, [TriggerEvent.insert]);
    await tester.tap(find.text('1. users_trg01'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilterChip, 'UPDATE'));
    await tester.pumpAndSettle();
    tr = session.model.tableById(t.id)!.triggers;
    expect(tr.single.events, [TriggerEvent.insert, TriggerEvent.update]);
    // INSERTを外す → UPDATEのみ。最後の1つは外せない
    await tester.tap(find.widgetWithText(FilterChip, 'INSERT'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilterChip, 'UPDATE'));
    await tester.pumpAndSettle();
    expect(session.model.tableById(t.id)!.triggers.single.events, [TriggerEvent.update]);
    // 2つ目を追加すると順が名前に入る
    await tester.tap(find.widgetWithText(FilledButton, '追加'));
    await tester.pumpAndSettle();
    expect(find.text('2. users_trg02'), findsOneWidget);
    // 追加→Undoで戻る
    session.undo();
    await tester.pumpAndSettle();
    expect(session.model.tableById(t.id)!.triggers.length, 1);
  });

  testWidgets('結合ビュー定義: ソースを追加すると結合条件が提案され、全列を出力列にしてOKで定義が返る', (tester) async {
    final m = fullModel();
    final customers = m.tables.firstWhere((t) => t.physicalName == 'customers');
    final orders = m.tables.firstWhere((t) => t.physicalName == 'orders');
    ViewEntity? out;
    await openDialog<ViewEntity>(tester, (c) => showJoinViewDialog(c, m, nameFormat: _fmt), (r) => out = r);
    // 何も選ばずOK → 不備を表示して閉じない
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.textContaining('ソースを1つ以上'), findsOneWidget);
    expect(out, isNull);

    Future<void> addSource(String label) async {
      await tester.tap(find.text('ソースを追加'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining(label).last);
      await tester.pumpAndSettle();
    }

    await addSource('orders');
    await addSource('customers');
    expect(find.text('条件を追加'), findsOneWidget); // 2つ目のソースにだけ結合条件の欄がある
    await tester.tap(find.text('orders の全列を追加'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('customers の全列を追加'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, '物理名'), 'v_join');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(out, isNotNull);
    final j = out!.join;
    expect(out!.viewType, ViewType.join);
    expect(j.sources.map((s) => s.alias), ['orders', 'customers']);
    // リレーションシップ(customers.id = orders.customer_id)から提案された結合条件
    expect(j.sources[1].on.single.leftAlias, 'orders');
    expect(j.sources[1].on.single.leftColumnId, orders.columns[1].id);
    expect(j.sources[1].on.single.rightColumnId, customers.columns[0].id);
    expect(j.sources[1].joinType, JoinType.inner);
    // 出力列: ソースの全列(実列+共通列)。名前の重複は別名で避ける
    expect(j.columns.length, m.expand(orders).columns.length + m.expand(customers).columns.length);
    final names = j.columns.map((c) => c.name.toLowerCase()).toList();
    expect(names.toSet().length, names.length);
    expect(names, contains('id'));
    expect(names, contains('customers_id'));
  });

  testWidgets('結合ビュー定義: 既存の結合ビューを編集して返す(結合種別の変更)。元のビューは変更されない', (tester) async {
    final m = fullModel();
    final v = m.views.firstWhere((x) => x.viewType == ViewType.join);
    ViewEntity? out;
    await openDialog<ViewEntity>(tester, (c) => showJoinViewDialog(c, m, nameFormat: _fmt, initial: v), (r) => out = r);
    expect(find.text('結合ビューの定義を編集'), findsOneWidget);
    await tester.tap(find.byType(DropdownButtonFormField<JoinType>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('INNER').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(out!.id, v.id);
    expect(out!.join.sources[1].joinType, JoinType.inner); // LEFT から変更
    expect(v.join.sources[1].joinType, JoinType.left); // 作業コピーのため元は変わらない
  });
}
