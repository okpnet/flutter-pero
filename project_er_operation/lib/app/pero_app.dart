// window_manager 0.6 の旧API(legacy)を使う。新APIへの移行は今後の課題。
// ignore_for_file: deprecated_member_use

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/legacy.dart';

import '../common/common.dart';
import '../logging/logging.dart';
import '../persistence/persistence.dart';
import '../session/session.dart';
import '../settings/settings.dart';
import 'main_screen.dart';

/// アプリのバージョン。
const String appVersion = '0.1.0';

/// 起動処理: 設定の読込、ウィンドウの初期化、セッションの生成。
Future<void> startApp(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  final store = SettingsStore();
  final (settings, settingsNotice) = store.load();

  final sink = LogSink(LogSink.defaultDir(), level: settings.logLevel, retentionDays: settings.logRetentionDays);
  final container = ProviderContainer(overrides: [logSinkProvider.overrideWithValue(sink)]);
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

  final localAppData = Platform.environment['LOCALAPPDATA'] ?? Directory.systemTemp.path;
  final cache = CacheStore('$localAppData${Platform.pathSeparator}PERO');
  final session = EditorSession(settings: settings, logger: container.read(loggerProvider('session')), cache: cache);
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
      child: PeroApp(session: session, store: store, initialFile: peroPathFromArgs(args)),
    ),
  ));
}

class PeroApp extends StatefulWidget {
  const PeroApp({super.key, required this.session, required this.store, this.initialFile});
  final EditorSession session;
  final SettingsStore store;
  final String? initialFile;

  @override
  State<PeroApp> createState() => _PeroAppState();
}

class _PeroAppState extends State<PeroApp> {
  late AppSettings _settings = widget.session.settings;

  void _applied(AppSettings s) {
    final sess = widget.session;
    sess.settings = s;
    sess.history.limit = s.undoLimit;
    sess.logger.sink
      ..level = s.logLevel
      ..retentionDays = s.logRetentionDays;
    sess.startBackupTimer();
    setState(() => _settings = s);
    sess.notify(null);
  }

  ThemeMode get _mode => switch (_settings.theme) {
        ThemeChoice.system => ThemeMode.system,
        ThemeChoice.dark => ThemeMode.dark,
        ThemeChoice.light => ThemeMode.light,
      };

  ThemeData _theme(Brightness b) => ThemeData(
        colorSchemeSeed: const Color(0xFF1F4E79),
        brightness: b,
        useMaterial3: true,
        fontFamily: _settings.fontFamily.isEmpty ? null : _settings.fontFamily,
        visualDensity: VisualDensity.compact,
      );

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: Strings.appName,
      debugShowCheckedModeBanner: false,
      themeMode: _mode,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      home: MainScreen(
        session: widget.session,
        settingsStore: widget.store,
        onSettingsApplied: _applied,
        initialFile: widget.initialFile,
      ),
    );
  }
}
