import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../settings/settings.dart';
import 'editor_session.dart';

/// 編集セッション。起動時に実体で上書きする。
final editorSessionProvider = Provider<EditorSession>(
  (ref) => throw UnimplementedError('editorSessionProvider は起動時に上書きしてください'),
);

/// 設定ファイルの読み書き。
final settingsStoreProvider = Provider<SettingsStore>((ref) => SettingsStore());
