import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../command/command.dart';
import '../common/common.dart';
import '../logging/logging.dart';
import '../model/model.dart';
import '../persistence/persistence.dart';
import '../settings/settings.dart';

/// 編集中のモデルと、それに対する操作の状態(選択、現在のダイアグラム、クリップボード、履歴)を持つ。
/// UIはこのオブジェクトを購読する(Observer パターン)。Undoでモデルの要素が差し替わるため、
/// UIは要素への参照を保持せず、都度 [model] から引き直すこと。
class EditorSession extends ChangeNotifier {
  EditorSession({required this.settings, required this.logger, required this.cache}) {
    _attach(ErModel.empty(
        typeTemplate: settings.typeTable,
        pageSize: settings.paperSize,
        orientation: settings.orientation,
        postPath: defaultPostPath()),
        null);
  }

  AppSettings settings;
  final AppLogger logger;
  final CacheStore cache;

  late CommandHistory history;
  String? filePath;
  final Set<int> selection = {};
  int _currentDiagramId = 0;
  ClipboardData? clipboard;
  int _pasteCount = 0;
  String? statusMessage;

  /// 保存済みかどうか(キャッシュ・バックアップの対象)。
  bool savedOnce = false;
  Timer? _backupTimer;
  int _lastBackupPos = -1;

  ErModel get model => history.model;
  bool get isDirty => history.isDirty;

  String get fileNameForTitle {
    final p = filePath;
    if (p == null) return Strings.untitled;
    return p.substring(p.lastIndexOf(Platform.pathSeparator) + 1);
  }

  Diagram get diagram =>
      model.diagramById(_currentDiagramId) ?? model.diagrams.first;
  int get currentDiagramId => diagram.id;

  set currentDiagramId(int id) {
    _currentDiagramId = id;
    selection.clear();
    notifyListeners();
  }

  EntityLayouter get layouter => EntityLayouter(model, settings.displayOptions);

  String defaultPostPath() {
    final folder = settings.postFolder.isNotEmpty
        ? settings.postFolder
        : '${File(Platform.resolvedExecutable).parent.path}${Platform.pathSeparator}post';
    return '$folder${Platform.pathSeparator}${settings.postFile}';
  }

  void _attach(ErModel m, String? path) {
    history = CommandHistory(CommandContext(m, () => EntityLayouter(m, settings.displayOptions)),
        limit: settings.undoLimit);
    history.onJournal = _journal;
    filePath = path;
    savedOnce = path != null;
    selection.clear();
    clipboard = null;
    _currentDiagramId = m.diagrams.first.id;
    _lastBackupPos = -1;
  }

  void _journal(Map<String, Object?> ev) {
    if (!savedOnce) return;
    try {
      cache.append(ev);
    } on FileSystemException catch (e, s) {
      logger.error('キャッシュへの記録に失敗', e, s);
    }
  }

  void notify(String? message) {
    statusMessage = message;
    notifyListeners();
  }

  // ---- コマンドの実行 ----

  /// コマンドを実行する。失敗したときは理由をステータスに出して false を返す。
  bool run(ModelCommand cmd) {
    try {
      history.execute(cmd);
    } on CommandException catch (e) {
      statusMessage = e.message;
      notifyListeners();
      return false;
    }
    _pruneSelection();
    statusMessage = null;
    notifyListeners();
    return true;
  }

  void undo() {
    history.undo();
    _pruneSelection();
    notifyListeners();
  }

  void redo() {
    history.redo();
    _pruneSelection();
    notifyListeners();
  }

  void _pruneSelection() {
    selection.removeWhere((id) => model.entityById(id) == null && model.relationshipById(id) == null);
    if (model.diagramById(_currentDiagramId) == null) _currentDiagramId = model.diagrams.first.id;
  }

  void setSelection(Iterable<int> ids) {
    selection
      ..clear()
      ..addAll(ids);
    notifyListeners();
  }

  /// ズーム・スクロールはUndoの対象外(9.1-6)。
  void setView({double? zoom, double? scrollX, double? scrollY}) {
    final v = diagram.view;
    if (zoom != null) v.zoom = zoom.clamp(0.25, 4.0);
    if (scrollX != null) v.scrollX = scrollX;
    if (scrollY != null) v.scrollY = scrollY;
    notifyListeners();
  }

  // ---- クリップボード(4.2-13) ----
  void copySelection() {
    final ids = selection.where((id) => model.entityById(id) != null).toList();
    if (ids.isEmpty) return;
    clipboard = ClipboardData.fromSelection(model, diagram, ids);
    _pasteCount = 0;
    notifyListeners();
  }

  bool paste() {
    final c = clipboard;
    if (c == null || c.isEmpty) return false;
    _pasteCount++;
    final cmd = PasteEntitiesCommand(diagramId: diagram.id, data: c, pasteCount: _pasteCount);
    final ok = run(cmd);
    if (ok) setSelection(cmd.createdIds);
    return ok;
  }

  void duplicateSelection() {
    copySelection();
    paste();
  }

