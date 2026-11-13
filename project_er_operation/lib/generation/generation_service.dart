import 'dart:convert';
import 'dart:io';
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
    final v = ModelValidator(model, nameFormat: nameFormat, pkNaming: pkNaming).validate();
    if (v.hasErrors) return GenerationOutcome.invalid(v.errors, v.warnings);
    final json = GenerationJsonBuilder(model, pkNaming: pkNaming, dropBeforeCreate: dropBeforeCreate).buildText();
    final text = await runner.run(script: postScript, jsonText: json, timeout: timeout, onLog: onLog);
    return GenerationOutcome.ok(text, v.warnings);
  }
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

/// 改行を変換した、UTF-8(BOMなし)のバイト列。
Uint8List generatedFileBytes(String text, {required bool crlf}) {
  final normalized = text.replaceAll('\r\n', '\n');
  return Uint8List.fromList(utf8.encode(crlf ? normalized.replaceAll('\n', '\r\n') : normalized));
}

/// 改行を変換して、UTF-8(BOMなし)で書く。
Future<void> writeGeneratedFile(String path, String text, {required bool crlf}) async {
  await File(path).writeAsBytes(generatedFileBytes(text, crlf: crlf), flush: true);
}
