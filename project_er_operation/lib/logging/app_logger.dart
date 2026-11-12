import 'dart:io';

/// ログレベル(10.2)。
enum LogLevel { error, warn, info, debug }

/// ログ出力(11.5)。機能名(11.1-4のディレクトリ名)をロガー名にして、出力元を切り分ける。
/// 出力先は `%LOCALAPPDATA%\PERO\logs\pero_yyyyMMdd.log`。
class LogSink {
  LogSink(this.dir, {this.level = LogLevel.info, this.retentionDays = 7});

  final String dir;
  LogLevel level;
  int retentionDays;

  static String defaultDir() {
    final base = Platform.environment['LOCALAPPDATA'] ?? Directory.systemTemp.path;
    return '$base${Platform.pathSeparator}PERO${Platform.pathSeparator}logs';
  }

  void write(LogLevel l, String logger, String message, [Object? error, StackTrace? stack]) {
    if (l.index > level.index) return;
    try {
      Directory(dir).createSync(recursive: true);
      final now = DateTime.now();
      final y = now.year.toString().padLeft(4, '0');
      final mo = now.month.toString().padLeft(2, '0');
      final d = now.day.toString().padLeft(2, '0');
      final file = File('$dir${Platform.pathSeparator}pero_$y$mo$d.log');
      String p2(int n) => n.toString().padLeft(2, '0');
      final ts = '$y-$mo-$d ${p2(now.hour)}:${p2(now.minute)}:${p2(now.second)}';
      final buf = StringBuffer('$ts [${l.name.toUpperCase()}] [$logger] $message');
      if (error != null) buf.write(' : $error');
      if (stack != null) buf.write('\n$stack');
      buf.writeln();
      file.writeAsStringSync(buf.toString(), mode: FileMode.append);
    } on FileSystemException {
      // ログの書込み失敗でアプリの動作を止めない。
    }
  }

  /// 保持日数を超えたログを削除する。
  void purgeOld() {
    try {
      final d = Directory(dir);
      if (!d.existsSync()) return;
      final limit = DateTime.now().subtract(Duration(days: retentionDays));
      for (final f in d.listSync().whereType<File>()) {
        if (f.lastModifiedSync().isBefore(limit)) f.deleteSync();
      }
    } on FileSystemException {
      // 無視する。
    }
  }
}

/// 機能名付きのロガー。
class AppLogger {
  AppLogger(this.sink, this.name);
  final LogSink sink;
  final String name;

  void error(String m, [Object? e, StackTrace? s]) => sink.write(LogLevel.error, name, m, e, s);
  void warn(String m) => sink.write(LogLevel.warn, name, m);
  void info(String m) => sink.write(LogLevel.info, name, m);
  void debug(String m) => sink.write(LogLevel.debug, name, m);
}
