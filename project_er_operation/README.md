# PERO(アプリ本体)

ER図作成アプリ(Windows 10/11、Flutter)。概要と使い方は、リポジトリのルートの [README](../README.md) と [使い方](doc/contents/使い方.md)、仕様は [CLAUDE.md](CLAUDE.md) を見てください。

現在のバージョン: **0.2.0**

## 開発

```
flutter pub get
flutter analyze
flutter test
flutter build windows --debug
```

- ポストファイルの生成テスト(`test/generation`、`test/actions`)は QuickJS(flutter_js)を使うため、先に一度 `flutter build windows --debug` を実行してください。テストは `build/windows/x64/runner/Debug/quickjs_c_bridge.dll` をプロジェクト直下へコピーして使います(`.gitignore` 対象)。
- 共通ライブラリ(`flutter-pms` の `theme_lib`、`logger_provider`)をパス依存で使っています。`pubspec.yaml` の `path:` のとおり、リポジトリの隣に `flutter-pms` を置いてください。
- `flutter test` / `flutter analyze` / 依存の追加の直後の `flutter build windows`(IDEのデバッグ実行を含む)は、1回目だけ「`windows/flutter/ephemeral/cpp_client_wrapper` のソースが開けない」というエラーで失敗することがあります。そのフォルダを削除してから、もう一度ビルドしてください。

```powershell
Remove-Item -Recurse -Force windows\flutter\ephemeral\cpp_client_wrapper
flutter build windows --debug
```
