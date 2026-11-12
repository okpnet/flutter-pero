import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:project_er_operation/logging/logging.dart';
import 'package:project_er_operation/model/model.dart';
import 'package:project_er_operation/settings/settings.dart';

void main() {
  late Directory exeDir, appData;
  setUp(() {
    exeDir = Directory.systemTemp.createTempSync('pero_exe');
    appData = Directory.systemTemp.createTempSync('pero_appdata');
    addTearDown(() {
      exeDir.deleteSync(recursive: true);
      appData.deleteSync(recursive: true);
    });
  });
  SettingsStore store() => SettingsStore(exeDir: exeDir.path, appDataDir: appData.path);

  test('既定値は仕様(10.2)のとおり', () {
    final s = AppSettings();
    expect(s.backupEnabled, isTrue);
    expect((s.backupCycleMinutes, s.backupRetentionDays), (5, 5));
    expect(s.recentFileCount, 10);
    expect((s.postFile, s.postTimeoutSeconds), ('postgresql.post', 30));
    expect((s.generatedExtension, s.crlf), ('sql', true));
    expect((s.paperSize, s.orientation, s.dpi), (PageSize.a3, Orientation.landscape, 300));
    expect((s.alignSpace, s.gridSnap, s.undoLimit), (40, 10, 100));
    expect((s.fontSize, s.headerScale, s.normalScale, s.supplementScale), (12, 1.2, 1.0, 0.8));
    expect(s.nameFormat, r'^[A-Za-z_][A-Za-z0-9_]*$');
    expect((s.logLevel, s.logRetentionDays), (LogLevel.info, 7));
    expect(s.rightPaneRatio, 0.25);
    expect(s.typeTable.length, standardTypes().length);
  });

  test('保存→読込で全項目が復元される(実行ファイル直下)', () {
    final s = AppSettings()
      ..backupEnabled = false
      ..dpi = 150
      ..theme = ThemeChoice.dark
      ..colComment = true
      ..recentFiles = ['a.pero', 'b.pero']
      ..windowWidth = 1500
      ..rightPaneRatio = 0.3;
    expect(store().save(s), isNull);
    expect(File('${exeDir.path}/settings.json').existsSync(), isTrue);
    expect(File('${exeDir.path}/settings.json.tmp').existsSync(), isFalse);
    final (r, notice) = store().load();
    expect(notice, isNull);
    expect(r.toJson(), s.toJson());
  });

  test('範囲外・不正な値は既定値のまま(例外にしない)', () {
    final r = AppSettings.fromJson({
      'backup': {'cycleMinutes': 999, 'enabled': 'x'},
      'canvas': {'dpi': 5, 'paperSize': 'B9'},
      'display': {'headerLogical': false, 'headerPhysical': false},
    });
    expect(r.backupCycleMinutes, 5);
    expect(r.backupEnabled, isTrue);
    expect(r.dpi, 300);
    expect(r.paperSize, PageSize.a3);
    expect(r.headerLogical || r.headerPhysical, isTrue); // 少なくとも一方はON
  });

  test('標準型が欠けた型テーブルは標準型を補う', () {
    final r = AppSettings.fromJson({'types': []});
    expect(r.typeTable.length, standardTypes().length);
  });

  test('破損した設定ファイルは既定値で起動し、.broken に退避する', () {
    File('${exeDir.path}/settings.json').writeAsStringSync('{ broken');
    final (s, notice) = store().load();
    expect(notice, isNotNull);
    expect(s.toJson(), AppSettings().toJson());
    expect(File('${exeDir.path}/settings.json.broken').existsSync(), isTrue);
  });

  test('読込は両方を探し、実行ファイル直下を優先する', () {
    File('${appData.path}/settings.json').writeAsStringSync('{"canvas":{"dpi":111}}');
    expect(store().load().$1.dpi, 111);
    File('${exeDir.path}/settings.json').writeAsStringSync('{"canvas":{"dpi":222}}');
    expect(store().load().$1.dpi, 222);
  });

  test('実行ファイルの場所に書き込めないときは APPDATA に保存して通知する', () {
    final blocked = SettingsStore(
        exeDir: '${exeDir.path}/no_such/\u0000bad', appDataDir: appData.path);
    final notice = blocked.save(AppSettings()..dpi = 123);
    expect(notice, contains('保存しました'));
    expect(File('${appData.path}/settings.json').existsSync(), isTrue);
  });

  test('ログ: 機能名付きで pero_yyyyMMdd.log に出力し、レベルで絞る', () {
    final dir = Directory.systemTemp.createTempSync('pero_log');
    addTearDown(() => dir.deleteSync(recursive: true));
    final sink = LogSink(dir.path, level: LogLevel.warn);
    AppLogger(sink, 'persistence')
      ..error('壊れた')
      ..info('出ない');
    final files = dir.listSync().whereType<File>().toList();
    expect(files.single.path, matches(r'pero_\d{8}\.log$'));
    final text = files.single.readAsStringSync();
    expect(text, contains('[ERROR] [persistence] 壊れた'));
    expect(text, isNot(contains('出ない')));
  });
}
