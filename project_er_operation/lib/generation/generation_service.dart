import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import '../model/model.dart';
import 'generation_json.dart';
import 'post_runner.dart';
import 'validator.dart';

class GenerationOutcome {
  GenerationOutcome.ok(this.text, this.warnings) : errors = const [];
  GenerationOutcome.invalid(this.errors, this.warnings) : text = null;
  final String? text;
  final List<ValidationIssue> errors;
  final List<ValidationIssue> warnings;
  bool get isOk => text != null;
}

/// 生成の手順(9.6-1の3〜4)。ファイルの確認・書込みはUI側が行う。
class GenerationService {
  GenerationService(this.runner);
  final PostRunner runner;

  /// 生成前検証 → 生成用JSON → ポストファイル実行。
  Future<GenerationOutcome> generate(
    ErModel model,
    String postScript, {
    required Duration timeout,
    String nameFormat = r'^[A-Za-z_][A-Za-z0-9_]*$',
    PkNaming pkNaming = const PkNaming(),
    bool dropBeforeCreate = false,
    void Function(String)? onLog,
  }) async {
    // 検証と生成用JSONの作成は、大きなモデルでは時間がかかるため、別Isolateで行う(画面を止めない)。
    // モデルなどを別Isolateへ渡せないときは、このIsolateで行う。
    PreparedGeneration prep;
    try {
      prep = await Isolate.run(() => prepareGeneration(model, nameFormat, pkNaming, dropBeforeCreate));
    } on Object {
      prep = prepareGeneration(model, nameFormat, pkNaming, dropBeforeCreate);
    }
    if (prep.jsonText == null) return GenerationOutcome.invalid(prep.errors, prep.warnings);
    final text = await runner.run(script: postScript, jsonText: prep.jsonText!, timeout: timeout, onLog: onLog);
    return GenerationOutcome.ok(text, prep.warnings);
  }
}

/// 生成前検証(9.5)と、生成用JSONの作成の結果。エラーがあるときは [jsonText] がnull。
class PreparedGeneration {
  PreparedGeneration(this.errors, this.warnings, this.jsonText);
  final List<ValidationIssue> errors;
  final List<ValidationIssue> warnings;
  final String? jsonText;
}

PreparedGeneration prepareGeneration(ErModel model, String nameFormat, PkNaming pkNaming, bool dropBeforeCreate) {
  final v = ModelValidator(model, nameFormat: nameFormat, pkNaming: pkNaming).validate();
  if (v.hasErrors) return PreparedGeneration(v.errors, v.warnings, null);
  final json = GenerationJsonBuilder(model, pkNaming: pkNaming, dropBeforeCreate: dropBeforeCreate).buildText();
  return PreparedGeneration(const [], v.warnings, json);
}

/// 出力先のパス(9.6-1の5)。
String resolveOutputPath({
  required ErModel model,
  required String? peroFilePath,
  required String documentsDir,
  required String extension,
}) {
  final sep = Platform.pathSeparator;
  String dirOf(String p) => p.substring(0, p.lastIndexOf(sep));
  String baseOf(String p) {
    final f = p.substring(p.lastIndexOf(sep) + 1);
    return f.toLowerCase().endsWith('.pero') ? f.substring(0, f.length - 5) : f;
  }

  var folder = model.properties.outputFolder;
  if (folder.isEmpty) folder = peroFilePath != null ? dirOf(peroFilePath) : documentsDir;
  var name = model.properties.outputFileName;
  if (name.isEmpty) name = peroFilePath != null ? baseOf(peroFilePath) : '無題';
  final ext = extension.startsWith('.') ? extension.substring(1) : extension;
  return '$folder$sep$name.$ext';
}

/// 改行を変換した、UTF-8(BOMなし)のバイト列。[db] は、引用符の規則(9.6-5)に使う。
Uint8List generatedFileBytes(String text, {required bool crlf, DbKind db = DbKind.postgresql}) =>
    Uint8List.fromList(utf8.encode(convertNewlines(text, crlf: crlf, db: db)));

/// 改行を変換して、UTF-8(BOMなし)で書く。
Future<void> writeGeneratedFile(String path, String text,
    {required bool crlf, DbKind db = DbKind.postgresql}) async {
  await File(path).writeAsBytes(generatedFileBytes(text, crlf: crlf, db: db), flush: true);
}

/// 生成したSQLの改行を、設定の改行コードへ変換する(9.6-5)。
/// 引用符(シングルクォート)で囲んだ文字列リテラルの中は、内容が変わるため変換しない。
/// ファンクションやビューの本体、コメント(`--`、`/* */`)など、それ以外は変換する。
/// 引用符が閉じていないなど、解析できないときは、全体を変換する。
String convertNewlines(String text, {required bool crlf, DbKind db = DbKind.postgresql}) {
  final eol = crlf ? '\r\n' : '\n';
  String whole() => text.replaceAll('\r\n', '\n').replaceAll('\n', eol);
  final out = StringBuffer();
  final n = text.length;
  final backslashEscapes = db == DbKind.mysql;
  var i = 0;

  /// 引用符 [q] で始まる要素を、閉じるところまでそのまま書く。閉じていなければ false。
  bool copyQuoted(String q, {required bool escapes}) {
    out.write(q);
    i++;
    while (i < n) {
      final c = text[i];
      if (escapes && c == r'\' && i + 1 < n) {
        out.write(text.substring(i, i + 2));
        i += 2;
        continue;
      }
      if (c == q) {
        if (i + 1 < n && text[i + 1] == q) {
          out.write(q + q);
          i += 2;
          continue;
        }
        out.write(q);
        i++;
        return true;
      }
      out.write(c);
      i++;
    }
    return false;
  }

  while (i < n) {
    final c = text[i];
    if (c == '\r' && i + 1 < n && text[i + 1] == '\n') {
      out.write(eol);
      i += 2;
    } else if (c == '\n') {
      out.write(eol);
      i++;
    } else if (c == '-' && i + 1 < n && text[i + 1] == '-') {
      // 行コメント: 改行の前まで(中の引用符は無視する)
      while (i < n && text[i] != '\n' && !(text[i] == '\r' && i + 1 < n && text[i + 1] == '\n')) {
        out.write(text[i]);
        i++;
      }
    } else if (c == '/' && i + 1 < n && text[i + 1] == '*') {
      final end = text.indexOf('*/', i + 2);
      if (end < 0) return whole();
      out.write(text.substring(i, end + 2).replaceAll('\r\n', '\n').replaceAll('\n', eol));
      i = end + 2;
    } else if (c == "'") {
      // PostgreSQL の E'...' は、バックスラッシュのエスケープを持つ。
      final prev = i > 0 ? text[i - 1] : '';
      final prev2 = i > 1 ? text[i - 2] : ' ';
      final isE = db == DbKind.postgresql && (prev == 'e' || prev == 'E') && !RegExp(r'[A-Za-z0-9_]').hasMatch(prev2);
      if (!copyQuoted("'", escapes: backslashEscapes || isE)) return whole();
    } else if (c == '"') {
      if (!copyQuoted('"', escapes: backslashEscapes)) return whole();
    } else if (c == '`' && db == DbKind.mysql) {
      if (!copyQuoted('`', escapes: false)) return whole();
    } else {
      out.write(c);
      i++;
    }
  }
  return out.toString();
}
