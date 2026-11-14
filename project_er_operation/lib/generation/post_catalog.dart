import 'dart:convert';
import 'dart:io';

import '../model/model.dart';
import 'post_runner.dart';

/// フォルダにあるポストファイル1つの情報(メタ情報から対象DBを判断する。9.6-4)。
class PostFileInfo {
  const PostFileInfo({required this.path, required this.fileName, this.meta, this.problem});

  final String path;
  final String fileName;

  /// 先頭10行以内の `// @post ...` を読んだ結果。読めない/不正なときはnull。
  final PostMeta? meta;

  /// メタ情報が使えない理由(あれば)。
  final String? problem;

  /// 使えるポストファイルか(メタ情報があり、apiVersionが合う)。
  bool get isValid => meta != null && problem == null;

  /// 一覧に出す表示名。
  String get label => meta == null ? fileName : '${meta!.name}($fileName)';

  /// このポストファイルが扱うデータベースの種類(kind)。
  /// メタ情報の `targetDb` がkindのいずれかならそれ、そうでなければ設定の関連付け(ファイル名 → kind)。
  /// どちらでもなければnull。
  DbKind? kindOf(Map<String, DbKind> associations) {
    final m = meta;
    if (m == null) return null;
    return associations[fileName.toLowerCase()] ??
        associations[m.targetDb.toLowerCase()] ??
        enumFromWire(DbKind.values, m.targetDb);
  }
}

/// ポストフォルダの内容(`*.post`)。
class PostCatalog {
  const PostCatalog(this.files);
  const PostCatalog.empty() : files = const [];

  final List<PostFileInfo> files;

  /// フォルダを走査する。フォルダが無いときは空。ファイル名の昇順。
  factory PostCatalog.scan(String folder) {
    final dir = Directory(folder);
    if (!dir.existsSync()) return const PostCatalog.empty();
    final infos = <PostFileInfo>[];
    final entries = dir.listSync().whereType<File>().where((f) => f.path.toLowerCase().endsWith('.post')).toList()
      ..sort((a, b) => a.path.toLowerCase().compareTo(b.path.toLowerCase()));
    for (final f in entries) {
      infos.add(_inspect(f));
    }
    return PostCatalog(infos);
  }

  static PostFileInfo _inspect(File f) {
    final name = f.path.substring(f.path.lastIndexOf(Platform.pathSeparator) + 1);
    try {
      // メタ情報は先頭10行以内。全文は読まない。
      final head = _readHead(f);
      final meta = parsePostMeta(head);
      return PostFileInfo(path: f.path, fileName: name, meta: meta, problem: checkPostApiVersion(meta));
    } on FileSystemException catch (e) {
      return PostFileInfo(path: f.path, fileName: name, problem: '読み込めません: ${e.message}');
    }
  }

  static String _readHead(File f) {
    final raf = f.openSync();
    try {
      final bytes = raf.readSync(4096);
      return utf8.decode(bytes, allowMalformed: true);
    } finally {
      raf.closeSync();
    }
  }

  /// 使えるエクスポート用(SQL生成)のポストファイル。
  List<PostFileInfo> get valid => [for (final f in files) if (f.isValid && f.meta!.role == PostRole.export) f];

  /// 使えるインポート用(SQL取り込み)のポストファイル。
  List<PostFileInfo> get imports => [for (final f in files) if (f.isValid && f.meta!.role == PostRole.import) f];

  /// 使えるエクスポート用のポストファイルが1つ以上あるか。
  bool get hasValid => files.any((f) => f.isValid && f.meta!.role == PostRole.export);

  /// 適用できるデータベースの種類(kind)。関連付け([associations])を含む。
  Set<DbKind> kinds(Map<String, DbKind> associations) =>
      {for (final f in valid) ?f.kindOf(associations)};

  /// 指定の種類のポストファイル(ファイル名順の先頭を既定とする)。
  List<PostFileInfo> forKind(DbKind kind, Map<String, DbKind> associations) =>
      [for (final f in valid) if (f.kindOf(associations) == kind) f];

  PostFileInfo? byPath(String path) {
    final p = path.toLowerCase();
    for (final f in files) {
      if (f.path.toLowerCase() == p) return f;
    }
    return null;
  }
}

/// 共通ヘルパのファイル名(9.12-1)。
const String postLibraryFileName = 'pero.lib.js';

/// ポストファイルと同じフォルダにある共通ヘルパ `pero.lib.js` を読む。無ければnull(9.12-1)。
String? loadPostLibrary(String postPath) {
  final i = postPath.lastIndexOf(Platform.pathSeparator);
  final dir = i < 0 ? '.' : postPath.substring(0, i);
  final f = File('$dir${Platform.pathSeparator}$postLibraryFileName');
  try {
    return f.existsSync() ? f.readAsStringSync() : null;
  } on FileSystemException {
    return null;
  }
}

/// ポストファイルを開けないとき(存在しない、他から使われているなど)。
class PostFileException implements Exception {
  PostFileException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// 生成の間、ポストファイルを占有する(ロック)。ほかのプロセスや操作から、
/// 書込み・削除・名前の変更ができないようにする(9.6-1-2)。使い終えたら必ず [release] する。
class LockedPostFile {
  LockedPostFile._(this.path, this._raf, this.text);

  final String path;
  final RandomAccessFile _raf;

  /// ロックしたまま読み込んだポストファイルの全文。
  final String text;

  /// ロックして読み込む。ファイルが無いときは [PostFileException](処理を止める)。
  static Future<LockedPostFile> acquire(String path) async {
    final file = File(path);
    if (!file.existsSync()) throw PostFileException('ポストファイルが存在しません: $path');
    RandomAccessFile? raf;
    try {
      raf = await file.open();
      await raf.lock(FileLock.exclusive);
      final len = await raf.length();
      await raf.setPosition(0);
      final bytes = await raf.read(len);
      return LockedPostFile._(path, raf, utf8.decode(bytes));
    } on FileSystemException catch (e) {
      await raf?.close();
      throw PostFileException('ポストファイルをロックできません(他で使用中の可能性があります): $path\n${e.message}');
    } on FormatException catch (e) {
      await raf?.close();
      throw PostFileException('ポストファイルがUTF-8ではありません: $path\n${e.message}');
    }
  }

  /// ロックを解除する。
  Future<void> release() async {
    try {
      await _raf.unlock();
    } on FileSystemException {
      // 解除に失敗しても、閉じればロックは外れる。
    }
    await _raf.close();
  }
}

/// 設定の関連付け(「ファイル名=kind」をカンマ・改行区切り)を読む。不正な項目は無視する。
Map<String, DbKind> parseKindAssociations(String text) {
  final map = <String, DbKind>{};
  for (final part in text.split(RegExp(r'[,\n;]'))) {
    final i = part.indexOf('=');
    if (i <= 0) continue;
    final key = part.substring(0, i).trim().toLowerCase();
    final kind = enumFromWire(DbKind.values, part.substring(i + 1).trim().toLowerCase());
    if (key.isNotEmpty && kind != null) map[key] = kind;
  }
  return map;
}

String formatKindAssociations(Map<String, DbKind> map) =>
    [for (final e in map.entries) '${e.key}=${e.value.wire}'].join(', ');
