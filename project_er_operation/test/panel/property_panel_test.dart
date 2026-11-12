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
            onEditFunctionView: (_) async {},
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

  testWidgets('何も選択していないときはモデルとダイアグラムのプロパティを表示する', (tester) async {
    await pumpPanel(tester);
    expect(find.text('モデル'), findsOneWidget);
    expect(find.text('ダイアグラム'), findsOneWidget);
    expect(find.textContaining('用紙ページ: 1行 × 1列'), findsOneWidget);
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
    await tester.tap(find.text('追加').first);
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
    final nameCol = cur().columns[1];
    expect(nameCol.notNull, isFalse);
    // 2列目のPKチェック(各列カードのCheckbox: PK, NotNull の順)
    final boxes = find.byType(Checkbox);
    await tester.tap(boxes.at(2)); // 2列目のPK
    await tester.pump();
    final c = cur().columns[1];
    expect((c.pk, c.notNull), (true, true));
  });
}
