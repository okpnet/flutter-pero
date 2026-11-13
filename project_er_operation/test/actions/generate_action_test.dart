import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_er_operation/actions/editor_actions.dart';
import 'package:project_er_operation/actions/file_dialogs.dart';
import 'package:project_er_operation/canvas/canvas.dart';
import 'package:project_er_operation/command/command.dart';
import 'package:project_er_operation/common/common.dart';
import 'package:project_er_operation/generation/generation.dart';
import 'package:project_er_operation/model/model.dart';
import 'package:project_er_operation/settings/settings.dart';

import '../support/post_models.dart';
import '../support/post_support.dart';
import '../support/session_support.dart';

/// ファイルダイアログの代わり。保存は、既定のフォルダ・ファイル名でそのまま保存する(キャンセルする設定もできる)。
class FakeFileDialogs extends FileDialogs {
  FakeFileDialogs({this.cancelSave = false});
  final bool cancelSave;
  int openCalls = 0;
  final saves = <({String title, String fileName, String? dir, String extension})>[];

  @override
  Future<String?> pickOpen({required String title, required List<String> extensions, String? initialDirectory}) async {
    openCalls++;
    return null;
  }

  @override
  Future<String?> saveBytes({
    required String title,
    required String fileName,
    required Uint8List bytes,
    required String extension,
    String? initialDirectory,
  }) async {
    saves.add((title: title, fileName: fileName, dir: initialDirectory, extension: extension));
    if (cancelSave) return null;
    final path = '${initialDirectory!}${Platform.pathSeparator}$fileName';
    File(path).writeAsBytesSync(bytes);
    return path;
  }
}

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

  Future<({EditorActions actions, dynamic session, FakeFileDialogs dialogs})> setup(WidgetTester tester,
      {required String postPath, DbKind target = DbKind.postgresql, FakeFileDialogs? dialogs, PostCatalog? catalog}) async {
    final s = newSession(model: modelSimple());
    s.settings.backupEnabled = false;
    if (catalog != null) s.postCatalog = catalog;
    final fake = dialogs ?? FakeFileDialogs();
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
      dialogs: fake,
    );
    return (actions: actions, session: s, dialogs: fake);
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

  testWidgets('生成のファイルは「保存」ダイアログで選ぶ(開くダイアログではない)。既定のフォルダ・ファイル名はモデルの出力設定', (tester) async {
    File(p('postgresql.post')).writeAsStringSync(pgScript);
    final r = await setup(tester, postPath: p('postgresql.post'));
    await runGenerate(tester, r.actions);
    expect(r.dialogs.openCalls, 0);
    expect(r.dialogs.saves.length, 1);
    final s = r.dialogs.saves.single;
    expect((s.fileName, s.extension, s.dir), ('out.sql', 'sql', dir.path));
    expect(File(p('out.sql')).existsSync(), isTrue);
  });

  testWidgets('まだ存在しないファイルへも生成できる。既存のファイルへは、OSの保存ダイアログに上書きを任せる(アプリの確認ダイアログは出さない)', (tester) async {
    File(p('postgresql.post')).writeAsStringSync(pgScript);
    File(p('out.sql')).writeAsStringSync('old');
    final r = await setup(tester, postPath: p('postgresql.post'));
    final text = await runGenerate(tester, r.actions);
    expect(text, isNot(contains('上書き')));
    expect(File(p('out.sql')).readAsStringSync(), contains('CREATE TABLE'));
  });

  testWidgets('保存ダイアログをキャンセルしたら、ファイルは書かず、ステータスバーに通知する', (tester) async {
    File(p('postgresql.post')).writeAsStringSync(pgScript);
    final r = await setup(tester, postPath: p('postgresql.post'), dialogs: FakeFileDialogs(cancelSave: true));
    await runGenerate(tester, r.actions);
    expect(File(p('out.sql')).existsSync(), isFalse);
    expect(r.session.statusMessage, Strings.generateCanceled);
  });

  testWidgets('ポストファイルのパスが空のときは、ポストフォルダの一覧から対象DBのものを使い、開くダイアログを出さない', (tester) async {
    File(p('postgresql.post')).writeAsStringSync(pgScript);
    File(p('other.post')).writeAsStringSync(pgScript.replaceFirst('targetDb=postgresql', 'targetDb=mysql'));
    PostFileInfo info(String f) => PostFileInfo(path: p(f), fileName: f, meta: parsePostMeta(File(p(f)).readAsStringSync()));
    final r = await setup(tester,
        postPath: '', catalog: PostCatalog([info('other.post'), info('postgresql.post')]));
    await runGenerate(tester, r.actions);
    expect(r.dialogs.openCalls, 0);
    expect(r.session.model.properties.postPath, p('postgresql.post'));
    expect(File(p('out.sql')).readAsStringSync(), contains('CREATE TABLE'));
  });

  testWidgets('ポストフォルダに使えるものがないときだけ、ポストファイルを開くダイアログを出す(キャンセルで中止)', (tester) async {
    final r = await setup(tester, postPath: '');
    await runGenerate(tester, r.actions);
    expect(r.dialogs.openCalls, 1);
    expect(r.dialogs.saves, isEmpty);
  });

  testWidgets('生成ファイルの拡張子は sql。設定が post(ポストファイルと同じ)や空でも sql になる', (tester) async {
    for (final ext in ['post', 'POST', '.post', '']) {
      File(p('postgresql.post')).writeAsStringSync(pgScript);
      final r = await setup(tester, postPath: p('postgresql.post'));
      r.session.settings.generatedExtension = ext;
      await runGenerate(tester, r.actions);
      final s = r.dialogs.saves.single;
      expect((s.fileName, s.extension), ('out.sql', 'sql'), reason: '設定「$ext」');
      expect(File(p('out.sql')).existsSync(), isTrue);
      File(p('out.sql')).deleteSync();
    }
  });

  testWidgets('拡張子を設定で変えたとき(例: .TXT)は、その拡張子(小文字)', (tester) async {
    File(p('postgresql.post')).writeAsStringSync(pgScript);
    final r = await setup(tester, postPath: p('postgresql.post'));
    r.session.settings.generatedExtension = '.TXT';
    await runGenerate(tester, r.actions);
    expect(r.dialogs.saves.single.fileName, 'out.txt');
  });
}
