import 'dart:io';

import 'package:project_er_operation/logging/logging.dart';
import 'package:project_er_operation/model/model.dart';
import 'package:project_er_operation/persistence/persistence.dart';
import 'package:project_er_operation/session/session.dart';
import 'package:project_er_operation/settings/settings.dart';

/// テスト用のセッション(キャッシュ・ログは一時ディレクトリ)。
EditorSession newSession({ErModel? model}) {
  final dir = Directory.systemTemp.createTempSync('pero_session');
  final s = EditorSession(
    settings: AppSettings(),
    logger: AppLogger(LogSink(dir.path, level: LogLevel.error), 'test'),
    cache: CacheStore(dir.path),
  );
  if (model != null) {
    s.openRecovered(model, null);
    s.history.clear();
  }
  return s;
}
