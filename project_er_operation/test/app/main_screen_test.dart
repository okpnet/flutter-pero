import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_er_operation/app/main_screen.dart';
import 'package:project_er_operation/canvas/canvas.dart';
import 'package:project_er_operation/common/common.dart';
import 'package:project_er_operation/generation/generation.dart';
import 'package:project_er_operation/model/model.dart' hide Orientation;
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

  testWidgets('テキスト入力中は、Ctrl+V / Ctrl+A / Ctrl+C / Delete などをテキスト側で処理する(図形の貼り付け・全選択・削除を起こさない)', (tester) async {
    final s = await pump(tester);
    String? clip = 'pasted text';
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.getData') return {'text': clip};
      if (call.method == 'Clipboard.setData') {
        clip = (call.arguments as Map)['text'] as String?;
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    final tablesBefore = s.model.tables.length;
    s.setSelection([s.model.tables.first.id]);
    s.copySelection(); // 図形のクリップボードがある状態
    await tester.tap(find.byKey(const ValueKey('searchField')));
    await tester.pump();
    Future<void> ctrl(LogicalKeyboardKey k) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(k);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
    }

    await ctrl(LogicalKeyboardKey.keyV);
    expect(tester.widget<TextField>(find.byKey(const ValueKey('searchField'))).controller!.text, 'pasted text');
    expect(s.model.tables.length, tablesBefore); // 図形は貼り付けられない
    await ctrl(LogicalKeyboardKey.keyA); // テキストの全選択
    await tester.sendKeyEvent(LogicalKeyboardKey.delete); // 選択したテキストを削除(図形は削除しない)
    await tester.pump();
    expect(tester.widget<TextField>(find.byKey(const ValueKey('searchField'))).controller!.text, '');
    expect(s.model.tables.length, tablesBefore);
  });

  testWidgets('ダイアグラムの切替ショートカット: Ctrl+Tab / Ctrl+Shift+Tab(循環)、Ctrl+1〜9(4.5)', (tester) async {
    final s = await pump(tester);
    s.model.diagrams.add(Diagram(id: s.model.allocateId(), name: '2'));
    s.model.diagrams.add(Diagram(id: s.model.allocateId(), name: '3'));
    s.notify(null);
    await tester.pump();
    final ids = s.model.diagrams.map((d) => d.id).toList();
    expect(s.diagram.id, ids[0]);
    Future<void> key(LogicalKeyboardKey k, {bool shift = false}) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(k);
      if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
    }

    await key(LogicalKeyboardKey.tab);
    expect(s.diagram.id, ids[1]);
    await key(LogicalKeyboardKey.tab, shift: true);
    await key(LogicalKeyboardKey.tab, shift: true);
    expect(s.diagram.id, ids.last); // 先頭から前へ循環
    await key(LogicalKeyboardKey.digit2);
    expect(s.diagram.id, ids[1]);
    await key(LogicalKeyboardKey.digit9); // 範囲外
    expect(s.diagram.id, ids[1]);
  });

  testWidgets('タブが画面に収まらないとき、両端の◀▶ボタンで表示範囲を移動する(収まるときは出ない。3.2-5)', (tester) async {
    final s = await pump(tester);
    expect(find.byKey(const ValueKey('tabScrollLeft')), findsNothing); // 収まっている
    expect(find.byKey(const ValueKey('tabScrollRight')), findsNothing);
    for (var i = 2; i <= 40; i++) {
      s.model.diagrams.add(Diagram(id: s.model.allocateId(), name: '長めのダイアグラム名$i'));
    }
    s.notify(null);
    await tester.pump();
    await tester.pumpAndSettle();
    final left = find.byKey(const ValueKey('tabScrollLeft'));
    final right = find.byKey(const ValueKey('tabScrollRight'));
    expect(left, findsOneWidget);
    expect(right, findsOneWidget);
    expect(tester.widget<IconButton>(left).onPressed, isNull); // 左端
    expect(tester.widget<IconButton>(right).onPressed, isNotNull);
    double offset() => tester
        .state<ScrollableState>(find.descendant(of: find.byType(ReorderableListView), matching: find.byType(Scrollable)).first)
        .position
        .pixels;
    await tester.tap(right);
    await tester.pumpAndSettle();
    expect(offset(), greaterThan(100)); // 表示範囲が動いた
    expect(tester.widget<IconButton>(left).onPressed, isNotNull);
    await tester.tap(left);
    await tester.pumpAndSettle();
    expect(offset(), closeTo(0, 1));
    // 切り替えたタブが見える位置へスクロールする
    final lastId = s.model.diagrams.last.id;
    s.currentDiagramId = lastId;
    await tester.pumpAndSettle();
    final lastBox = tester.getRect(find.byKey(ValueKey('tab$lastId')));
    expect(lastBox.right, lessThanOrEqualTo(1280));
  });

  testWidgets('検索ボックスの↑↓ボタンで、ヒットしたオブジェクトへ移動する(循環)', (tester) async {
    final s = await pump(tester);
    expect(tester.widget<IconButton>(find.byKey(const ValueKey('searchNext'))).onPressed, isNull); // ヒットなし
    await tester.enterText(find.byKey(const ValueKey('searchField')), 'orders');
    await tester.pump();
    final targets = s.highlights.targets;
    expect(targets, isNotEmpty);
    await tester.tap(find.byKey(const ValueKey('searchNext')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('searchPrev')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('searchPrev')));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

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
