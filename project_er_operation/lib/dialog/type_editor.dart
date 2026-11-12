import 'package:flutter/material.dart';

import '../command/command.dart';
import '../model/model.dart';
import 'common_dialogs.dart';
import 'form_widgets.dart';

/// 型の編集部品(6.3-4)。モデルの型管理ダイアログと、設定画面の型テーブルで共用する。
/// [types] は呼び出し側が持つ作業コピーで、この部品が直接書き換える。
class TypeEditor extends StatefulWidget {
  const TypeEditor({
    super.key,
    required this.types,
    required this.usageCount,
    required this.onReplacement,
    this.onChanged,
  });

  final List<DataType> types;

  /// 型を使っている列とビューの件数(使用中の型の削除と、パラメータ種別の変更不可に使う)。
  final int Function(String typeId) usageCount;

  /// 使用中の型を削除するときの置換先(削除する型ID, 置換先の型ID)。
  final void Function(String removedId, String replacementId) onReplacement;
  final VoidCallback? onChanged;

  @override
  State<TypeEditor> createState() => _TypeEditorState();
}

class _TypeEditorState extends State<TypeEditor> {
  String? _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.types.firstOrNull?.id;
  }

  DataType? get _cur => widget.types.where((t) => t.id == _selected).firstOrNull;

  void _changed() {
    widget.onChanged?.call();
    setState(() {});
  }

  void _add() {
    var n = 1;
    while (widget.types.any((t) => t.id == 'custom_$n')) {
      n++;
    }
    final t = DataType(
      id: 'custom_$n',
      displayName: 'custom_$n',
      category: TypeCategory.string,
      physical: {for (final d in DbKind.values) d: ''},
    );
    widget.types.add(t);
    _selected = t.id;
    _changed();
  }

  Future<void> _delete() async {
    final t = _cur;
    if (t == null || t.isStandard) return;
    final used = widget.usageCount(t.id);
    if (used > 0) {
      final candidates = widget.types.where((x) => x.id != t.id).toList();
      String? repl = candidates.firstOrNull?.id;
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => StatefulBuilder(
          builder: (c, setS) => AlertDialog(
            title: const Text('使用中の型の削除'),
            content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('「${t.displayName}」は $used 件で使用されています。置換先の型を選択してください。'),
              const SizedBox(height: 8),
              DropdownButton<String>(
                value: repl,
                items: [for (final x in candidates) DropdownMenuItem(value: x.id, child: Text(x.displayName))],
                onChanged: (v) => setS(() => repl = v),
              ),
            ]),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('キャンセル')),
              FilledButton(onPressed: repl == null ? null : () => Navigator.pop(c, true), child: const Text('置換して削除')),
            ],
          ),
        ),
      );
      if (ok != true || repl == null) return;
      widget.onReplacement(t.id, repl!);
    }
    widget.types.remove(t);
    _selected = widget.types.firstOrNull?.id;
    _changed();
  }

  void _resetTemplates(DataType t) {
    final std = standardTypes().where((x) => x.id == t.id).firstOrNull;
    if (std == null) return;
    t.physical
      ..clear()
      ..addAll(std.physical);
    _changed();
  }

  @override
  Widget build(BuildContext context) {
    final cur = _cur;
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(
        width: 230,
        child: Column(children: [
          Row(children: [
            TextButton.icon(onPressed: _add, icon: const Icon(Icons.add, size: 16), label: const Text('カスタム型を追加')),
          ]),
          Expanded(
            child: ListView(children: [
              for (final t in widget.types)
                ListTile(
                  dense: true,
                  selected: t.id == _selected,
                  title: Text(t.displayName),
                  subtitle: Text(t.isStandard ? '標準 / ${t.id}' : 'カスタム / ${t.id}'),
                  onTap: () => setState(() => _selected = t.id),
                ),
            ]),
          ),
        ]),
      ),
      const VerticalDivider(),
      Expanded(
        child: cur == null
            ? const SizedBox()
            : ListView(key: ValueKey('t${cur.id}'), children: [
                Row(children: [
                  Expanded(
                    child: textField('表示名', cur.displayName, (v) {
                      cur.displayName = v;
                      widget.onChanged?.call();
                    }, key: ValueKey('dn${cur.id}'), enabled: !cur.isStandard),
                  ),
                  if (!cur.isStandard)
                    TextButton.icon(onPressed: _delete, icon: const Icon(Icons.delete_outline, size: 16), label: const Text('削除')),
                ]),
                Row(children: [
                  Expanded(
                    child: DropdownButtonFormField<ParamKind>(
                      key: ValueKey('pk${cur.id}${cur.paramKind}'),
                      initialValue: cur.paramKind,
                      decoration: InputDecoration(
                        labelText: 'パラメータ種別',
                        isDense: true,
                        border: const OutlineInputBorder(),
                        helperText: widget.usageCount(cur.id) > 0 ? '使用中の型は変更できません' : null,
                      ),
                      items: const [
                        DropdownMenuItem(value: ParamKind.none, child: Text('なし')),
                        DropdownMenuItem(value: ParamKind.length, child: Text('長さ')),
                        DropdownMenuItem(value: ParamKind.precisionScale, child: Text('精度とスケール')),
                      ],
                      onChanged: cur.isStandard || widget.usageCount(cur.id) > 0
                          ? null
                          : (v) {
                              cur.paramKind = v ?? ParamKind.none;
                              _changed();
                            },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonFormField<TypeCategory>(
                      key: ValueKey('cat${cur.id}${cur.category}'),
                      initialValue: cur.category,
                      decoration: const InputDecoration(labelText: 'カテゴリ', isDense: true, border: OutlineInputBorder()),
                      items: [for (final c in TypeCategory.values) DropdownMenuItem(value: c, child: Text(c.wire))],
                      onChanged: cur.isStandard
                          ? null
                          : (v) {
                              cur.category = v ?? TypeCategory.string;
                              _changed();
                            },
                    ),
                  ),
                ]),
                if (cur.paramKind == ParamKind.length)
                  textField('既定の長さ', '${cur.defaultLength ?? ''}', (v) => cur.defaultLength = int.tryParse(v),
                      key: ValueKey('dl${cur.id}'), enabled: !cur.isStandard, keyboardType: TextInputType.number),
                if (cur.paramKind == ParamKind.precisionScale)
                  Row(children: [
                    Expanded(
                        child: textField('既定の精度', '${cur.defaultPrecision ?? ''}', (v) => cur.defaultPrecision = int.tryParse(v),
                            key: ValueKey('dp${cur.id}'), enabled: !cur.isStandard, keyboardType: TextInputType.number)),
                    const SizedBox(width: 8),
                    Expanded(
                        child: textField('既定のスケール', '${cur.defaultScale ?? ''}', (v) => cur.defaultScale = int.tryParse(v),
                            key: ValueKey('ds${cur.id}'), enabled: !cur.isStandard, keyboardType: TextInputType.number)),
                  ]),
                const SizedBox(height: 8),
                Row(children: [
                  const Expanded(child: Text('対象DBごとの物理名テンプレート({length} {precision} {scale} を置換)')),
                  if (cur.isStandard)
                    TextButton(onPressed: () => _resetTemplates(cur), child: const Text('初期値に戻す')),
                ]),
                PerDbTabs(
                  key: ValueKey('tpl${cur.id}${cur.physical.hashCode}'),
                  height: 90,
                  entries: [('物理名テンプレート', _templates(cur), false)],
                ),
              ]),
      ),
    ]);
  }

  /// テンプレート欄の編集を [DataType.physical] へ反映するためのMap(書込みは直接行う)。
  Map<DbKind, String> _templates(DataType t) => t.physical;
}

/// モデルの型管理ダイアログ(操作メニュー)。OKで (型一覧, 削除する型の置換先) を返す。
Future<(List<DataType>, Map<String, String>)?> showTypeManagerDialog(BuildContext context, ErModel model) {
  final work = model.types.map((t) => t.copy()).toList();
  final repl = <String, String>{};
  return showDialog<(List<DataType>, Map<String, String>)>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('型管理'),
      content: SizedBox(
        width: 860,
        height: 520,
        child: TypeEditor(
          types: work,
          usageCount: (id) => DeleteTypeCommand.usageCount(model, id),
          onReplacement: (id, r) => repl[id] = r,
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('キャンセル')),
        FilledButton(
          onPressed: () {
            if (work.any((t) => t.displayName.trim().isEmpty)) {
              showMessageDialog(c, title: '入力エラー', message: '表示名を入力してください');
              return;
            }
            Navigator.pop(c, (work, repl));
          },
          child: const Text('OK'),
        ),
      ],
    ),
  );
}
