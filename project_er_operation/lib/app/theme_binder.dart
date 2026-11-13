import 'dart:io';

import 'package:flutter/material.dart';
import 'package:theme_lib/theme_lib.dart';

import '../settings/settings.dart';

/// 設定の色テーマ(10.2)を、共通ライブラリ(theme_lib)の管理インスタンスへ反映する。
///
/// システム/ダーク/ライトは theme_lib の既定テーマのモードを切り替える。ユーザーテーマは、
/// 設定のファイルから theme_lib のテーマJSONを取り込んで適用する。
class ThemeBinder {
  ThemeBinder(this.manager);
  final ThemeManager manager;

  String? _userThemeId;

  /// 設定を反映する。ユーザーテーマが読み込めないときは、システムテーマで表示して理由を返す。
  String? apply(AppSettings s) {
    _removeUserTheme();
    switch (s.theme) {
      case ThemeChoice.system:
        return _builtIn(ThemeMode.system);
      case ThemeChoice.dark:
        return _builtIn(ThemeMode.dark);
      case ThemeChoice.light:
        return _builtIn(ThemeMode.light);
      case ThemeChoice.user:
        return _user(s.userThemeFile);
    }
  }

  String? _builtIn(ThemeMode mode) {
    manager.select(builtInThemes.first.id);
    manager.setMode(mode);
    return null;
  }

  String? _user(String path) {
    if (path.trim().isEmpty) {
      _builtIn(ThemeMode.system);
      return 'ユーザーテーマのファイルが指定されていません';
    }
    try {
      final text = File(path).readAsStringSync();
      final def = manager.importJson(text);
      _userThemeId = def.id;
      manager.setMode(ThemeMode.system);
      return null;
    } on ThemeLibException catch (e) {
      _builtIn(ThemeMode.system);
      return 'ユーザーテーマを読み込めません: ${e.message}';
    } on FileSystemException catch (e) {
      _builtIn(ThemeMode.system);
      return 'ユーザーテーマのファイルを読み込めません: ${e.message}';
    }
  }

  void _removeUserTheme() {
    final id = _userThemeId;
    _userThemeId = null;
    if (id == null) return;
    manager.select(builtInThemes.first.id);
    try {
      manager.remove(id);
    } on ThemeLibException {
      // 取り込み済みの定義が既に無い、または組み込みと同じidのときは何もしない。
    }
  }
}
