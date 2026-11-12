import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';

import '../persistence/persistence.dart';

/// ファイル選択ダイアログ(Adapter パターン)。ダイアログのパッケージ(file_selector)をここに閉じ込める。
///
/// file_selector は、選択だけを行い、書込みはしない。そのため、保存は選ばれたパスへ
/// 一時ファイル経由で原子的に書き込める(4.1-3: 途中で失敗しても元のファイルを壊さない)。
class FileDialogs {
  const FileDialogs();

  /// 既存のファイルを1つ選ぶ。キャンセルはnull。
  Future<String?> pickOpen({
    required String title,
    required List<String> extensions,
    String? initialDirectory,
  }) async {
    final f = await openFile(
      acceptedTypeGroups: [XTypeGroup(label: extensions.join(', '), extensions: extensions)],
      initialDirectory: initialDirectory,
      confirmButtonText: '開く',
    );
    return f?.path;
  }

  /// 保存先を選び、[bytes] を原子的に書き込んで、保存したパスを返す。キャンセルはnull。
  /// 拡張子が付いていなければ [extension](ドットなし)を付ける。
  /// 既存のファイルを選んだときの上書きの確認は、OSのダイアログが行う。書込みの失敗は [FileSystemException]。
  Future<String?> saveBytes({
    required String title,
    required String fileName,
    required Uint8List bytes,
    required String extension,
    String? initialDirectory,
  }) async {
    final name = fileName.toLowerCase().endsWith('.$extension') ? fileName : '$fileName.$extension';
    final loc = await getSaveLocation(
      acceptedTypeGroups: [XTypeGroup(label: extension, extensions: [extension])],
      suggestedName: name,
      initialDirectory: initialDirectory,
      confirmButtonText: '保存',
    );
    if (loc == null) return null;
    final path = loc.path.toLowerCase().endsWith('.$extension') ? loc.path : '${loc.path}.$extension';
    final r = await PeroFile.writeAtomically(path, bytes, Repairs());
    if (!r.isOk) throw FileSystemException(r.error ?? '書込みに失敗しました', path);
    return path;
  }

  /// フォルダを選ぶ。キャンセルはnull。
  Future<String?> pickFolder({required String title, String? initialDirectory}) =>
      getDirectoryPath(initialDirectory: initialDirectory, confirmButtonText: '選択');
}
