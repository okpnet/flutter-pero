import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_er_operation/actions/editor_actions.dart';
import 'package:project_er_operation/canvas/canvas.dart';
import 'package:project_er_operation/common/common.dart';
import 'package:project_er_operation/persistence/persistence.dart';
import 'package:project_er_operation/settings/settings.dart';

import '../support/sample_models.dart';
import '../support/session_support.dart';

/// ファイルを開く操作(4.1-2〜4.1-8)の、読込中の表示。
void main() {
  late Directory dir;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('pero_openact');
    addTearDown(() {
      try {
        dir.deleteSync(recursive: true);
      } on FileSystemException {
        // 後始末の失敗は無視する。
      }
    });
  });

  Future<({EditorActions actions, dynamic session})> setup(WidgetTester tester) async {
    final s = newSession();
    s.settings.backupEnabled = false;
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

  /// 開く処理を、フレームを進めながら最後まで実行する。
  Future<void> runOpen(WidgetTester tester, Future<void> Function() open) async {
    await tester.runAsync(() async {
      var finished = false;
      final done = open().whenComplete(() => finished = true);
      final deadline = DateTime.now().add(const Duration(seconds: 20));
      while (!finished && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await tester.pump();
      }
      await done.timeout(const Duration(seconds: 5));
    });
  }

  testWidgets('開いている間だけ「読み込み中」を表示し、読み込んだモデルに切り替わる', (tester) async {
    final path = '${dir.path}${Platform.pathSeparator}a.pero';
    File(path).writeAsStringSync(PeroEncoder.encode(fullModel()));
    final r = await setup(tester);
    final seen = <String?>[];
    r.session.busyMessage.addListener(() => seen.add(r.session.busyMessage.value));
    await runOpen(tester, () => r.actions.openPath(path, skipConfirm: true));
    expect(seen, [Strings.loadingFile('a.pero'), null]);
    expect(r.session.busyMessage.value, isNull);
    expect(r.session.filePath, path);
    expect(r.session.model.entities, isNotEmpty);
  });

  testWidgets('読み込みに失敗しても、表示は必ず消える。エラーを表示する', (tester) async {
    final path = '${dir.path}${Platform.pathSeparator}bad.pero';
    File(path).writeAsStringSync('{ not json');
    final r = await setup(tester);
    final seen = <String?>[];
    r.session.busyMessage.addListener(() => seen.add(r.session.busyMessage.value));
    await tester.runAsync(() async {
      var finished = false;
      final done = r.actions.openPath(path, skipConfirm: true).whenComplete(() => finished = true);
      final deadline = DateTime.now().add(const Duration(seconds: 20));
      while (!finished && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await tester.pump();
        if (find.text(Strings.close).evaluate().isNotEmpty) {
          await tester.tap(find.text(Strings.close));
          await tester.pump();
        }
      }
      await done.timeout(const Duration(seconds: 5));
    });
    expect(seen, [Strings.loadingFile('bad.pero'), null]);
    expect(r.session.filePath, isNull);
  });

  testWidgets('読み込み中に、もう一度開く操作をしても、二重には読み込まない', (tester) async {
    final path = '${dir.path}${Platform.pathSeparator}a.pero';
    File(path).writeAsStringSync(PeroEncoder.encode(fullModel()));
    final r = await setup(tester);
    r.session.busyMessage.value = '読み込み中';
    await tester.runAsync(() => r.actions.openPath(path, skipConfirm: true));
    expect(r.session.filePath, isNull);
    expect(r.session.busyMessage.value, '読み込み中');
  });
}
