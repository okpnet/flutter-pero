import 'package:logger_provider/logger_provider.dart';

import 'app_logger.dart';

/// 共通ライブラリ(theme_lib)のロガー(`ILoggerProvider`)を、アプリのログ(11.5)へつなぐ。
/// アダプタ(Adapter)。
class ThemeLoggerAdapter implements ILoggerProvider {
  ThemeLoggerAdapter(this._logger);
  final AppLogger _logger;

  // `logger` パッケージのレベル値(debug=2000, info=3000, warning=4000, error=5000, fatal=6000)に合わせる。
  @override
  int get level => switch (_logger.sink.level) {
        LogLevel.debug => 2000,
        LogLevel.info => 3000,
        LogLevel.warn => 4000,
        LogLevel.error => 5000,
      };

  @override
  void debug(String message, {Object? ex, StackTrace? trace}) => _logger.debug(_join(message, ex));

  @override
  void info(String message, {Object? ex, StackTrace? trace}) => _logger.info(_join(message, ex));

  @override
  void warn(String message, {Object? ex, StackTrace? trace}) => _logger.warn(_join(message, ex));

  @override
  void error(String message, {Object? ex, StackTrace? trace}) => _logger.error(message, ex, trace);

  @override
  void fatal(String message, {Object? ex, StackTrace? trace}) => _logger.error(message, ex, trace);

  String _join(String m, Object? ex) => ex == null ? m : '$m : $ex';
}
