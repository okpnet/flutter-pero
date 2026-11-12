import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

/// ファイル選択ダイアログ(Adapter パターン)。`file_picker` のバージョン差をここに閉じ込める。
///
/// file_picker 13.x では、保存ダイアログ(`saveFile`)が選択と同時にバイト列を書き込む(保存先のパスだけを返す
/// 方法は無い)。そのため、保存するデータは先に作って渡す(`.pero` は `PeroFile.prepare` で整合性確認を済ませる)。
class FileDialogs {
  const FileDialogs();

  /// 既存のファイルを1つ選ぶ。キャンセルはnull。
  Future<String?> pickOpen({
    required String title,
    required List<String> extensions,
    String? initialDirectory,
  }) async {
    final f = await FilePicker.pickFile(
      dialogTitle: title,
      type: FileType.custom,
      allowedExtensions: extensions,
      initialDirectory: initialDirectory,
    );
    return f?.path;
  }

  /// 保存先を選び、[bytes] を書き込んで、保存したパスを返す。キャンセルはnull。
  /// 既存のファイルを選んだときの上書きの確認は、OSのダイアログが行う。
  /// 既定のファイル名には [extension](ドットなし)を付け、ユーザーが拡張子なしで入力したときは、
  /// ダイアログが既定の拡張子を補う。書込みの失敗は [FileSystemException]。
  Future<String?> saveBytes({
    required String title,
    required String fileName,
    required Uint8List bytes,
    required String extension,
    String? initialDirectory,
  }) async {
    final name = fileName.toLowerCase().endsWith('.$extension') ? fileName : '$fileName.$extension';
    final Uri? saved;
    try {
      saved = await FilePicker.saveFile(
        dialogTitle: title,
        fileName: name,
        bytes: bytes,
        initialDirectory: initialDirectory,
      );
    } on FileSystemException {
      rethrow;
    } on Object catch (e) {
      throw FileSystemException('$e', name);
    }
    return saved?.toFilePath();
  }

  /// フォルダを選ぶ。キャンセルはnull。
  Future<String?> pickFolder({required String title, String? initialDirectory}) =>
      FilePicker.getDirectoryPath(dialogTitle: title, initialDirectory: initialDirectory);
}
