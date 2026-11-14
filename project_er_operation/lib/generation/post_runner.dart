import 'generation_json.dart';

/// ポストファイルのメタ情報(9.6-4)。
class PostMeta {
  const PostMeta({required this.name, required this.targetDb, required this.apiVersion, this.role = PostRole.export});
  final String name;
  final String targetDb;
  final int apiVersion;

  /// ポストファイルの役割(エクスポート=SQL生成、インポート=SQL取り込み。9.6-4)。省略時はエクスポート。
  final PostRole role;
}

/// ポストファイルの役割。
enum PostRole { export, import }

/// 先頭10行以内の `// @post name=<表示名> targetDb=<dbKind> apiVersion=<整数>` を読む。
/// 見つからないか不正ならnull。
PostMeta? parsePostMeta(String script) {
  final lines = script.split(RegExp(r'\r?\n')).take(10);
  for (final line in lines) {
    final m = RegExp(r'^\s*//\s*@post\s+(.*)$').firstMatch(line);
    if (m == null) continue;
    final kv = <String, String>{};
    // 値に空白を含む name は、次のキー(targetDb= / apiVersion=)の直前までとする。
    final rest = m.group(1)!;
    final re = RegExp(r'(name|targetDb|apiVersion|role)=');
    final hits = re.allMatches(rest).toList();
    for (var i = 0; i < hits.length; i++) {
      final end = i + 1 < hits.length ? hits[i + 1].start : rest.length;
      kv[hits[i].group(1)!] = rest.substring(hits[i].end, end).trim();
    }
    final v = int.tryParse(kv['apiVersion'] ?? '');
    if (kv['name'] == null || kv['targetDb'] == null || v == null) return null;
    final roleText = (kv['role'] ?? 'export').toLowerCase();
    final role = roleText == 'import' ? PostRole.import : (roleText == 'export' ? PostRole.export : null);
    if (role == null) return null;
    return PostMeta(name: kv['name']!, targetDb: kv['targetDb']!, apiVersion: v, role: role);
  }
  return null;
}

/// ポストファイルの実行に失敗したとき。
class PostException implements Exception {
  PostException(this.message, {this.stack});
  final String message;
  final String? stack;
  @override
  String toString() => message;
}

/// ポストファイル(JavaScript)の実行を隔離するインターフェース(2-13)。
abstract class PostRunner {
  /// `main(jsonText)` を実行して生成ファイル全文を返す。
  /// 例外・タイムアウト・戻り値が文字列でない場合は [PostException]。
  /// [onLog] へ `console.log` を渡す。
  Future<String> run({
    required String script,
    required String jsonText,
    required Duration timeout,
    void Function(String message)? onLog,
    String? library,
  });
}

/// メタ情報の検査(9.6-2)。問題があれば文言を返す。
String? checkPostApiVersion(PostMeta? meta) {
  if (meta == null) return 'ポストファイルの先頭に「// @post name=… targetDb=… apiVersion=…」がありません';
  if (meta.apiVersion != postApiVersion) {
    return 'ポストファイルのapiVersion(${meta.apiVersion})がアプリの対応(apiVersion $postApiVersion)と合いません';
  }
  return null;
}
