import 'dart:convert';
import 'dart:io';

import '../model/model.dart';
import 'pero_encoder.dart';

/// キャッシュから読み出した内容。
class CacheState {
  CacheState(
      {required this.modelId,
      required this.filePath,
      required this.savedOnce,
      required this.appVersion,
      required this.baseText,
      required this.journal});
  final int modelId;
  final String? filePath;
  final bool savedOnce;
  final String appVersion;
  final String baseText;

  /// `commands.jsonl` の各行(exec / undo / redo)。
  final List<Map<String, Object?>> journal;
}

/// 異常終了からの復旧のためのキャッシュ(9.2)。保存先は `%LOCALAPPDATA%\PERO\cache\`。
/// 編集中のモデルは常に1つなので、1セットだけ持つ。
class CacheStore {
  CacheStore(String baseDir)
      : dir = Directory('$baseDir${Platform.pathSeparator}cache'),
        _lock = File('$baseDir${Platform.pathSeparator}session.lock');

  final Directory dir;
  final File _lock;

  File get _meta => File('${dir.path}${Platform.pathSeparator}meta.json');
  File get _base => File('${dir.path}${Platform.pathSeparator}base.pero');
  File get _commands => File('${dir.path}${Platform.pathSeparator}commands.jsonl');

  // ---- セッションロック(9.2-4) ----
  bool get previousSessionCrashed => _lock.existsSync();

  void createSessionLock() {
    _lock.parent.createSync(recursive: true);
    _lock.writeAsStringSync('${DateTime.now().toIso8601String()}\n');
  }

  void deleteSessionLock() {
    if (_lock.existsSync()) _lock.deleteSync();
  }

  // ---- 記録(9.2-3) ----
  /// 保存に成功したとき: `base.pero` を更新し、`commands.jsonl` を空にする。
  void writeBase(ErModel model, String filePath, {required String baseText}) {
    dir.createSync(recursive: true);
    _meta.writeAsStringSync(jsonEncode({
      'modelId': model.id,
      'filePath': filePath,
      'savedOnce': true,
      'appVersion': model.appVersion,
    }));
    _base.writeAsStringSync(baseText, encoding: utf8, flush: true);
    _commands.writeAsStringSync('', flush: true);
  }

  /// 実行したコマンド、Undo、Redoを1行ずつ追記する。
  void append(Map<String, Object?> event) {
    if (!_meta.existsSync()) return; // 一度も保存していないモデルは記録しない
    _commands.writeAsStringSync('${jsonEncode(event)}\n', mode: FileMode.append, flush: true);
  }

  /// 書き出し用のテキスト。
  static String baseTextOf(ErModel m) => PeroEncoder.encode(m);

  /// キャッシュを読む。無い、または破損しているときは null(破損は [corrupt] で通知)。
  CacheState? read({void Function(String)? corrupt}) {
    if (!_meta.existsSync() || !_base.existsSync()) return null;
    try {
      final meta = jsonDecode(_meta.readAsStringSync(encoding: utf8)) as Map<String, dynamic>;
      final lines = _commands.existsSync()
          ? _commands.readAsLinesSync(encoding: utf8).where((l) => l.trim().isNotEmpty)
          : const <String>[];
      return CacheState(
        modelId: meta['modelId'] as int,
        filePath: meta['filePath'] as String?,
        savedOnce: meta['savedOnce'] as bool? ?? false,
        appVersion: meta['appVersion'] as String? ?? '',
        baseText: _base.readAsStringSync(encoding: utf8),
        journal: [for (final l in lines) Map<String, Object?>.from(jsonDecode(l) as Map)],
      );
    } on Object catch (e) {
      corrupt?.call('$e');
      return null;
    }
  }

  /// 復元の提案の対象か(`savedOnce` が真で `commands.jsonl` が1行以上)。
  bool isRecoverable(CacheState? s) => s != null && s.savedOnce && s.journal.isNotEmpty;

  void clear() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  }
}
