import 'package:flutter/material.dart';

import '../common/common.dart';

Future<void> showMessageDialog(BuildContext context,
    {required String title, required String message, String? detail}) {
  return showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 420),
        child: SingleChildScrollView(
          child: SelectableText('$message${detail == null ? '' : '\n\n$detail'}'),
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text(Strings.close))],
    ),
  );
}

/// はい / いいえの確認。
Future<bool> showConfirmDialog(BuildContext context,
    {required String title,
    required String message,
    String yes = Strings.yes,
    String no = Strings.no}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 420),
        child: SingleChildScrollView(child: SelectableText(message)),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: Text(no)),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(yes)),
      ],
    ),
  );
  return r ?? false;
}

enum UnsavedChoice { save, discard, cancel }

/// 未保存確認(4.1-8): 保存 / 保存しない / キャンセル。
Future<UnsavedChoice> showUnsavedDialog(BuildContext context) async {
  final r = await showDialog<UnsavedChoice>(
    context: context,
    barrierDismissible: false,
    builder: (c) => AlertDialog(
      title: const Text(Strings.unsavedTitle),
      content: const Text(Strings.unsavedMessage),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, UnsavedChoice.cancel), child: const Text(Strings.cancel)),
        TextButton(onPressed: () => Navigator.pop(c, UnsavedChoice.discard), child: const Text(Strings.dontSave)),
        FilledButton(onPressed: () => Navigator.pop(c, UnsavedChoice.save), child: const Text(Strings.save)),
      ],
    ),
  );
  return r ?? UnsavedChoice.cancel;
}

/// 1行の文字列入力。キャンセル時はnull。[validator] はエラー文言を返す。
Future<String?> showTextPrompt(BuildContext context,
    {required String title,
    required String initial,
    String? Function(String)? validator}) {
  final ctrl = TextEditingController(text: initial);
  String? error;
  return showDialog<String>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, setState) {
        void submit() {
          final err = validator?.call(ctrl.text);
          if (err != null) {
            setState(() => error = err);
            return;
          }
          Navigator.pop(c, ctrl.text);
        }

        return AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 320,
            child: TextField(
              controller: ctrl,
              autofocus: true,
              decoration: InputDecoration(errorText: error),
              onSubmitted: (_) => submit(),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text(Strings.cancel)),
            FilledButton(onPressed: submit, child: const Text(Strings.ok)),
          ],
        );
      },
    ),
  );
}