  // ---- ファイル ----

  /// 新しいモデルに切り替える(4.1-1)。
  void newModel() {
    _attach(
        ErModel.empty(
            typeTemplate: settings.typeTable,
            pageSize: settings.paperSize,
            orientation: settings.orientation,
            postPath: defaultPostPath()),
        null);
    cache.clear();
    notify(null);
  }

  /// ファイルを開く。失敗時はエラー文言(と修復内容)を返す。
  Future<LoadResult> open(String path) async {
    final r = await PeroFile.open(path);
    final m = r.model;
    if (m == null) {
      logger.error('ファイルを開けません: $path / ${r.error}');
      return r;
    }
    if (!r.repairs.isEmpty) logger.warn('整合性確認で修復: $path\n${r.repairs.summary(maxLines: 50)}');
    logger.info('ファイルを開きました: $path');
    _attach(m, path);
    cache.clear();
    cache.writeBase(m, path, baseText: CacheStore.baseTextOf(m));
    _rememberFile(path);
    notify(null);
    return r;
  }

  /// 復元したモデルを、未保存の状態で開く(9.2-4)。
  void openRecovered(ErModel m, String? path) {
    _attach(m, path);
    savedOnce = path != null;
    // 復元後の内容は「保存済みからの変更あり」の状態にする。
    history.clear();
    history.markUnsaved();
    notify(null);
  }

  /// 保存。成功したら未保存状態を解除し、キャッシュの基点を更新する(4.1-3)。
  Future<SaveResult> save(String path) async {
    final r = await PeroFile.save(model, path);
    if (!r.isOk) {
      logger.error('保存に失敗: $path / ${r.error}');
      return r;
    }
    if (!r.repairs.isEmpty) logger.warn('保存時の整合性確認で修復\n${r.repairs.summary(maxLines: 50)}');
    filePath = path;
    savedOnce = true;
    history.markSaved();
    try {
      cache.writeBase(model, path, baseText: CacheStore.baseTextOf(model));
    } on FileSystemException catch (e, s) {
      logger.error('キャッシュの更新に失敗', e, s);
    }
    _rememberFile(path);
    logger.info('保存しました: $path');
    notify(null);
    return r;
  }

  void _rememberFile(String path) {
    settings.lastFolder = path.substring(0, path.lastIndexOf(Platform.pathSeparator));
    settings.recentFiles
      ..remove(path)
      ..insert(0, path);
    if (settings.recentFiles.length > 20) settings.recentFiles.removeRange(20, settings.recentFiles.length);
  }

  // ---- バックアップ(9.3) ----

  void startBackupTimer() {
    _backupTimer?.cancel();
    if (!settings.backupEnabled) return;
    _backupTimer = Timer.periodic(Duration(minutes: settings.backupCycleMinutes), (_) => backupNow());
  }

  /// 前回のバックアップ以降に変更があれば、保存済みファイルのモデルをバックアップする。
  void backupNow() {
    final p = filePath;
    if (!settings.backupEnabled || !savedOnce || p == null) return;
    final pos = history.revision;
    if (pos == _lastBackupPos) return;
    try {
      final dir = settings.backupFolder.isNotEmpty ? settings.backupFolder : defaultBackupDir();
      final name = p.substring(p.lastIndexOf(Platform.pathSeparator) + 1).replaceAll(RegExp(r'\.pero$', caseSensitive: false), '');
      final now = DateTime.now();
      String t(int n, [int w = 2]) => n.toString().padLeft(w, '0');
      final stamp = '${t(now.year, 4)}${t(now.month)}${t(now.day)}_${t(now.hour)}${t(now.minute)}${t(now.second)}';
      Directory(dir).createSync(recursive: true);
      File('$dir${Platform.pathSeparator}${name}_$stamp.pero')
          .writeAsStringSync(PeroEncoder.encode(model));
      _lastBackupPos = pos;
      purgeOldBackups(dir);
    } on FileSystemException catch (e, s) {
      logger.error('バックアップに失敗', e, s);
      notify('バックアップに失敗しました: ${e.message}');
    }
  }

  static String defaultBackupDir() {
    final base = Platform.environment['LOCALAPPDATA'] ?? Directory.systemTemp.path;
    return '$base${Platform.pathSeparator}PERO${Platform.pathSeparator}backup';
  }

  /// 保存期間を超えたバックアップを削除する(9.3-4)。
  void purgeOldBackups(String dir) {
    final limit = DateTime.now().subtract(Duration(days: settings.backupRetentionDays));
    final d = Directory(dir);
    if (!d.existsSync()) return;
    for (final f in d.listSync().whereType<File>()) {
      if (f.path.toLowerCase().endsWith('.pero') && f.lastModifiedSync().isBefore(limit)) {
        try {
          f.deleteSync();
        } on FileSystemException {
          // 削除に失敗しても継続する。
        }
      }
    }
  }

  @override
  void dispose() {
    _backupTimer?.cancel();
    super.dispose();
  }
}
