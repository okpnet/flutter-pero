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

  void _add([TypeKind kind = TypeKind.scalar]) {
    var n = 1;
    while (widget.types.any((t) => t.id == 'custom_$n')) {
      n++;
    }
    final base = switch (kind) {
      TypeKind.scalar => 'custom_$n',
      TypeKind.composite => 'composite_$n',
      TypeKind.enumeration => 'enum_$n',
    };
    final t = DataType(
      id: 'custom_$n',
      displayName: base,
      category: TypeCategory.string,
      physical: {
        for (final d in DbKind.values) d: kind == TypeKind.scalar || d != DbKind.postgresql ? '' : base,
      },
      kind: kind,
      fields: kind == TypeKind.composite ? [TypeField(name: 'field_1', typeId: 'integer')] : null,
      enumValues: kind == TypeKind.enumeration ? ['value_1'] : null,
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
            PopupMenuButton<TypeKind>(
              tooltip: '型を追加',
              onSelected: _add,
              itemBuilder: (c) => const [
                PopupMenuItem(value: TypeKind.scalar, child: Text('カスタム型')),
                PopupMenuItem(value: TypeKind.composite, child: Text('複合型(CREATE TYPE ... AS)')),
                PopupMenuItem(value: TypeKind.enumeration, child: Text('列挙型(CREATE TYPE ... AS ENUM)')),
              ],
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.add, size: 16),
                  SizedBox(width: 4),
                  Text('型を追加'),
                ]),
              ),
            ),
          ]),
          Expanded(
            child: ListView(children: [
              for (final t in widget.types)
                ListTile(
                  dense: true,
                  selected: t.id == _selected,
                  title: Text(t.displayName),
                  subtitle: Text(t.isStandard
                      ? '標準 / ${t.id}'
                      : '${switch (t.kind) { TypeKind.scalar => 'カスタム', TypeKind.composite => '複合型', TypeKind.enumeration => '列挙型' }} / ${t.id}'),
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
            : cur.isUserDefined
                ? _userDefined(cur)
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

  /// ユーザー定義型(複合型、列挙型)の編集。名前は PostgreSQL の物理名になる(6.3-2)。
  Widget _userDefined(DataType cur) {
    final isComposite = cur.kind == TypeKind.composite;
    return ListView(key: ValueKey('u${cur.id}'), children: [
      Row(children: [
        Expanded(
          child: textField('型の名前(PostgreSQL)', cur.physical[DbKind.postgresql] ?? '', (v) {
            cur.physical[DbKind.postgresql] = v;
            cur.displayName = v;
            widget.onChanged?.call();
          }, key: ValueKey('un${cur.id}')),
        ),
        TextButton.icon(onPressed: _delete, icon: const Icon(Icons.delete_outline, size: 16), label: const Text('削除')),
      ]),
      textField('スキーマ(空でモデルのスキーマ)', cur.schema, (v) {
        cur.schema = v;
        widget.onChanged?.call();
      }, key: ValueKey('us${cur.id}')),
      textField('コメント(COMMENT ON TYPE で出力)', cur.comment, (v) {
        cur.comment = v;
        widget.onChanged?.call();
      }, key: ValueKey('uc${cur.id}'), multiline: true),
      const SizedBox(height: 8),
      if (isComposite) ...[
        Row(children: [
          const Expanded(child: Text('項目')),
          TextButton.icon(
            onPressed: () {
              var n = 1;
              while (cur.fields.any((f) => f.name == 'field_$n')) {
                n++;
              }
              cur.fields.add(TypeField(name: 'field_$n', typeId: 'integer'));
              _changed();
            },
            icon: const Icon(Icons.add, size: 16),
            label: const Text('追加'),
          ),
        ]),
        for (var i = 0; i < cur.fields.length; i++)
          Card(
            key: ValueKey('uf${cur.id}$i${cur.fields.length}'),
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Column(children: [
                Row(children: [
                  Expanded(
                    child: textField('項目名', cur.fields[i].name, (v) {
                      cur.fields[i].name = v;
                      widget.onChanged?.call();
                    }, key: ValueKey('ufn${cur.id}$i${cur.fields.length}')),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 18),
                    onPressed: () {
                      cur.fields.removeAt(i);
                      _changed();
                    },
                  ),
                ]),
                TypeAndParams(
                  types: [for (final t in widget.types) if (t.id != cur.id) t],
                  typeId: cur.fields[i].typeId,
                  length: cur.fields[i].length,
                  precision: cur.fields[i].precision,
                  scale: cur.fields[i].scale,
                  onChanged: (t, l, p, s) {
                    final f = cur.fields[i];
                    f.typeId = t;
                    f.length = l;
                    f.precision = p;
                    f.scale = s;
                    _changed();
                  },
                ),
              ]),
            ),
          ),
      ] else
        textField('値(1行に1つ)', cur.enumValues.join('\n'), (v) {
          cur.enumValues = [for (final s in v.split('\n')) if (s.trim().isNotEmpty) s.trim()];
          widget.onChanged?.call();
        }, key: ValueKey('uv${cur.id}'), multiline: true),
      const SizedBox(height: 8),
      Text('PostgreSQL以外の対象DBでは使えません(物理名が空のため生成前検証でエラーになります)。',
          style: Theme.of(context).textTheme.bodySmall),
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
