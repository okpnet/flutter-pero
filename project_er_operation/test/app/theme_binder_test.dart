import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger_provider/logger_provider.dart';
import 'package:project_er_operation/app/theme_binder.dart';
import 'package:project_er_operation/logging/logging.dart';
import 'package:project_er_operation/settings/settings.dart';
import 'package:theme_lib/theme_lib.dart';

const userTheme = '''
{
  "schemaVersion": 1,
  "id": "sunset",
  "name": "Sunset",
  "light": { "seedColor": "#E65100" },
  "dark": { "seedColor": "#FF8A65" }
}
''';

void main() {
  late Directory dir;
  late ProviderContainer container;
  late ThemeBinder binder;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('pero_theme');
    final sink = LogSink(dir.path, level: LogLevel.debug);
    container = ProviderContainer(overrides: [
      themeLoggerProvider.overrideWithValue(ThemeLoggerAdapter(AppLogger(sink, 'theme'))),
    ]);
    binder = ThemeBinder(container.read(themeManagerProvider.notifier));
    addTearDown(() {
      container.dispose();
      dir.deleteSync(recursive: true);
    });
  });

  ThemeState state() => container.read(themeManagerProvider);
  File themeFile(String text) => File('${dir.path}${Platform.pathSeparator}user_theme.json')..writeAsStringSync(text);

  test('システム / ダーク / ライト は、theme_lib の既定テーマのモードを切り替える', () {
    expect(binder.apply(AppSettings()..theme = ThemeChoice.dark), isNull);
    expect((state().mode, state().activeId), (ThemeMode.dark, 'default'));
    expect(binder.apply(AppSettings()..theme = ThemeChoice.light), isNull);
    expect(state().mode, ThemeMode.light);
    expect(binder.apply(AppSettings()..theme = ThemeChoice.system), isNull);
    expect(state().mode, ThemeMode.system);
  });

  test('ユーザーテーマ: ファイルのテーマJSONを取り込んで適用する。システムに戻すと取り除く', () {
    final f = themeFile(userTheme);
    final s = AppSettings()
      ..theme = ThemeChoice.user
      ..userThemeFile = f.path;
    expect(binder.apply(s), isNull);
    expect(state().activeId, 'sunset');
    expect(state().active.name, 'Sunset');
    // 取り込んだテーマで ThemeData が作られる
    expect(container.read(lightThemeProvider).colorScheme.brightness, Brightness.light);
    expect(container.read(darkThemeProvider).colorScheme.brightness, Brightness.dark);
    // ユーザーテーマ以外に切り替えると、取り込んだテーマは取り除かれる
    expect(binder.apply(AppSettings()..theme = ThemeChoice.dark), isNull);
    expect(state().themes.containsKey('sunset'), isFalse);
    expect(state().activeId, 'default');
  });

  test('ユーザーテーマ: 同じファイルを再度適用しても重複せず、内容を変えれば反映される', () {
    final f = themeFile(userTheme);
    final s = AppSettings()
      ..theme = ThemeChoice.user
      ..userThemeFile = f.path;
    binder.apply(s);
    f.writeAsStringSync(userTheme.replaceAll('Sunset', 'Sunset 2'));
    expect(binder.apply(s), isNull);
    expect(state().active.name, 'Sunset 2');
    expect(state().themes.keys.where((k) => k == 'sunset').length, 1);
  });

  test('ユーザーテーマが読めないとき(未指定、ファイルなし、不正なJSON)は、システムテーマで表示して理由を返す', () {
    final none = binder.apply(AppSettings()..theme = ThemeChoice.user);
    expect(none, contains('指定されていません'));
    expect((state().activeId, state().mode), ('default', ThemeMode.system));

    final missing = binder.apply(AppSettings()
      ..theme = ThemeChoice.user
      ..userThemeFile = '${dir.path}${Platform.pathSeparator}none.json');
    expect(missing, contains('読み込めません'));

    final bad = binder.apply(AppSettings()
      ..theme = ThemeChoice.user
      ..userThemeFile = themeFile('{"id": "x"}').path);
    expect(bad, contains('読み込めません'));
    expect(state().activeId, 'default');
    // 失敗は theme_lib が [theme_lib] 付きでログに残す(アプリのログへ出る)
    final log = Directory(dir.path).listSync().whereType<File>().where((f) => f.path.endsWith('.log'));
    expect(log.map((f) => f.readAsStringSync()).join(), contains('[theme_lib]'));
  });

  test('ThemeLoggerAdapter: ログレベルの対応とメッセージの出力', () {
    final sink = LogSink(dir.path, level: LogLevel.warn);
    final a = ThemeLoggerAdapter(AppLogger(sink, 'theme'));
    expect(a.level, 4000);
    sink.level = LogLevel.debug;
    expect(a.level, 2000);
    a.warn('注意', ex: 'e1');
    a.fatal('致命的', ex: StateError('x'));
    final text = Directory(dir.path).listSync().whereType<File>().map((f) => f.readAsStringSync()).join();
    expect(text, contains('[WARN] [theme] 注意 : e1'));
    expect(text, contains('[ERROR] [theme] 致命的'));
    expect(a, isA<ILoggerProvider>());
  });
}
