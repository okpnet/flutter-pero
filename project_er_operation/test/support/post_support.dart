import 'dart:io';

import 'package:project_er_operation/generation/generation.dart';
import 'package:project_er_operation/model/model.dart';
import 'package:project_er_operation/runner/runner.dart';

/// flutter_qjs は `flutter test` 中は test/build/Debug/ffiquickjs.dll を読む。
/// `flutter build windows --debug` で作られるプラグインDLLを複製して使う。
bool prepareQuickJs() {
  final dst = File('test/build/Debug/ffiquickjs.dll');
  if (dst.existsSync()) return true;
  final src = File('build/windows/x64/plugins/flutter_qjs/Debug/flutter_qjs_plugin.dll');
  if (!src.existsSync()) return false;
  dst.parent.createSync(recursive: true);
  src.copySync(dst.path);
  return true;
}

final String postScript = File('post/postgresql.post').readAsStringSync();

/// モデルから、同梱の postgresql.post でSQLを生成する。
Future<String> generateSql(ErModel model) async {
  final r = await GenerationService(QjsPostRunner())
      .generate(model, postScript, timeout: const Duration(seconds: 20));
  if (!r.isOk) {
    throw StateError('検証エラー: ${r.errors.map((e) => e.message).join(' / ')}');
  }
  return r.text!;
}
