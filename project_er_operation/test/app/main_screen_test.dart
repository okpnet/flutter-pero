import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_er_operation/app/main_screen.dart';
import 'package:project_er_operation/canvas/canvas.dart';
import 'package:project_er_operation/common/common.dart';
import 'package:project_er_operation/generation/generation.dart';
import 'package:project_er_operation/session/session.dart';
import 'package:project_er_operation/settings/settings.dart';
import 'package:theme_lib/theme_lib.dart';

import '../support/sample_models.dart';
import '../support/session_support.dart';

PostCatalog validCatalog() => const PostCatalog([
      PostFileInfo(
        path: 'postgresql.post',
        fileName: 'postgresql.post',
        meta: PostMeta(name: 'PostgreSQL', targetDb: 'postgresql', apiVersion: postApiVersion),
      ),
    ]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final windowCalls = <String>[];
  setUp(() {
    windowCalls.clear();
    // window_manager のネイティブ側は無いので、すべて成功(null)で返し、呼び出しを記録する。
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('window_manager'), (call) async {
      windowCalls.add(call.method);
      return null;
    });
  });

  var destroyed = 0;

  Future<EditorSession> pump(WidgetTester tester, {PostCatalog? catalog}) async {
    destroyed = 0;
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final s = newSession(model: fullModel());
    s.postCatalog = catalog ?? validCatalog();
    s.settings.backupEnabled = false; // 定期バックアップのタイマーを起動しない
    final dir = Directory.systemTemp.createTempSync('pero_main');
    addTearDown(() => dir.deleteSync(recursive: true));
    await tester.pumpWidget(MaterialApp(
      // 実機と同じ、theme_lib のテーマ(入力欄の余白が大きい)で確認する。
      theme: ThemeBuilder.build(openDesignTheme, Brightness.dark),
      home: MainScreen(
        session: s,
        settingsStore: SettingsStore(exeDir: dir.path, appDataDir: dir.path),
        onSettingsApplied: (_) {},
        destroyWindow: () async => destroyed++,
      ),
    ));
    await tester.pump();
    return s;
  }

  testWidgets('検索の入力欄、正規表現のトグル、範囲のプルダウンは同じ高さ', (tester) async {
    await pump(tester);
    final field = tester.getSize(find.byKey(const ValueKey('searchField'))).height;
    final regex = tester.getSize(find.descendant(of: find.byKey(const ValueKey('searchRegex')), matching: find.byType(Container)).first).height;
    final scope = tester
        .getSize(find.ancestor(of: find.byKey(const ValueKey('searchScope')), matching: find.byType(Container)).first)
        .height;
    expect(field, 32);
    expect(regex, 32);
    expect(scope, 32);
  });

  testWidgets('サイドメニューの項目は、どのタブでも折り返さずに1行で表示する', (tester) async {
    await pump(tester);
    for (var i = 0; i < 4; i++) {
      await tester.tap(find.byKey(ValueKey('sideTab$i')));
      await tester.pump();
      for (final t in tester.widgetList<Text>(find.descendant(of: find.descendant(of: find.byKey(const ValueKey('sideMenu')), matching: find.byType(ListTile)), matching: find.byType(Text)))) {
        // 1行のテキストは、行の高さ(フォントサイズ以下の余裕)に収まる。2行なら倍になる。
        final size = tester.getSize(find.byWidget(t));
        expect(size.height, lessThan(26), reason: '「${t.data}」が折り返している');
        expect(t.softWrap, isFalse);
      }
    }
  });

  testWidgets('サイドメニューとプロパティは、ボタンで折りたたみ/スライドインできる(キャンバスが広がる)', (tester) async {
    final s = await pump(tester);
    final base = tester.getSize(find.byType(DiagramCanvas)).width;
    await tester.tap(find.byKey(const ValueKey('toggleSideMenu')));
    await tester.pumpAndSettle();
    final noSide = tester.getSize(find.byType(DiagramCanvas)).width;
    expect(noSide, greaterThan(base + 150));
    expect(s.settings.sideMenuOpen, isFalse);
    await tester.tap(find.byKey(const ValueKey('toggleRightPane')));
    await tester.pumpAndSettle();
    final wide = tester.getSize(find.byType(DiagramCanvas)).width;
    expect(wide, greaterThan(noSide + 200));
    expect(s.settings.rightPaneOpen, isFalse);
    // もう一度押すと元に戻る
    await tester.tap(find.byKey(const ValueKey('toggleSideMenu')));
    await tester.tap(find.byKey(const ValueKey('toggleRightPane')));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(DiagramCanvas)).width, closeTo(base, 1));
  });

  testWidgets('ポストファイルが1つも無いときは、警告を出して終了する(キャッシュは消さない)', (tester) async {
    await pump(tester, catalog: const PostCatalog.empty());
    await tester.pump();
    expect(find.textContaining('ポストファイル(*.post)が見つかりません'), findsOneWidget);
    await tester.tap(find.text(Strings.close));
    await tester.pumpAndSettle();
    expect(destroyed, 1);
  });

  testWidgets('ポストファイルがあるときは、警告せずに起動する', (tester) async {
    await pump(tester);
    await tester.pump();
    expect(find.textContaining('見つかりません'), findsNothing);
    expect(destroyed, 0);
  });

  testWidgets('読込中は、画面全体のオーバーレイとローディング(くるくる)を表示し、終わると消える', (tester) async {
    final s = await pump(tester);
    expect(find.byKey(const ValueKey('busyOverlay')), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    s.busyMessage.value = Strings.loadingFile('pms_test.pero');
    await tester.pump();
    expect(find.byKey(const ValueKey('busyOverlay')), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('pms_test.pero を読み込み中…'), findsOneWidget);
    // 画面全体を覆う
    final size = tester.getSize(find.byKey(const ValueKey('busyOverlay')));
    expect(size, const Size(1280, 800));
    // 覆っている間は、下の画面の操作(サイドメニューのタブ)を受け付けない
    await tester.tap(find.byKey(const ValueKey('sideTab2')), warnIfMissed: false);
    await tester.pump();
    expect(find.text('元に戻す'), findsNothing);
    s.busyMessage.value = null;
    await tester.pump();
    expect(find.byKey(const ValueKey('busyOverlay')), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}
