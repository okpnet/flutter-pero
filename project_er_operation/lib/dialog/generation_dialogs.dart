import 'dart:io';

import 'package:flutter/material.dart';

import '../common/common.dart';
import '../generation/generation.dart';

/// 生成前検証のエラー一覧(9.5)。
Future<void> showValidationErrors(BuildContext context, List<ValidationIssue> errors,
    List<ValidationIssue> warnings) {
  return showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text('生成前検証: エラー ${errors.length}件'),
      content: SizedBox(
        width: 640,
        height: 400,
        child: ListView(children: [
          for (final e in errors)
            ListTile(dense: true, leading: const Icon(Icons.error, color: Colors.red, size: 18), title: Text(e.message)),
          for (final w in warnings)
            ListTile(dense: true, leading: const Icon(Icons.warning_amber, color: Colors.orange, size: 18), title: Text(w.message)),
        ]),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text(Strings.close))],
    ),
  );
}

/// 生成結果(9.6-1の6): 成功、警告の一覧、出力ファイルのパス。
Future<void> showGenerationResult(BuildContext context,
    {required String path, required List<ValidationIssue> warnings}) {
  return showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('生成が完了しました'),
      content: SizedBox(
        width: 640,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          SelectableText(path),
          if (warnings.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('警告 ${warnings.length}件'),
            SizedBox(
              height: 200,
              child: ListView(children: [
                for (final w in warnings)
                  ListTile(dense: true, leading: const Icon(Icons.warning_amber, color: Colors.orange, size: 18), title: Text(w.message)),
              ]),
            ),
          ],
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Process.run('explorer', ['/select,', path]), child: const Text('フォルダを開く')),
        TextButton(onPressed: () => Process.run('cmd', ['/c', 'start', '', path]), child: const Text('ファイルを開く')),
        FilledButton(onPressed: () => Navigator.pop(c), child: const Text(Strings.close)),
      ],
    ),
  );
}

/// 画像出力のオプション(9.8-2)。
class ImageExportOptions {
  ImageExportOptions({required this.perPage, required this.dpi});
  final bool perPage;
  final int dpi;
}

Future<ImageExportOptions?> showImageExportDialog(BuildContext context, int defaultDpi) {
  var perPage = true;
  final ctrl = TextEditingController(text: '$defaultDpi');
  String? err;
  return showDialog<ImageExportOptions>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, setState) => AlertDialog(
        title: const Text('画像出力(PNG)'),
        content: SizedBox(
          width: 360,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('形式: PNG(PDF出力は今後のバージョンで対応します)'),
            const SizedBox(height: 8),
            RadioGroup<bool>(
              groupValue: perPage,
              onChanged: (v) => setState(() => perPage = v ?? true),
              child: const Column(children: [
                RadioListTile<bool>(dense: true, title: Text('用紙ページごと'), value: true),
                RadioListTile<bool>(dense: true, title: Text('全体を1枚'), value: false),
              ]),
            ),
            TextField(
              controller: ctrl,
              decoration: InputDecoration(labelText: '解像度(dpi 100〜600)', errorText: err, isDense: true),
              keyboardType: TextInputType.number,
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text(Strings.cancel)),
          FilledButton(
            onPressed: () {
              final v = int.tryParse(ctrl.text);
              if (v == null || v < 100 || v > 600) {
                setState(() => err = '100〜600の整数');
                return;
              }
              Navigator.pop(c, ImageExportOptions(perPage: perPage, dpi: v));
            },
            child: const Text(Strings.ok),
          ),
        ],
      ),
    ),
  );
}
