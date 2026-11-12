import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import '../persistence/persistence.dart';

/// ファイル選択ダイアログ(Adapter パターン)。`file_picker` のバージョン差をここに閉じ込める。
class FileDialogs {
  const FileDialogs();

  /// 既存のファイルを1つ選ぶ。キャンセルはnull。
  Future<String?> pickOpen({
    required String title,
    required List<String> extensions,
    String? initialDirectory,
  }) async {
    final r = await FilePicker.platform.pickFiles(
      dialogTitle: title,
      type: FileType.custom,
      allowedExtensions: extensions,
      initialDirectory: initialDirectory,
    );
    return r?.files.single.path;
  }

  /// 保存先を選び、[bytes] を書き込んで、保存したパスを返す。キャンセルはnull。
  /// 拡張子が付いていなければ [extension](ドットなし)を付ける。
  Future<String?> saveBytes({
    required String title,
    required String fileName,
    required Uint8List bytes,
    required String extension,
    String? initialDirectory,
  }) async {
    final picked = await FilePicker.platform.saveFile(
      dialogTitle: title,
      fileName: fileName,
      initialDirectory: initialDirectory,
      type: FileType.custom,
      allowedExtensions: [extension],
    );
    if (picked == null) return null;
    final path = picked.toLowerCase().endsWith('.$extension') ? picked : '$picked.$extension';
    final r = await PeroFile.writeAtomically(path, bytes, Repairs());
    if (!r.isOk) throw FileSystemException(r.error ?? '書込みに失敗しました', path);
    return path;
  }

  /// フォルダを選ぶ。キャンセルはnull。
  Future<String?> pickFolder({required String title, String? initialDirectory}) =>
      FilePicker.platform.getDirectoryPath(dialogTitle: title, initialDirectory: initialDirectory);
}
