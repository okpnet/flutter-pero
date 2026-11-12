import 'package:flutter/material.dart';

import '../command/command.dart';
import '../common/common.dart';
import '../model/model.dart';
import 'common_dialogs.dart';
import 'form_widgets.dart';

/// メソッド管理ダイアログ(8.1-2)。OKで編集後のメソッド一覧を返す。キャンセルはnull。
/// 削除したメソッドの参照は、OK時にコマンドが解除する(1コマンド)。
Future<List<MethodDef>?> showMethodDialog(
  BuildContext context,
  ErModel model, {
  required String nameFormat,
  MethodKind initialKind = MethodKind.function,
  int? selectId,
}) {
  return showDialog<List<MethodDef>>(
    context: context,
    builder: (c) => _MethodDialog(model: model, nameFormat: nameFormat, initialKind: initialKind, selectId: selectId),
  );
}

class _MethodDialog extends StatefulWidget {
  const _MethodDialog({required this.model, required this.nameFormat, required this.initialKind, this.selectId});
  final ErModel model;
  final String nameFormat;
  final MethodKind initialKind;
  final int? selectId;

  @override
  State<_MethodDialog> createState() => _MethodDialogState();
}

class _MethodDialogState extends State<_MethodDialog> {
  late final List<MethodDef> _work = widget.model.methods.map((m) => m.copy()).toList();
  late final LocalIds _ids = LocalIds(widget.model.nextId);
  late MethodKind _kind = widget.initialKind;
  int? _selected;
  String? _error;

  @override
  void initState() {
    super.initState();
    _selected = widget.selectId ?? _work.where((m) => m.kind == _kind).firstOrNull?.id;
    final sel = _work.where((m) => m.id == _selected).firstOrNull;
    if (sel != null) _kind = sel.kind;
  }

  MethodDef? get _current => _work.where((m) => m.id == _selected).firstOrNull;

  void _add() {
    setState(() {
      final base = _kind == MethodKind.function ? 'function' : 'trigger';
      final used = _work.map((m) => m.name.toLowerCase()).toSet();
      var n = 1;
      while (used.contains('${base}_$n')) {
        n++;
      }
      final m = MethodDef(id: _ids.next(), kind: _kind, name: '${base}_$n');
      _work.add(m);
      _selected = m.id;
    });
  }

  Future<void> _delete() async {
    final m = _current;
    if (m == null) return;
    final refs = DeleteMethodCommand.references(widget.model, m.id);
    if (refs.isNotEmpty) {
      final viewRefs = widget.model.views.where((v) => v.viewType == ViewType.function && v.function.methodId == m.id);
      if (viewRefs.isNotEmpty) {
        await showMessageDialog(context,
            title: '削除できません', message: '関数ビューが参照しています。先にビューを修正してください:\n${refs.join('\n')}');
        return;
      }
      final ok = await showConfirmDialog(context,
          title: 'メソッドの削除',
          message: '次から参照されています。削除すると参照を解除します(列のデフォルトは「なし」、トリガー行は削除)。\n\n${refs.join('\n')}');
      if (!ok) return;
    }
    setState(() {
      _work.remove(m);
      _selected = _work.where((x) => x.kind == _kind).firstOrNull?.id;
    });
  }

  String? _nameError(MethodDef m) {
    final e = nameFormatError(m.name, widget.nameFormat);
    if (e != null) return e;
    if (_work.any((x) => x.id != m.id && x.name.toLowerCase() == m.name.toLowerCase())) {
      return '同じ名前のメソッドが存在します';
    }
    return null;
  }

  void _ok() {
    for (final m in _work) {
      final e = _nameError(m);
      if (e != null) {
        setState(() {
          _selected = m.id;
          _kind = m.kind;
          _error = 'メソッド「${m.name}」: $e';
        });
        return;
      }
    }
    Navigator.pop(context, _work);
  }

