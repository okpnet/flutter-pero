import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_er_operation/actions/editor_actions.dart';
import 'package:project_er_operation/canvas/canvas.dart';
import 'package:project_er_operation/command/command.dart';
import 'package:project_er_operation/common/common.dart';
import 'package:project_er_operation/model/model.dart';
import 'package:project_er_operation/settings/settings.dart';

import '../support/post_models.dart';
import '../support/post_support.dart';
import '../support/session_support.dart';

/// 生成実行(RUN > 生成実行。9.6-1)のポストファイルの扱い: メタ情報による対象DBの決定、ロック、存在しないときの停止。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late String pgScript;

  setUpAll(() {
    expect(prepareQuickJs(), isTrue, reason: 'flutter build windows --debug を一度実行してください');
    pgScript = File('post/postgresql.post').readAsStringSync();
  });

  setUp(() {
    dir = Directory.systemTemp.createTempSync('pero_gen');
    addTearDown(() {
      try {
        dir.deleteSync(recursive: true);
      } on FileSystemException {
        // 後始末の失敗は無視する。
      }
    });
  });

  String p(String name) => '${dir.path}${Platform.pathSeparator}$name';

  Future<({EditorActions actions, dynamic session})> setup(WidgetTester tester, {required String postPath, DbKind target = DbKind.postgresql}) async {
    final s = newSession(model: modelSimple());
    s.settings.backupEnabled = false;
    s.run(UpdateModelPropertiesCommand({
      'postPath': postPath,
      'targetDb': target.wire,
      'outputFolder': dir.path,
      'outputFileName': 'out',
    }));
    late BuildContext ctx;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (c) {
        ctx = c;
        return const SizedBox();
      }),
    ));
    final actions = EditorActions(
      session: s,
      contextProvider: () => ctx,
      canvasKey: GlobalKey<DiagramCanvasState>(),
      nameFocus: FocusNode(),
      settingsStore: SettingsStore(exeDir: dir.path, appDataDir: dir.path),
      onSettingsApplied: (_) {},
      requestExit: () async {},
    );
    return (actions: actions, session: s);
  }

  /// 生成を実行し、ダイアログ(結果またはエラー)が出たら本文を読んで閉じる。本文を返す。
  /// ポストファイルの実行は別Isolateで行うため、実際の非同期(runAsync)の中で進める。
  Future<String> runGenerate(WidgetTester tester, EditorActions actions) async {
    var text = '';
    await tester.runAsync(() async {
      var finished = false;
      final done = actions.generate().whenComplete(() => finished = true);
      final deadline = DateTime.now().add(const Duration(seconds: 25));
      while (!finished && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump();
        if (find.byType(AlertDialog).evaluate().isNotEmpty) {
          text = tester.widgetList<Text>(find.descendant(of: find.byType(AlertDialog), matching: find.byType(Text))).map((t) => t.data ?? '').join('\n') +
              tester.widgetList<SelectableText>(find.descendant(of: find.byType(AlertDialog), matching: find.byType(SelectableText))).map((t) => t.data ?? '').join('\n');
          await tester.tap(find.text(Strings.close));
          await tester.pump();
        }
      }
      await done.timeout(const Duration(seconds: 5));
    });
    await tester.pumpAndSettle();
    return text;
  }

  testWidgets('メタ情報のkindが、モデルの対象DBと違うときは、ポストファイルのkindに合わせて生成する', (tester) async {
    File(p('postgresql.post')).writeAsStringSync(pgScript);
    final r = await setup(tester, postPath: p('postgresql.post'), target: DbKind.sqlite);
    final text = await runGenerate(tester, r.actions);
    expect(text, contains('生成が完了しました'));
    expect(r.session.model.properties.targetDb, DbKind.postgresql);
    final out = File(p('out.sql'));
    expect(out.existsSync(), isTrue);
    expect(out.readAsStringSync(), contains('CREATE TABLE'));
  });

  testWidgets('生成が終わったらポストファイルのロックを解除する(編集・削除できる)', (tester) async {
    final f = File(p('postgresql.post'))..writeAsStringSync(pgScript);
    final r = await setup(tester, postPath: f.path);
    await runGenerate(tester, r.actions);
    expect(File(p('out.sql')).existsSync(), isTrue);
    f.writeAsStringSync('$pgScript\n// edited');
    f.deleteSync();
    expect(f.existsSync(), isFalse);
  });

  testWidgets('ポストファイルが存在しないときは、処理を停止する(生成しない。ファイル選択も出さない)', (tester) async {
    final r = await setup(tester, postPath: p('missing.post'));
    final text = await runGenerate(tester, r.actions);
    expect(text, contains('ポストファイルが存在しません'));
    expect(File(p('out.sql')).existsSync(), isFalse);
  });

  testWidgets('メタ情報のkindが未対応で、関連付けも無いときは、エラーにして生成しない', (tester) async {
    File(p('oracle.post')).writeAsStringSync(pgScript.replaceFirst('targetDb=postgresql', 'targetDb=oracle'));
    final r = await setup(tester, postPath: p('oracle.post'));
    final text = await runGenerate(tester, r.actions);
    expect(text, contains('対象DB(oracle)'));
    expect(File(p('out.sql')).existsSync(), isFalse);
  });

  testWidgets('設定で関連付けたkind(oracle.post=postgresql)なら、そのkindで生成する', (tester) async {
    File(p('oracle.post')).writeAsStringSync(pgScript.replaceFirst('targetDb=postgresql', 'targetDb=oracle'));
    final r = await setup(tester, postPath: p('oracle.post'), target: DbKind.mysql);
    r.session.settings.postKindsText = 'oracle.post=postgresql';
    await runGenerate(tester, r.actions);
    expect(r.session.model.properties.targetDb, DbKind.postgresql);
    expect(File(p('out.sql')).readAsStringSync(), contains('CREATE TABLE'));
  });
}
