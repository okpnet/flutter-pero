import 'package:flutter/material.dart';

import '../common/common.dart';
import '../model/model.dart';
import 'form_widgets.dart';

/// 共通列パターン管理ダイアログ(8.2-2)。OKで編集後のパターン一覧(並び順つき)を返す。
Future<List<CommonColumnPattern>?> showPatternDialog(
  BuildContext context,
  ErModel model, {
  required String nameFormat,
}) {
  return showDialog<List<CommonColumnPattern>>(
    context: context,
    builder: (c) => _PatternDialog(model: model, nameFormat: nameFormat),
  );
}

class _PatternDialog extends StatefulWidget {
  const _PatternDialog({required this.model, required this.nameFormat});
  final ErModel model;
  final String nameFormat;

  @override
  State<_PatternDialog> createState() => _PatternDialogState();
}

class _PatternDialogState extends State<_PatternDialog> {
  late final List<CommonColumnPattern> _work = widget.model.patterns.map((p) => p.copy()).toList();
  late final LocalIds _ids = LocalIds(widget.model.nextId);
  int? _selected;
  String _testName = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    _selected = _work.firstOrNull?.id;
  }

  CommonColumnPattern? get _cur => _work.where((p) => p.id == _selected).firstOrNull;

  void _add() => setState(() {
        final used = _work.map((p) => p.name).toSet();
        var n = 1;
        while (used.contains('パターン$n')) {
          n++;
        }
        final p = CommonColumnPattern(id: _ids.next(), name: 'パターン$n');
        _work.add(p);
        _selected = p.id;
      });

  void _delete() => setState(() {
        _work.removeWhere((p) => p.id == _selected);
        _selected = _work.firstOrNull?.id;
      });

  String? _nameError(CommonColumnPattern p) {
    if (p.name.trim().isEmpty) return '名前は必須です';
    if (_work.any((x) => x.id != p.id && x.name == p.name)) return '同じ名前のパターンが存在します';
    return null;
  }

  String? _colError(CommonColumnPattern p, ColumnDef c) {
    final e = nameFormatError(c.physicalName, widget.nameFormat);
    if (e != null) return e;
    if (p.columns.any((x) => x.id != c.id && x.physicalName.toLowerCase() == c.physicalName.toLowerCase())) {
      return '同じ列名があります';
    }
    return null;
  }

  void _ok() {
    for (final p in _work) {
      final e = _nameError(p) ?? p.columns.map((c) => _colError(p, c)).whereType<String>().firstOrNull;
      if (e != null) {
        setState(() {
          _selected = p.id;
          _error = 'パターン「${p.name}」: $e';
        });
        return;
      }
    }
    Navigator.pop(context, _work);
  }

  /// 現在のモデルで対象になるテーブル(有効/無効にかかわらず、フィルタだけで判定)。
  List<String> _matching(CommonColumnPattern p) {
    final probe = p.copy()..enabled = true;
    return [for (final t in widget.model.tables) if (probe.appliesTo(t.physicalName)) t.physicalName];
  }

  @override
  Widget build(BuildContext context) {
    final cur = _cur;
    return AlertDialog(
      title: const Text('共通列パターン管理'),
      content: SizedBox(
        width: 900,
        height: 560,
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: 230,
            child: Column(children: [
              Row(children: [
                TextButton.icon(onPressed: _add, icon: const Icon(Icons.add, size: 16), label: const Text('追加')),
                TextButton.icon(onPressed: cur == null ? null : _delete, icon: const Icon(Icons.delete_outline, size: 16), label: const Text('削除')),
              ]),
              Expanded(
                child: ReorderableListView(
                  buildDefaultDragHandles: true,
                  onReorderItem: (from, to) => setState(() => _work.insert(to, _work.removeAt(from))),
                  children: [
                    for (final p in _work)
                      ListTile(
                        key: ValueKey('p${p.id}'),
                        dense: true,
                        selected: p.id == _selected,
                        title: Text(p.name, style: TextStyle(color: !p.isRegexValid ? Colors.red : null)),
                        subtitle: Text(p.enabled ? (p.position == PatternPosition.start ? '先頭' : '末尾') : '無効'),
                        onTap: () => setState(() => _selected = p.id),
                      ),
                  ],
                ),
              ),
            ]),
          ),
          const VerticalDivider(),
          Expanded(child: cur == null ? const Center(child: Text('パターンを追加してください')) : _detail(cur)),
        ]),
      ),
      actions: [
        if (_error != null) Padding(padding: const EdgeInsets.only(right: 12), child: Text(_error!, style: const TextStyle(color: Colors.red))),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text(Strings.cancel)),
        FilledButton(onPressed: _ok, child: const Text(Strings.ok)),
      ],
    );
  }

  Widget _detail(CommonColumnPattern p) {
    final matching = _matching(p);
    final probe = p.copy()..enabled = true;
    final testResult = _testName.isEmpty ? null : probe.appliesTo(_testName);
    return ListView(key: ValueKey('pd${p.id}'), children: [
      Row(children: [
        Expanded(child: textField('名前', p.name, (v) => setState(() => p.name = v), key: ValueKey('pn${p.id}'), error: _nameError(p))),
        const SizedBox(width: 8),
        Switch(value: p.enabled, onChanged: (v) => setState(() => p.enabled = v)),
        Text(p.enabled ? '有効' : '無効'),
      ]),
      Row(children: [
        Expanded(
          child: textField('対象フィルタ(正規表現・全体一致)', p.include, (v) => setState(() => p.include = v),
              key: ValueKey('pi${p.id}'), error: _regexError(p.include)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: textField('除外フィルタ(任意)', p.exclude, (v) => setState(() => p.exclude = v),
              key: ValueKey('pe${p.id}'), error: p.exclude.isEmpty ? null : _regexError(p.exclude)),
        ),
      ]),
      Row(children: [
        const Text('位置: '),
        SegmentedButton<PatternPosition>(
          segments: const [
            ButtonSegment(value: PatternPosition.start, label: Text('先頭')),
            ButtonSegment(value: PatternPosition.end, label: Text('末尾')),
          ],
          selected: {p.position},
          onSelectionChanged: (s) => setState(() => p.position = s.first),
        ),
      ]),
      const SizedBox(height: 6),
      Row(children: [
        Expanded(
          child: textField('試験: テーブル物理名を入力', _testName, (v) => setState(() => _testName = v), key: const ValueKey('ptest')),
        ),
        const SizedBox(width: 8),
        if (testResult != null)
          Text(testResult ? '一致' : '不一致', style: TextStyle(color: testResult ? Colors.green : Colors.red, fontWeight: FontWeight.bold)),
      ]),
      Text('現在のモデルで一致するテーブル(${matching.length}件): ${matching.join(', ')}', style: Theme.of(context).textTheme.bodySmall),
      const Divider(),
      Row(children: [
        const Expanded(child: Text('列(PKは指定できません)')),
        TextButton.icon(
          onPressed: () => setState(() {
            var n = 1;
            while (p.columns.any((c) => c.physicalName == 'column_$n')) {
              n++;
            }
            p.columns.add(ColumnDef(id: _ids.next(), logicalName: '列$n', physicalName: 'column_$n', typeId: 'varchar', length: 255));
          }),
          icon: const Icon(Icons.add, size: 16),
          label: const Text('列を追加'),
        ),
      ]),
      for (final c in p.columns) _column(p, c),
    ]);
  }

  String? _regexError(String src) {
    try {
      RegExp(src);
      return null;
    } on FormatException {
      return '正規表現が不正です';
    }
  }

  Widget _column(CommonColumnPattern p, ColumnDef c) {
    final methods = widget.model.methods.where((m) => m.kind == MethodKind.function).toList();
    return Card(
      key: ValueKey('pc${c.id}'),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Column(children: [
          Row(children: [
            Expanded(child: textField('論理名', c.logicalName, (v) => c.logicalName = v, key: ValueKey('cl${c.id}'))),
            const SizedBox(width: 4),
            Expanded(
              child: textField('物理名', c.physicalName, (v) => setState(() => c.physicalName = v),
                  key: ValueKey('cp${c.id}'), error: _colError(p, c)),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 18),
              onPressed: () => setState(() => p.columns.remove(c)),
            ),
          ]),
          TypeAndParams(
            types: widget.model.types,
            typeId: c.typeId,
            length: c.length,
            precision: c.precision,
            scale: c.scale,
            onChanged: (t, l, pr, s) => setState(() {
              c.typeId = t;
              c.length = l;
              c.precision = pr;
              c.scale = s;
              if (widget.model.typeById(t)?.category == TypeCategory.auto) c.defaultKind = DefaultKind.none;
            }),
          ),
          Row(children: [
            Checkbox(value: c.notNull, onChanged: (v) => setState(() => c.notNull = v ?? false)),
            const Text('NotNull'),
            const SizedBox(width: 12),
            SizedBox(
              width: 140,
              child: DropdownButtonFormField<DefaultKind>(
                key: ValueKey('dk${c.id}${c.defaultKind}'),
                initialValue: c.defaultKind,
                decoration: const InputDecoration(labelText: 'デフォルト', isDense: true, border: OutlineInputBorder()),
                items: const [
                  DropdownMenuItem(value: DefaultKind.none, child: Text('なし')),
                  DropdownMenuItem(value: DefaultKind.value, child: Text('値')),
                  DropdownMenuItem(value: DefaultKind.method, child: Text('メソッド')),
                  DropdownMenuItem(value: DefaultKind.expression, child: Text('式')),
                ],
                onChanged: (v) => setState(() => c.defaultKind = v ?? DefaultKind.none),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: c.defaultKind == DefaultKind.method
                  ? DropdownButtonFormField<int>(
                      key: ValueKey('dm${c.id}${c.defaultMethodId}'),
                      initialValue: methods.any((m) => m.id == c.defaultMethodId) ? c.defaultMethodId : null,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'メソッド', isDense: true, border: OutlineInputBorder()),
                      items: [for (final m in methods) DropdownMenuItem(value: m.id, child: Text(m.name))],
                      onChanged: (v) => setState(() => c.defaultMethodId = v),
                    )
                  : c.defaultKind == DefaultKind.expression
                      ? textField('式(そのまま出力)', c.defaultExpression, (v) => c.defaultExpression = v,
                          key: ValueKey('de${c.id}'))
                      : textField('値', c.defaultValue, (v) => c.defaultValue = v,
                          key: ValueKey('dv${c.id}'), enabled: c.defaultKind == DefaultKind.value),
            ),
          ]),
          textField('コメント', c.comment, (v) => c.comment = v, key: ValueKey('cc${c.id}')),
        ]),
      ),
    );
  }
}
