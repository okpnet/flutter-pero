# PERO

ER図作成アプリ(Windows 10/11、Flutter)。仕様は [CLAUDE.md](CLAUDE.md)、使い方は [doc/contents/使い方.md](doc/contents/使い方.md)。

現在のバージョン: **0.1.0**(実装状況は [doc/log/20261112_0001.md](doc/log/20261112_0001.md))。

## 開発

```
flutter pub get
flutter analyze
flutter test
flutter build windows --debug
```

- `postgresql.post` の生成テスト(`test/generation`)は QuickJS(flutter_js)を使うため、先に一度 `flutter build windows --debug` を実行してください。テストは `build/windows/x64/runner/Debug/quickjs_c_bridge.dll` をプロジェクト直下へコピーして使います(`.gitignore` 対象)。
- `flutter test` / `flutter analyze` / 依存の追加の直後の `flutter build windows`(IDEのデバッグ実行を含む)は、1回目だけ「`windows/flutter/ephemeral/cpp_client_wrapper` のソースが開けない」というエラーで失敗することがあります。もう一度実行すると成功します。
