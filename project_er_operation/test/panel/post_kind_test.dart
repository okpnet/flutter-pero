import 'package:flutter/material.dart' hide Orientation;
import 'package:flutter_test/flutter_test.dart';
import 'package:project_er_operation/command/command.dart';
import 'package:project_er_operation/common/common.dart';
import 'package:project_er_operation/dialog/dialog.dart';
import 'package:project_er_operation/generation/generation.dart';
import 'package:project_er_operation/model/model.dart' hide Orientation;
import 'package:project_er_operation/panel/panel.dart';
import 'package:project_er_operation/session/session.dart';

import '../support/sample_models.dart';
import '../support/session_support.dart';

/// テスト用のポストファイルのパス。
String postPath(String file) => 'C:/post/$file';

PostFileInfo post(String file, String db, {String name = 'N'}) => PostFileInfo(
      path: postPath(file),
      fileName: file,
      meta: PostMeta(name: name, targetDb: db, apiVersion: postApiVersion),
    );

void main() {
  tearDown(() => DbKindFilter.visibleKinds = null);

  EditorSession sessionWith(List<PostFileInfo> files, {String kinds = ''}) {
    final m = ErModel.empty();
    table(m, 't', [col(m, 'id', 'auto', pk: true)]);
    final s = newSession(model: m);
    s.settings.postKindsText = kinds;
    s.postCatalog = PostCatalog(files);
    s.notify(null);
    return s;
  }

  group('ポストファイルのkindで、表示する種類を制限する', () {
    test('ポストファイルがある種類だけを表示する。関連付けた種類も含む', () {
      final s = sessionWith([post('postgresql.post', 'postgresql'), post('mariadb.post', 'mariadb')],
          kinds: 'mariadb.post=mysql');
      expect(s.availableKinds, {DbKind.postgresql, DbKind.mysql});
      expect(DbKindFilter.visible, [DbKind.postgresql, DbKind.mysql]);
    });

    test('モデルが使っている対象DBは、ポストファイルが無くても表示する(データを隠さない)', () {
      final s = sessionWith([post('postgresql.post', 'postgresql')]);
      s.run(UpdateModelPropertiesCommandForTest.targetDb('sqlite'));
      expect(DbKindFilter.visible, [DbKind.postgresql, DbKind.sqlite]);
    });

    test('ポストファイルの一覧が空(未走査)のときは、すべての種類を表示する', () {
      sessionWith([]);
      expect(DbKindFilter.visible, DbKind.values);
    });

    testWidgets('メソッド・型・トリガーの対象DBごとのタブは、表示する種類だけ', (tester) async {
      sessionWith([post('postgresql.post', 'postgresql'), post('mysql.post', 'mysql')]);
      final values = {for (final k in DbKind.values) k: ''};
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: PerDbTabs(entries: [('本体', values, true)])),
      ));
      expect(find.widgetWithText(Tab, 'postgresql'), findsOneWidget);
      expect(find.widgetWithText(Tab, 'mysql'), findsOneWidget);
      expect(find.widgetWithText(Tab, 'sqlserver'), findsNothing);
      expect(find.widgetWithText(Tab, 'sqlite'), findsNothing);
    });
  });

  group('モデルのプロパティ', () {
    Future<EditorSession> pumpModelPanel(WidgetTester tester, List<PostFileInfo> files, {String kinds = ''}) async {
      tester.view.physicalSize = const Size(500, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final s = sessionWith(files, kinds: kinds);
      final focus = FocusNode();
      addTearDown(focus.dispose);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: s,
            builder: (_, _) => PropertyPanel(
              session: s,
              nameFocus: focus,
              onManageMethods: () async {},
              onEditView: (_) async {},
            ),
          ),
        ),
      ));
      return s;
    }

    testWidgets('対象のデータベースの候補は、ポストファイルがある種類だけ', (tester) async {
      await pumpModelPanel(tester, [post('postgresql.post', 'postgresql'), post('mysql.post', 'mysql')]);
      await tester.tap(find.byType(DropdownButtonFormField<DbKind>));
      await tester.pumpAndSettle();
      expect(find.text('mysql'), findsWidgets);
      expect(find.text('sqlserver'), findsNothing);
      expect(find.text('sqlite'), findsNothing);
    });

    testWidgets('ポストファイルを一覧から選ぶと、パスと対象のデータベース(メタ情報のkind)が決まる', (tester) async {
      final s = await pumpModelPanel(tester, [
        post('postgresql.post', 'postgresql', name: 'PostgreSQL用'),
        post('mysql.post', 'mysql', name: 'MySQL用'),
      ]);
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('MySQL用(mysql.post)').last);
      await tester.pumpAndSettle();
      expect(s.model.properties.postPath, postPath('mysql.post'));
      expect(s.model.properties.targetDb, DbKind.mysql);
    });

    testWidgets('メタ情報のkindが未対応のポストファイルは、関連付けた種類になる', (tester) async {
      final s = await pumpModelPanel(
          tester, [post('postgresql.post', 'postgresql'), post('mariadb.post', 'mariadb', name: 'MariaDB用')],
          kinds: 'mariadb.post=mysql');
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('MariaDB用(mariadb.post)').last);
      await tester.pumpAndSettle();
      expect(s.model.properties.targetDb, DbKind.mysql);
      expect(s.model.properties.postPath, postPath('mariadb.post'));
    });

    testWidgets('対象のデータベースを変えると、その種類のポストファイルへ切り替える', (tester) async {
      final s = await pumpModelPanel(tester, [post('postgresql.post', 'postgresql'), post('mysql.post', 'mysql')]);
      await tester.tap(find.byType(DropdownButtonFormField<DbKind>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('mysql').last);
      await tester.pumpAndSettle();
      expect(s.model.properties.targetDb, DbKind.mysql);
      expect(s.model.properties.postPath, postPath('mysql.post'));
    });
  });
}

/// テスト用: 対象DBだけを変えるコマンド。
class UpdateModelPropertiesCommandForTest {
  static UpdateModelPropertiesCommand targetDb(String wire) => UpdateModelPropertiesCommand({'targetDb': wire});
}
