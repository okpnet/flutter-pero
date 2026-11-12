import 'dart:convert';
import 'dart:io';

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
    void Function(String)? onLog,
  }) async {
    final v = ModelValidator(model, nameFormat: nameFormat).validate();
    if (v.hasErrors) return GenerationOutcome.invalid(v.errors, v.warnings);
    final json = GenerationJsonBuilder(model).buildText();
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

/// 改行を変換して、UTF-8(BOMなし)で書く。
Future<void> writeGeneratedFile(String path, String text, {required bool crlf}) async {
  final normalized = text.replaceAll('\r\n', '\n');
  final body = crlf ? normalized.replaceAll('\n', '\r\n') : normalized;
  await File(path).writeAsString(body, encoding: utf8, flush: true);
}
