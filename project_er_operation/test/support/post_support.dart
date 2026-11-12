import 'dart:io';

import 'package:project_er_operation/generation/generation.dart';
import 'package:project_er_operation/model/model.dart';
import 'package:project_er_operation/runner/runner.dart';

/// flutter_js は `flutter test` 中は、カレントディレクトリ(など)の `quickjs_c_bridge.dll` を読む。
/// `flutter build windows --debug` で作られるプラグインのDLLを、プロジェクト直下へ複製して使う(.gitignore 対象)。
bool prepareQuickJs() {
  final dst = File('quickjs_c_bridge.dll');
  if (dst.existsSync()) return true;
  final src = File('build/windows/x64/runner/Debug/quickjs_c_bridge.dll');
  if (!src.existsSync()) return false;
  src.copySync(dst.path);
  return true;
}

final String postScript = File('post/postgresql.post').readAsStringSync();

/// モデルから、同梱の postgresql.post でSQLを生成する。
Future<String> generateSql(ErModel model) async {
  final r = await GenerationService(JsPostRunner())
      .generate(model, postScript, timeout: const Duration(seconds: 20));
  if (!r.isOk) {
    throw StateError('検証エラー: ${r.errors.map((e) => e.message).join(' / ')}');
  }
  return r.text!;
}