  /// 依存テーブル(8.1-3)。これらのテーブルの作成後にファンクションを出力する。
  Widget _dependsOn(MethodDef cur) {
    final tables = widget.model.entities.toList();
    final selected = [
      for (final id in cur.dependsOnTableIds)
        if (tables.any((t) => t.id == id)) tables.firstWhere((t) => t.id == id)
    ];
    return Column(
      key: ValueKey('dep${cur.id}${cur.dependsOnTableIds.length}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 4),
        const Text('依存テーブル・ビュー(作成後にこのファンクションを出力)'),
        Wrap(spacing: 6, runSpacing: 4, children: [
          for (final t in selected)
            InputChip(
              label: Text(t.physicalName, style: const TextStyle(fontSize: 11)),
              onDeleted: () => setState(() => cur.dependsOnTableIds.remove(t.id)),
            ),
        ]),
        Autocomplete<Entity>(
          displayStringForOption: (t) => t.physicalName,
          optionsBuilder: (v) {
            final q = v.text.toLowerCase();
            return tables
                .where((t) =>
                    !cur.dependsOnTableIds.contains(t.id) &&
                    (q.isEmpty ||
                        t.physicalName.toLowerCase().contains(q) ||
                        t.logicalName.toLowerCase().contains(q)))
                .take(30);
          },
          onSelected: (t) => setState(() => cur.dependsOnTableIds.add(t.id)),
          fieldViewBuilder: (context, controller, focus, onSubmit) => TextField(
            controller: controller,
            focusNode: focus,
            style: const TextStyle(fontSize: 13),
            decoration: const InputDecoration(
              labelText: 'テーブル・ビューを検索して追加',
              isDense: true,
              border: OutlineInputBorder(),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final list = _work.where((m) => m.kind == _kind).toList();
    final cur = _current;
    return AlertDialog(
      title: const Text('メソッド管理'),
      content: SizedBox(
        width: 860,
        height: 520,
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: 250,
            child: Column(children: [
              SegmentedButton<MethodKind>(
                segments: const [
                  ButtonSegment(value: MethodKind.function, label: Text('ファンクション')),
                  ButtonSegment(value: MethodKind.trigger, label: Text('トリガー')),
                ],
                selected: {_kind},
                onSelectionChanged: (s) => setState(() {
                  _kind = s.first;
                  _selected = _work.where((m) => m.kind == _kind).firstOrNull?.id;
                }),
              ),
              Row(children: [
                TextButton.icon(onPressed: _add, icon: const Icon(Icons.add, size: 16), label: const Text('追加')),
                TextButton.icon(onPressed: cur == null ? null : _delete, icon: const Icon(Icons.delete_outline, size: 16), label: const Text('削除')),
              ]),
              Expanded(
                child: ListView(children: [
                  for (final m in list)
                    ListTile(
                      dense: true,
                      selected: m.id == _selected,
                      title: Text(m.name.isEmpty ? '(名前なし)' : m.name),
                      subtitle: m.external ? const Text('外部定義') : null,
                      onTap: () => setState(() => _selected = m.id),
                    ),
                ]),
              ),
            ]),
          ),
          const VerticalDivider(),
          Expanded(
            child: cur == null
                ? const Center(child: Text('メソッドを選択、または追加してください'))
                : ListView(key: ValueKey('m${cur.id}'), children: [
                    textField('名前', cur.name, (v) => setState(() => cur.name = v),
                        key: ValueKey('name${cur.id}'), error: _nameError(cur)),
                    if (cur.kind == MethodKind.function)
                      CheckboxListTile(
                        dense: true,
                        controlAffinity: ListTileControlAffinity.leading,
                        title: const Text('外部定義(定義のCREATE文を出力しない)'),
                        value: cur.external,
                        onChanged: (v) => setState(() => cur.external = v ?? false),
                      ),
                    textField('コメント(COMMENT ON FUNCTION で出力)', cur.comment, (v) => cur.comment = v,
                        key: ValueKey('mc${cur.id}'), multiline: true),
                    textField('引数の定義(COMMENT ON FUNCTION 名前(引数) の括弧の内側)', cur.args, (v) => cur.args = v,
                        key: ValueKey('ma${cur.id}')),
                    if (cur.kind == MethodKind.function && !cur.external) _dependsOn(cur),
                    const SizedBox(height: 4),
                    Text(cur.kind == MethodKind.function ? '対象DBごとの呼出し式・本体' : '対象DBごとのトリガー本体'),
                    PerDbTabs(height: 330, entries: [
                      if (cur.kind == MethodKind.function) ('呼出し式(省略時は {名前}())', cur.call, false),
                      (cur.kind == MethodKind.function ? '本体(CREATE文)' : '本体', cur.bodies, true),
                    ]),
                  ]),
          ),
        ]),
      ),
      actions: [
        if (_error != null) Padding(padding: const EdgeInsets.only(right: 12), child: Text(_error!, style: const TextStyle(color: Colors.red))),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text(Strings.cancel)),
        FilledButton(onPressed: _ok, child: const Text(Strings.ok)),
      ],
    );
  }
}
