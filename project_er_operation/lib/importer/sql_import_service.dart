import 'dart:convert';

import '../generation/generation.dart';

/// インポートするSQLファイル1つ。
class SqlImportFile {
  const SqlImportFile({required this.name, required this.text});
  final String name;
  final String text;
}

/// インポート用のポストファイルを実行して、インポート結果(付録E)を返す(Facade パターン)。
/// ポストファイルへは `{ "files": [ { "name", "text" } ] }` を渡す。
/// 例外・タイムアウト・結果が不正なときは [PostException]。
Future<Map<String, Object?>> runImportPost(
  PostRunner runner, {
  required String script,
  required List<SqlImportFile> files,
  required Duration timeout,
  String? library,
  void Function(String message)? onLog,
}) async {
  final input = jsonEncode({
    'files': [
      for (final f in files) {'name': f.name, 'text': f.text}
    ]
  });
  final text = await runner.run(script: script, jsonText: input, timeout: timeout, onLog: onLog, library: library);
  final Object? decoded;
  try {
    decoded = jsonDecode(text);
  } on FormatException catch (e) {
    throw PostException('インポート結果がJSONではありません: ${e.message}');
  }
  if (decoded is! Map) throw PostException('インポート結果がJSONのオブジェクトではありません');
  return Map<String, Object?>.from(decoded);
}
