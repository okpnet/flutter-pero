import 'dart:convert';
import 'dart:io';

import '../logging/logging.dart';
import '../model/model.dart';
import '../persistence/persistence.dart';

const int settingsVersion = 1;

/// 色テーマ(10.2)。
enum ThemeChoice { system, dark, light }

/// アプリの設定(10.2)。自動保存の項目(分割割合、ウィンドウ、フォルダ、最近使ったファイル)を含む。
class AppSettings {
  AppSettings();

  // バックアップ
  bool backupEnabled = true;
  String backupFolder = '';
  int backupCycleMinutes = 5;
  int backupRetentionDays = 5;
  // ファイル
  int recentFileCount = 10;
  // ポストファイル
  String postFolder = '';
  String postFile = 'postgresql.post';
  int postTimeoutSeconds = 30;
  // 生成
  String generatedExtension = 'sql';
  bool crlf = true;
  String pkPrefix = '';
  String pkSuffix = '_pk';
  bool dropBeforeCreate = false;
  // キャンバス
  PageSize paperSize = PageSize.a3;
  Orientation orientation = Orientation.landscape;
  int dpi = 300;
  double alignSpace = 40;
  double gridSnap = 10;
  int undoLimit = 100;
  // 表示
  ThemeChoice theme = ThemeChoice.system;
  bool headerLogical = true;
  bool headerPhysical = true;
  bool colLogical = true;
  bool colPhysical = true;
  bool colType = true;
  bool colDefault = false;
  bool colComment = false;
  String nameFormat = r'^[A-Za-z_][A-Za-z0-9_]*$';
  // 文字
  double fontSize = 12;
  String fontFamily = '';
  double headerScale = 1.2;
  double normalScale = 1.0;
  double supplementScale = 0.8;
  // 型
  List<DataType> typeTable = standardTypes();
  // ログ
  LogLevel logLevel = LogLevel.info;
  int logRetentionDays = 7;
  // 自動保存の項目
  double rightPaneRatio = 0.25;
  double propsRatio = 0.5;
  double? windowX, windowY, windowWidth, windowHeight;
  bool windowMaximized = false;
  String lastFolder = '';
  List<String> recentFiles = [];

  PkNaming get pkNaming => PkNaming(prefix: pkPrefix, suffix: pkSuffix);

  DisplayOptions get displayOptions => DisplayOptions(
        headerLogical: headerLogical,
        headerPhysical: headerPhysical,
        colLogical: colLogical,
        colPhysical: colPhysical,
        colType: colType,
        colDefault: colDefault,
        colComment: colComment,
        fontSize: fontSize,
        headerScale: headerScale,
        normalScale: normalScale,
        supplementScale: supplementScale,
      );

  AppSettings copy() => AppSettings.fromJson(toJson());

  Map<String, Object?> toJson() => {
        'settingsVersion': settingsVersion,
        'backup': {
          'enabled': backupEnabled,
          'folder': backupFolder,
          'cycleMinutes': backupCycleMinutes,
          'retentionDays': backupRetentionDays,
        },
        'file': {'recentFileCount': recentFileCount},
        'post': {'folder': postFolder, 'file': postFile, 'timeoutSeconds': postTimeoutSeconds},
        'generation': {
          'extension': generatedExtension,
          'crlf': crlf,
          'pkPrefix': pkPrefix,
          'pkSuffix': pkSuffix,
          'dropBeforeCreate': dropBeforeCreate,
        },
        'canvas': {
          'paperSize': paperSize.wire,
          'orientation': orientation.wire,
          'dpi': dpi,
          'alignSpace': alignSpace,
          'gridSnap': gridSnap,
          'undoLimit': undoLimit,
        },
        'display': {
          'theme': theme.name,
          'headerLogical': headerLogical,
          'headerPhysical': headerPhysical,
          'colLogical': colLogical,
          'colPhysical': colPhysical,
          'colType': colType,
          'colDefault': colDefault,
          'colComment': colComment,
          'nameFormat': nameFormat,
        },
        'font': {
          'size': fontSize,
          'family': fontFamily,
          'headerScale': headerScale,
          'normalScale': normalScale,
          'supplementScale': supplementScale,
        },
        'types': typeTable.map(PeroEncoder.typeToMap).toList(),
        'log': {'level': logLevel.name, 'retentionDays': logRetentionDays},
        'auto': {
          'rightPaneRatio': rightPaneRatio,
          'propsRatio': propsRatio,
          'windowX': windowX,
          'windowY': windowY,
          'windowWidth': windowWidth,
          'windowHeight': windowHeight,
          'windowMaximized': windowMaximized,
          'lastFolder': lastFolder,
          'recentFiles': recentFiles,
        },
      };

