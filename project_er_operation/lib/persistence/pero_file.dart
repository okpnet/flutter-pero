import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../model/model.dart';
import 'integrity.dart';
import 'pero_decoder.dart';
import 'pero_encoder.dart';

/// 保存結果。
class SaveResult {
  SaveResult.ok(this.repairs) : error = null;
  SaveResult.fail(this.error) : repairs = Repairs();
  final String? error;
  final Repairs repairs;
  bool get isOk => error == null;
}

/// 保存の準備の結果(整合性確認を済ませたバイト列)。
class PreparedSave {
  PreparedSave.ok(this.bytes, this.repairs) : error = null;
  PreparedSave.fail(this.error)
      : bytes = null,
        repairs = Repairs();
  final Uint8List? bytes;
  final Repairs repairs;
  final String? error;
  bool get isOk => error == null;
}

/// `.pero` ファイルの読み書き(4.1、9.4)。
class PeroFile {
  /// 保存の準備: 整合性確認(修復を含む)を行い、書き込むバイト列(UTF-8、BOMなし)を作る(9.4-1)。
  /// ファイル選択ダイアログがバイト列を書き込む場合(file_picker)にも使う。
  static PreparedSave prepare(ErModel model) {
    final (ok, repairs) = IntegrityRepairer.repairAll(model);
    if (!ok) return PreparedSave.fail('整合性を回復できないため保存を中止しました');
    return PreparedSave.ok(Uint8List.fromList(utf8.encode(PeroEncoder.encode(model))), repairs);
  }

  /// 保存: 整合性確認 → 一時ファイルに書く → リネーム(4.1-3)。
  static Future<SaveResult> save(ErModel model, String path) async {
    final prep = prepare(model);
    if (!prep.isOk) return SaveResult.fail(prep.error);
    return writeAtomically(path, prep.bytes!, prep.repairs);
  }

  /// バイト列を一時ファイルに書いてからリネームする(途中で失敗しても元のファイルを壊さない)。
  static Future<SaveResult> writeAtomically(String path, Uint8List bytes, Repairs repairs) async {
    final tmp = File('$path.tmp');
    try {
      await tmp.writeAsBytes(bytes, flush: true);
      await tmp.rename(path);
      return SaveResult.ok(repairs);
    } on FileSystemException catch (e) {
      try {
        if (tmp.existsSync()) tmp.deleteSync();
      } on FileSystemException {
        // 一時ファイルの掃除失敗は無視する。
      }
      return SaveResult.fail('書込みに失敗しました: ${e.message}');
    }
  }

  /// 読込。修復があった場合は元のファイルを `.pero.bak` へ退避する(9.4-6)。
  static Future<LoadResult> open(String path) async {
    final String text;
    try {
      text = await File(path).readAsString(encoding: utf8);
    } on FileSystemException catch (e) {
      return LoadResult.fail('読込に失敗しました: ${e.message}');
    } on FormatException {
      return LoadResult.fail('UTF-8として読み込めません');
    }
    final r = PeroDecoder.decode(text.startsWith('﻿') ? text.substring(1) : text);
    if (r.model != null && !r.repairs.isEmpty) {
      try {
        await File(path).copy('$path.bak');
      } on FileSystemException {
        // 退避失敗は読込自体を妨げない。
      }
    }
    return r;
  }
}
