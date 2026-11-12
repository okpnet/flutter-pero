import 'dart:convert';
import 'dart:io';

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

/// `.pero` ファイルの読み書き(4.1、9.4)。
class PeroFile {
  /// 保存: 整合性確認 → 一時ファイルに書く → リネーム(4.1-3)。
  static Future<SaveResult> save(ErModel model, String path) async {
    final (ok, repairs) = IntegrityRepairer.repairAll(model);
    if (!ok) return SaveResult.fail('整合性を回復できないため保存を中止しました');
    final tmp = File('$path.tmp');
    try {
      await tmp.writeAsString(PeroEncoder.encode(model), encoding: utf8, flush: true);
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