  /// JSONから復元する。範囲外・不正な値は既定値のまま(例外は投げない)。
  factory AppSettings.fromJson(Map<String, Object?> j) {
    final s = AppSettings();
    Map<String, Object?> sec(String k) =>
        j[k] is Map ? Map<String, Object?>.from(j[k] as Map) : <String, Object?>{};
    bool b(Map<String, Object?> m, String k, bool d) => m[k] is bool ? m[k] as bool : d;
    int i(Map<String, Object?> m, String k, int d, int lo, int hi) {
      final v = m[k];
      return v is num && v >= lo && v <= hi ? v.toInt() : d;
    }

    double f(Map<String, Object?> m, String k, double d, double lo, double hi) {
      final v = m[k];
      return v is num && v >= lo && v <= hi ? v.toDouble() : d;
    }

    String str(Map<String, Object?> m, String k, String d) => m[k] is String ? m[k] as String : d;

    final bk = sec('backup');
    s.backupEnabled = b(bk, 'enabled', s.backupEnabled);
    s.backupFolder = str(bk, 'folder', s.backupFolder);
    s.backupCycleMinutes = i(bk, 'cycleMinutes', s.backupCycleMinutes, 1, 60);
    s.backupRetentionDays = i(bk, 'retentionDays', s.backupRetentionDays, 1, 180);
    s.recentFileCount = i(sec('file'), 'recentFileCount', s.recentFileCount, 0, 20);
    final po = sec('post');
    s.postFolder = str(po, 'folder', s.postFolder);
    s.postFile = str(po, 'file', s.postFile);
    s.postTimeoutSeconds = i(po, 'timeoutSeconds', s.postTimeoutSeconds, 1, 300);
    final g = sec('generation');
    s.generatedExtension = str(g, 'extension', s.generatedExtension);
    s.crlf = b(g, 'crlf', s.crlf);
    s.pkPrefix = str(g, 'pkPrefix', s.pkPrefix);
    s.pkSuffix = str(g, 'pkSuffix', s.pkSuffix);
    s.dropBeforeCreate = b(g, 'dropBeforeCreate', s.dropBeforeCreate);
    final c = sec('canvas');
    s.paperSize = enumFromWire(PageSize.values, c['paperSize']) ?? s.paperSize;
    s.orientation = enumFromWire(Orientation.values, c['orientation']) ?? s.orientation;
    s.dpi = i(c, 'dpi', s.dpi, 100, 600);
    s.alignSpace = f(c, 'alignSpace', s.alignSpace, 10, 200);
    s.gridSnap = f(c, 'gridSnap', s.gridSnap, 0, 50);
    s.undoLimit = i(c, 'undoLimit', s.undoLimit, 10, 1000);
    final d = sec('display');
    s.theme = ThemeChoice.values.where((e) => e.name == d['theme']).firstOrNull ?? s.theme;
    s.headerLogical = b(d, 'headerLogical', s.headerLogical);
    s.headerPhysical = b(d, 'headerPhysical', s.headerPhysical);
    if (!s.headerLogical && !s.headerPhysical) s.headerLogical = s.headerPhysical = true;
    s.colLogical = b(d, 'colLogical', s.colLogical);
    s.colPhysical = b(d, 'colPhysical', s.colPhysical);
    s.colType = b(d, 'colType', s.colType);
    s.colDefault = b(d, 'colDefault', s.colDefault);
    s.colComment = b(d, 'colComment', s.colComment);
    s.nameFormat = str(d, 'nameFormat', s.nameFormat);
    final ft = sec('font');
    s.fontSize = f(ft, 'size', s.fontSize, 8, 32);
    s.fontFamily = str(ft, 'family', s.fontFamily);
    s.headerScale = f(ft, 'headerScale', s.headerScale, 0.5, 3);
    s.normalScale = f(ft, 'normalScale', s.normalScale, 0.5, 3);
    s.supplementScale = f(ft, 'supplementScale', s.supplementScale, 0.3, 3);
    if (j['types'] is List) {
      final ts = <DataType>[];
      for (final x in j['types'] as List) {
        final t = PeroDecoder.typeFromMap(x);
        if (t != null) ts.add(t);
      }
      // 標準型が不足していれば補う(9.4-9と同じ考え方)。
      for (final st in standardTypes()) {
        if (!ts.any((t) => t.id == st.id)) ts.add(st);
      }
      s.typeTable = ts;
    }
    final lg = sec('log');
    s.logLevel = LogLevel.values.where((e) => e.name == lg['level']).firstOrNull ?? s.logLevel;
    s.logRetentionDays = i(lg, 'retentionDays', s.logRetentionDays, 1, 90);
    final a = sec('auto');
    s.rightPaneRatio = f(a, 'rightPaneRatio', s.rightPaneRatio, 0.1, 0.6);
    s.propsRatio = f(a, 'propsRatio', s.propsRatio, 0.1, 0.9);
    double? nd(String k) => a[k] is num ? (a[k] as num).toDouble() : null;
    s.windowX = nd('windowX');
    s.windowY = nd('windowY');
    s.windowWidth = nd('windowWidth');
    s.windowHeight = nd('windowHeight');
    s.windowMaximized = b(a, 'windowMaximized', false);
    s.lastFolder = str(a, 'lastFolder', '');
    s.recentFiles = [
      if (a['recentFiles'] is List)
        for (final x in a['recentFiles'] as List)
          if (x is String) x
    ];
    return s;
  }
}

