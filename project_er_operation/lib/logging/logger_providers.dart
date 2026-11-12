import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_logger.dart';

/// ログの出力先。起動時に実体で上書きする(`ProviderContainer(overrides: ...)`)。
final logSinkProvider = Provider<LogSink>(
  (ref) => throw UnimplementedError('logSinkProvider は起動時に上書きしてください'),
);

/// 機能名(11.1-4のディレクトリ名)をロガー名にしたロガー(11.5-3)。
final loggerProvider = Provider.family<AppLogger, String>(
  (ref, feature) => AppLogger(ref.watch(logSinkProvider), feature),
);
