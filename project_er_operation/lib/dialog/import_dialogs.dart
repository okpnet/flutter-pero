import 'package:flutter/material.dart';

import '../common/common.dart';
import '../generation/generation.dart';
import '../importer/importer.dart';

/// SQLインポートの指定(9.11-2)。
class SqlImportOptions {
  SqlImportOptions({required this.postPath, required this.files, required this.newModel});

  /// インポート用のポストファイル。
  final String postPath;

  /// 取り込むSQLファイル(読む順)。
  final List<String> files;

  /// 真なら新しいモデルとして開く。偽なら現在のモデルに追加する。
  final bool newModel;
}

String _fileName(String p) => p.substring(p.lastIndexOf(RegExp(r'[\\/]')) + 1);

/// SQLインポートのダイアログ。ポストファイル(データベースの種類)、SQLファイル、取込先を選ぶ。
/// [pickFiles] はSQLファイルの選択ダイアログ。キャンセルは空のリスト。
Future<SqlImportOptions?> showSqlImportDialog(
  BuildContext context, {
  required List<PostFileInfo> imports,
  required Future<List<String>> Function() pickFiles,
  String? initialPostPath,
}) {
  var post = imports.any((f) => f.path == initialPostPath) ? initialPostPath! : imports.first.path;
  final files = <String>[];
  var newModel = true;
  return showDialog<SqlImportOptions>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, setState) => AlertDialog(
        title: const Text(Strings.fileImportSql),
        content: SizedBox(
          width: 560,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('データベース(インポート用のポストファイル)'),
            const SizedBox(height: 4),
            DropdownButton<String>(
              key: const ValueKey('importPost'),
              isExpanded: true,
              value: post,
              items: [
                for (final f in imports)
                  DropdownMenuItem(value: f.path, child: Text(f.label, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (v) => setState(() => post = v ?? post),
            ),
            const SizedBox(height: 12),
            Row(children: [
              const Expanded(child: Text('SQLファイル(上から順に読みます)')),
              TextButton.icon(
                key: const ValueKey('importPickFiles'),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('追加'),
                onPressed: () async {
                  final picked = await pickFiles();
                  setState(() {
                    for (final p in picked) {
                      if (!files.contains(p)) files.add(p);
                    }
                  });
                },
              ),
            ]),
            Container(
              height: 140,
              decoration: BoxDecoration(border: Border.all(color: Theme.of(c).dividerColor)),
              child: files.isEmpty
                  ? const Center(child: Text('SQLファイルを追加してください'))
                  : ReorderableListView(
                      onReorderItem: (a, b) => setState(() => files.insert(b, files.removeAt(a))),
                      children: [
                        for (final p in files)
                          ListTile(
                            key: ValueKey(p),
                            dense: true,
                            title: Text(_fileName(p), overflow: TextOverflow.ellipsis),
                            subtitle: Text(p, style: const TextStyle(fontSize: 10), overflow: TextOverflow.ellipsis),
                            trailing: IconButton(
                              icon: const Icon(Icons.close, size: 16),
                              tooltip: '外す',
                              onPressed: () => setState(() => files.remove(p)),
                            ),
                          ),
                      ],
                    ),
            ),
            const SizedBox(height: 12),
            const Text('取込先'),
            RadioGroup<bool>(
              groupValue: newModel,
              onChanged: (v) => setState(() => newModel = v ?? true),
              child: const Column(children: [
                RadioListTile<bool>(dense: true, title: Text('新しいモデル(未保存の無題として開く)'), value: true),
                RadioListTile<bool>(dense: true, title: Text('現在のモデルに追加'), value: false),
              ]),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text(Strings.cancel)),
          FilledButton(
            key: const ValueKey('importRun'),
            onPressed: files.isEmpty
                ? null
                : () => Navigator.pop(c, SqlImportOptions(postPath: post, files: List.of(files), newModel: newModel)),
            child: const Text('取り込む'),
          ),
        ],
      ),
    ),
  );
}

/// 取り込めなかったものを、別ファイルへ保存できる形のテキストにする(9.11-4)。
String unparsedAsText(List<UnparsedItem> items) {
  final b = StringBuffer('-- PERO SQLインポート: 取り込めなかった文(${items.length}件)\n\n');
  for (final u in items) {
    b.writeln('-- [${u.kind}] ${u.reason}${u.where.isEmpty ? '' : ' (${u.where})'}');
    if (u.text.isNotEmpty) b.writeln(u.text.endsWith(';') ? u.text : '${u.text};');
    b.writeln();
  }
  return b.toString();
}

/// SQLインポートの結果。件数、補足、取り込めなかったもの。[saveUnparsed] は、別ファイルへの保存(保存したパスを返す)。
Future<void> showSqlImportResult(
  BuildContext context, {
  required ImportReport report,
  required Future<String?> Function() saveUnparsed,
}) {
  String? saved;
  return showDialog<void>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, setState) => AlertDialog(
        title: const Text('SQLインポートが完了しました'),
        content: SizedBox(
          width: 640,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('取り込み: ${report.summary}'),
            if (report.notes.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('補足 ${report.notes.length}件'),
              SizedBox(
                height: 80,
                child: ListView(children: [
                  for (final n in report.notes)
                    ListTile(dense: true, leading: const Icon(Icons.info_outline, size: 18), title: Text(n)),
                ]),
              ),
            ],
            const SizedBox(height: 12),
            Text('取り込めなかったもの ${report.unparsed.length}件(ログにも記録しました)'),
            SizedBox(
              height: 200,
              child: report.unparsed.isEmpty
                  ? const Center(child: Text('なし'))
                  : ListView(children: [
                      for (final u in report.unparsed)
                        ListTile(
                          dense: true,
                          leading: const Icon(Icons.warning_amber, color: Colors.orange, size: 18),
                          title: Text('[${u.kind}] ${u.reason}', overflow: TextOverflow.ellipsis),
                          subtitle: Text(u.where, style: const TextStyle(fontSize: 10)),
                        ),
                    ]),
            ),
            if (saved != null) Padding(padding: const EdgeInsets.only(top: 8), child: SelectableText('保存しました: $saved')),
          ]),
        ),
        actions: [
          if (report.unparsed.isNotEmpty)
            TextButton(
              key: const ValueKey('importSaveUnparsed'),
              onPressed: () async {
                final p = await saveUnparsed();
                if (p != null) setState(() => saved = p);
              },
              child: const Text('取り込めなかった文を保存'),
            ),
          FilledButton(onPressed: () => Navigator.pop(c), child: const Text(Strings.close)),
        ],
      ),
    ),
  );
}