/// 設定ファイル `settings.json` の読み書き(10.1)。
/// 実行ファイル直下に保存し、書き込めない場合は `%APPDATA%\PERO\` に保存する。
class SettingsStore {
  SettingsStore({String? exeDir, String? appDataDir})
      : exeDir = exeDir ?? File(Platform.resolvedExecutable).parent.path,
        appDataDir = appDataDir ??
            '${Platform.environment['APPDATA'] ?? Directory.systemTemp.path}${Platform.pathSeparator}PERO';

  final String exeDir;
  final String appDataDir;

  File get _exeFile => File('$exeDir${Platform.pathSeparator}settings.json');
  File get _appDataFile => File('$appDataDir${Platform.pathSeparator}settings.json');

  /// 読込。両方を探し、実行ファイル直下を優先する。破損時は既定値と通知メッセージを返す。
  (AppSettings, String?) load() {
    final file = _exeFile.existsSync()
        ? _exeFile
        : (_appDataFile.existsSync() ? _appDataFile : null);
    if (file == null) return (AppSettings(), null);
    try {
      final j = jsonDecode(file.readAsStringSync(encoding: utf8));
      if (j is! Map) throw const FormatException('ルートがオブジェクトではありません');
      return (AppSettings.fromJson(Map<String, Object?>.from(j)), null);
    } on Object catch (e) {
      try {
        file.copySync('${file.path}.broken');
      } on FileSystemException {
        // 退避失敗は無視する。
      }
      return (AppSettings(), '設定ファイルを読み込めないため既定値で起動しました($e)');
    }
  }

  /// 保存(一時ファイルに書いてからリネーム)。通知メッセージ(あれば)を返す。失敗しても動作は継続する。
  String? save(AppSettings s) {
    final text = '${const JsonEncoder.withIndent('  ').convert(s.toJson())}\n';
    String? tryWrite(File f) {
      try {
        f.parent.createSync(recursive: true);
        final tmp = File('${f.path}.tmp');
        tmp.writeAsStringSync(text, encoding: utf8, flush: true);
        tmp.renameSync(f.path);
        return null;
      } on FileSystemException catch (e) {
        return e.message;
      }
    }

    if (tryWrite(_exeFile) == null) return null;
    final err = tryWrite(_appDataFile);
    if (err == null) return '設定を ${_appDataFile.path} に保存しました(実行ファイルの場所に書き込めません)';
    return '設定を保存できませんでした: $err';
  }
}
