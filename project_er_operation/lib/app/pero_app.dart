// window_manager 0.6 の旧API(legacy)を使う。新APIへの移行は今後の課題。
// ignore_for_file: deprecated_member_use

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:theme_lib/theme_lib.dart';
import 'package:window_manager/legacy.dart';

import '../common/common.dart';
import '../logging/logging.dart';
import '../persistence/persistence.dart';
import '../session/session.dart';
import '../settings/settings.dart';
import 'main_screen.dart';
import 'single_instance.dart';
import 'theme_binder.dart';

/// アプリのバージョン。
const String appVersion = '0.1.0';

/// 起動処理: 設定の読込、ウィンドウの初期化、セッションの生成。
Future<void> startApp(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  // 単一インスタンス(2-14): 既に起動していれば、引数(ファイルパス)を渡して終了する。
  final appDir = '${Platform.environment['LOCALAPPDATA'] ?? Directory.systemTemp.path}${Platform.pathSeparator}PERO';
  SingleInstance? single;
  if (Platform.environment['PERO_ALLOW_MULTIPLE'] != '1') {
    single = await SingleInstance.acquire(dir: appDir, args: args);
    if (single == null) exit(0);
  }
  await windowManager.ensureInitialized();

  final store = SettingsStore();
  final (settings, settingsNotice) = store.load();

  final sink = LogSink(LogSink.defaultDir(), level: settings.logLevel, retentionDays: settings.logRetentionDays);
  // 共通ライブラリ(theme_lib)のログを、アプリのログ(機能名 theme)へつなぐ。
  final container = ProviderContainer(overrides: [
    logSinkProvider.overrideWithValue(sink),
    themeLoggerProvider.overrideWithValue(ThemeLoggerAdapter(AppLogger(sink, 'theme'))),
  ]);
  final logger = container.read(loggerProvider('app'));
  FlutterError.onError = (d) {
    logger.error('Flutterの例外: ${d.exceptionAsString()}', d.exception, d.stack);
    FlutterError.presentError(d);
  };
  ui.PlatformDispatcher.instance.onError = (e, s) {
    logger.error('未処理の例外', e, s);
    return true;
  };
  logger.info('起動 v$appVersion');

  final cache = CacheStore(appDir);
  final session = EditorSession(settings: settings, logger: container.read(loggerProvider('session')), cache: cache);
  session.rescanPosts();
  if (settingsNotice != null) {
    logger.warn(settingsNotice);
    session.statusMessage = settingsNotice;
  }

  final width = settings.windowWidth ?? 1280;
  final height = settings.windowHeight ?? 800;
  final options = WindowOptions(
    size: Size(width < 1024 ? 1024 : width, height < 700 ? 700 : height),
    minimumSize: const Size(1024, 700),
    center: settings.windowX == null,
    title: Strings.appName,
  );
  await windowManager.waitUntilReadyToShow(options, () async {
    if (settings.windowX != null && settings.windowY != null) {
      await windowManager.setPosition(Offset(settings.windowX!, settings.windowY!));
    }
    if (settings.windowMaximized) await windowManager.maximize();
    await windowManager.show();
    await windowManager.focus();
  });

  runApp(UncontrolledProviderScope(
    container: container,
    child: ProviderScope(
      overrides: [
        editorSessionProvider.overrideWithValue(session),
        settingsStoreProvider.overrideWithValue(store),
      ],
      child: PeroApp(session: session, store: store, initialFile: peroPathFromArgs(args), singleInstance: single),
    ),
  ));
}

class PeroApp extends ConsumerStatefulWidget {
  const PeroApp({super.key, required this.session, required this.store, this.initialFile, this.singleInstance});
  final EditorSession session;
  final SettingsStore store;
  final String? initialFile;
  final SingleInstance? singleInstance;

  @override
  ConsumerState<PeroApp> createState() => _PeroAppState();
}

class _PeroAppState extends ConsumerState<PeroApp> {
  late AppSettings _settings = widget.session.settings;
  late final ThemeBinder _themeBinder = ThemeBinder(ref.read(themeManagerProvider.notifier));

  @override
  void initState() {
    super.initState();
    // 起動時の設定を反映する(ビルド中にプロバイダを変更しないよう、最初のフレームの後で行う)。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final err = _applyTheme();
      if (err != null) widget.session.notify(err);
    });
  }

  /// 色テーマを反映する。失敗したときは理由を返す(ログにも記録する)。
  String? _applyTheme() {
    final err = _themeBinder.apply(_settings);
    if (err != null) widget.session.logger.warn(err);
    return err;
  }

  void _applied(AppSettings s) {
    final sess = widget.session;
    sess.settings = s;
    sess.history.limit = s.undoLimit;
    sess.logger.sink
      ..level = s.logLevel
      ..retentionDays = s.logRetentionDays;
    sess.startBackupTimer();
    setState(() => _settings = s);
    sess.rescanPosts();
    String? notice;
    if (!sess.postCatalog.hasValid) {
      notice = '使えるポストファイルがありません: ${sess.postFolderPath()}';
      sess.logger.warn(notice);
    }
    sess.notify(_applyTheme() ?? notice);
  }

  /// theme_lib のテーマに、アプリ固有の設定(フォント、コンパクトな密度)を重ねる。
  ThemeData _themed(ThemeData base) {
    final family = _settings.fontFamily;
    return base.copyWith(
      visualDensity: VisualDensity.compact,
      textTheme: family.isEmpty ? null : base.textTheme.apply(fontFamily: family),
      primaryTextTheme: family.isEmpty ? null : base.primaryTextTheme.apply(fontFamily: family),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: Strings.appName,
      debugShowCheckedModeBanner: false,
      themeMode: ref.watch(themeModeProvider),
      theme: _themed(ref.watch(lightThemeProvider)),
      darkTheme: _themed(ref.watch(darkThemeProvider)),
      home: MainScreen(
        session: widget.session,
        settingsStore: widget.store,
        onSettingsApplied: _applied,
        initialFile: widget.initialFile,
        singleInstance: widget.singleInstance,
      ),
    );
  }
}
