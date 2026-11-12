import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_er_operation/model/model.dart' hide Orientation;
import 'package:project_er_operation/panel/panel.dart';
import 'package:project_er_operation/session/session.dart';

import '../support/sample_models.dart';
import '../support/session_support.dart';

void main() {
  late EditorSession session;
  late TableEntity t;
  late FocusNode focus;

  Future<void> pumpPanel(WidgetTester tester) async {
    tester.view.physicalSize = const Size(500, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListenableBuilder(
          listenable: session,
          builder: (_, _) => PropertyPanel(
            session: session,
            nameFocus: focus,
            onManageMethods: () async {},
            onEditView: (_) async {},
          ),
        ),
      ),
    ));
  }

  setUp(() {
    final m = ErModel.empty();
    t = table(m, 'users', [col(m, 'id', 'auto', pk: true), col(m, 'name', 'varchar', length: 50)]);
    table(m, 'orders', [col(m, 'id', 'auto', pk: true)], x: 400);
    session = newSession(model: m);
    focus = FocusNode();
    addTearDown(focus.dispose);
  });

  // 列カードにも同名の項目があるため、先頭(テーブル自身の項目)を使う。
  Finder field(String label) => find.widgetWithText(TextField, label).first;
  TableEntity cur() => session.model.tableById(t.id)!;

  testWidgets('モデルのスキーマと「出力にスキーマを含める」、ダイアグラムのスキーマを編集できる(5.1-2、5.2-1)', (tester) async {
    await pumpPanel(tester);
    await tester.enterText(find.widgetWithText(TextField, 'スキーマ(ダイアグラムのスキーマが空のときに使う)'), 'app');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(session.model.properties.schema, 'app');
    await tester.tap(find.widgetWithText(SwitchListTile, '出力にスキーマを含める'));
    await tester.pump();
    expect(session.model.properties.includeSchema, isTrue);
    await tester.tap(find.widgetWithText(ChoiceChip, 'ダイアグラム'));
    await tester.pump();
    await tester.enterText(find.widgetWithText(TextField, 'スキーマ(空でモデルのスキーマ)'), 'sales');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(session.model.diagrams.first.schema, 'sales');
    session.undo();
    await tester.pump();
    expect(session.model.diagrams.first.schema, '');
  });

  testWidgets('列のデフォルトに「式」を選べる(6.2-4)', (tester) async {
    session.setSelection([t.id]);
    await pumpPanel(tester);
    await tester.tap(find.widgetWithText(ChoiceChip, '列'));
    await tester.pump();
    final name = cur().columns[1];
    await tester.tap(find.text('name').first); // 列カードを開く
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('cdk${name.id}${name.defaultKind}false')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('式').last);
    await tester.pumpAndSettle();
    expect(cur().columns[1].defaultKind, DefaultKind.expression);
    await tester.enterText(find.byKey(ValueKey('cde${name.id}')), "'x' || 'y'");
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(cur().columns[1].defaultExpression, "'x' || 'y'");
  });

  testWidgets('制約タブ: CHECK制約を追加し、ユニークにNULLS NOT DISTINCTを設定できる(6.4)', (tester) async {
    cur().uniques.add(ConstraintDef(id: session.model.allocateId(), columnIds: [cur().columns[1].id]));
    session.setSelection([t.id]);
    await pumpPanel(tester);
    await tester.tap(find.widgetWithText(ChoiceChip, '制約'));
    await tester.pump();
    await tester.tap(find.widgetWithText(SwitchListTile, 'NULLを同値として扱う(NULLS NOT DISTINCT)'));
    await tester.pump();
    expect(cur().uniques.single.nullsNotDistinct, isTrue);
    final addCheck = find.widgetWithText(FilledButton, '追加').last;
    await tester.ensureVisible(addCheck);
    await tester.tap(addCheck);
    await tester.pump();
    expect(cur().checks.length, 1);
    expect(find.text('users_ck1'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, '検査式(括弧の内側)'), 'id > 0');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(cur().checks.single.expression, 'id > 0');
  });

  testWidgets('トリガー: 引数とUPDATEの対象(指定した列)を設定できる(6.5-2)', (tester) async {
    cur().triggers.add(TriggerDef(
        id: session.model.allocateId(),
        events: [TriggerEvent.insert, TriggerEvent.update],
        inlineBodies: {DbKind.postgresql: 'CREATE FUNCTION {{trigger}}() ...'}));
    session.setSelection([t.id]);
    await pumpPanel(tester);
    await tester.tap(find.widgetWithText(ChoiceChip, 'トリガー'));
    await tester.pump();
    await tester.tap(find.textContaining('users_trg01'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, "関数への引数(例: '80', 1)"), "'80'");
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(cur().triggers.single.args, "'80'");
    final target = find.byKey(ValueKey('tuc${cur().triggers.single.id}false'));
    await tester.ensureVisible(target);
    await tester.tap(target);
    await tester.pumpAndSettle();
    await tester.tap(find.text('指定した列(UPDATE OF)').last);
    await tester.pumpAndSettle();
    expect(cur().triggers.single.updateColumnIds, [cur().columns.first.id]);
    final chip = find.widgetWithText(FilterChip, 'name');
    await tester.ensureVisible(chip);
    await tester.tap(chip);
    await tester.pump();
    expect(cur().triggers.single.updateColumnIds.length, 2);
  });

  testWidgets('何も選択していないときは、モデルとダイアグラムのタブでプロパティを表示する', (tester) async {
    await pumpPanel(tester);
    expect(find.widgetWithText(ChoiceChip, 'モデル'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'ダイアグラム'), findsOneWidget);
    expect(find.widgetWithText(TextField, '出力ファイル名'), findsOneWidget);
    expect(find.textContaining('用紙ページ'), findsNothing); // 別タブ
    await tester.tap(find.widgetWithText(ChoiceChip, 'ダイアグラム'));
    await tester.pump();
    expect(find.textContaining('用紙ページ: 1行 × 1列'), findsOneWidget);
    expect(find.widgetWithText(TextField, '出力ファイル名'), findsNothing);
  });

  testWidgets('テーブルは機能別のタブに分かれ、同じ種類の間は選択中のタブを保持する', (tester) async {
    session.setSelection([t.id]);
    await pumpPanel(tester);
    for (final label in ['基本', '列', '制約', 'トリガー', 'クエリ']) {
      expect(find.widgetWithText(ChoiceChip, label), findsOneWidget);
    }
    expect(find.widgetWithText(TextField, '論理名'), findsOneWidget); // 基本
    expect(find.text('列を追加'), findsNothing);
    await tester.tap(find.widgetWithText(ChoiceChip, '列'));
    await tester.pump();
    expect(find.text('列を追加'), findsOneWidget);
    expect(find.widgetWithText(TextField, '論理名'), findsNothing);
    // 別のテーブルを選んでも「列」タブのまま
    final other = session.model.tables.firstWhere((x) => x.id != t.id);
    session.setSelection([other.id]);
    await tester.pump();
    expect(find.text('列を追加'), findsOneWidget);
  });

  testWidgets('列の項目は1項目1行で縦に並ぶ(開いたとき、各入力欄が別の行にある)', (tester) async {
    session.setSelection([t.id]);
    await pumpPanel(tester);
    await tester.tap(find.widgetWithText(ChoiceChip, '列'));
    await tester.pump();
    await tester.tap(find.text('name'));
    await tester.pumpAndSettle();
    final ys = <double>[];
    for (final label in ['論理名', '物理名', '型', '長さ', 'デフォルト', 'コメント']) {
      final f = find.ancestor(of: find.text(label), matching: find.byType(InputDecorator));
      expect(f, findsWidgets, reason: label);
      ys.add(tester.getTopLeft(f.first).dy);
    }
    // 上から順に、互いに重ならず並ぶ
    for (var i = 1; i < ys.length; i++) {
      expect(ys[i], greaterThan(ys[i - 1]), reason: 'index $i');
    }
    // 同じ行に2つ以上の入力欄が並ばない
    final lefts = {
      for (final label in ['論理名', '物理名', '型', '長さ', 'デフォルト', 'コメント'])
        tester.getTopLeft(find.ancestor(of: find.text(label), matching: find.byType(InputDecorator)).first).dx
    };
    expect(lefts.length, 1);
  });

  testWidgets('複数選択のときは「N個選択」とロックの一括切替だけを表示する', (tester) async {
    session.setSelection(session.model.entities.map((e) => e.id));
    await pumpPanel(tester);
    expect(find.text('2個選択'), findsOneWidget);
    expect(find.byType(SwitchListTile), findsOneWidget);
    await tester.tap(find.byType(SwitchListTile));
    await tester.pump();
    expect(session.model.entities.every((e) => e.locked), isTrue);
    session.undo();
    expect(session.model.entities.any((e) => e.locked), isFalse);
  });

  testWidgets('Enterで確定すると1コマンドで反映され、Undoで戻る', (tester) async {
    session.setSelection([t.id]);
    await pumpPanel(tester);
    await tester.enterText(field('論理名'), 'ユーザー');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(cur().logicalName, 'ユーザー');
    session.undo();
    await tester.pump();
    expect(cur().logicalName, '');
  });

  testWidgets('フォーカスを失うと確定する', (tester) async {
    session.setSelection([t.id]);
    await pumpPanel(tester);
    await tester.enterText(field('コメント'), '備考');
    await tester.tap(field('物理名'));
    await tester.pump();
    expect(cur().comment, '備考');
  });

  testWidgets('不正な物理名は赤枠とメッセージで示し、確定せず元の値に戻す', (tester) async {
    session.setSelection([t.id]);
    await pumpPanel(tester);
    await tester.enterText(field('物理名'), '1bad name');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(find.textContaining('形式'), findsOneWidget);
    expect(cur().physicalName, 'users');
    // フォーカスを移すと元の値に戻る
    await tester.tap(field('論理名'));
    await tester.pump();
    await tester.pump();
    expect(cur().physicalName, 'users');
    expect(find.textContaining('形式'), findsNothing);
    final tf = tester.widget<TextField>(field('物理名'));
    expect(tf.controller!.text, 'users');
  });

  testWidgets('物理名は大文字小文字を区別せず重複できない', (tester) async {
    session.setSelection([t.id]);
    await pumpPanel(tester);
    await tester.enterText(field('物理名'), 'ORDERS');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(find.textContaining('同じ物理名'), findsOneWidget);
    expect(cur().physicalName, 'users');
  });

  testWidgets('列の追加で既定値(列N・column_N・varchar(255))が入る', (tester) async {
    session.setSelection([t.id]);
    await pumpPanel(tester);
    await tester.tap(find.widgetWithText(ChoiceChip, '列'));
    await tester.pump();
    await tester.tap(find.text('列を追加'));
    await tester.pump();
    final c = cur().columns.last;
    expect((c.logicalName, c.physicalName, c.typeId, c.length), ('列1', 'column_1', 'varchar', 255));
    expect(c.notNull, isFalse);
  });

  testWidgets('ロック中のテーブルはロック以外の項目を無効表示にする', (tester) async {
    t.locked = true;
    session.setSelection([t.id]);
    await pumpPanel(tester);
    expect(tester.widget<TextField>(field('論理名')).enabled, isFalse);
    expect(tester.widget<TextField>(field('物理名')).enabled, isFalse);
    final lock = find.widgetWithText(SwitchListTile, 'ロック');
    expect(tester.widget<SwitchListTile>(lock).onChanged, isNotNull);
  });

  testWidgets('PKにするとNotNullが固定される', (tester) async {
    session.setSelection([t.id]);
    await pumpPanel(tester);
    await tester.tap(find.widgetWithText(ChoiceChip, '列'));
    await tester.pump();
    final nameCol = cur().columns[1];
    expect(nameCol.notNull, isFalse);
    await tester.tap(find.text('name')); // 2列目を開く
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CheckboxListTile, 'PK(主キー)'));
    await tester.pump();
    final c = cur().columns[1];
    expect((c.pk, c.notNull), (true, true));
  });

  testWidgets('右ペインの既定幅(約300px)でも、全タブの全項目が横にあふれない', (tester) async {
    tester.view.physicalSize = const Size(300, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final m = fullModel();
    final s = newSession(model: m);
    final orders = m.tables.firstWhere((x) => x.physicalName == 'orders');
    final rel = m.relationships.first;
    final view = m.views.firstWhere((v) => v.viewType == ViewType.function);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListenableBuilder(
          listenable: s,
          builder: (_, _) => PropertyPanel(
            session: s,
            nameFocus: FocusNode(),
            onManageMethods: () async {},
            onEditView: (_) async {},
          ),
        ),
      ),
    ));
    Future<void> visit(int id, List<String> tabs) async {
      s.setSelection([id]);
      await tester.pumpAndSettle();
      for (final tab in tabs) {
        await tester.tap(find.widgetWithText(ChoiceChip, tab));
        await tester.pumpAndSettle();
        // 開閉できるもの(列、トリガー)は全て開く
        for (final tile in find.byType(ExpansionTile).evaluate().toList()) {
          final w = tile.widget as ExpansionTile;
          if (w.title is Text) {
            await tester.tap(find.byWidget(w.title));
            await tester.pumpAndSettle();
          }
        }
        expect(tester.takeException(), isNull, reason: tab);
      }
    }

    await visit(orders.id, ['基本', '列', '制約', 'トリガー', 'クエリ']);
    await visit(rel.id, ['基本', '列対応', '参照規則']);
    await visit(view.id, ['基本', '定義', 'クエリ']);
    s.setSelection([]);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
