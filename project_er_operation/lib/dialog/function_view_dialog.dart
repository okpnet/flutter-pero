import 'package:flutter/material.dart';

import '../common/common.dart';
import '../model/model.dart';
import '../persistence/persistence.dart';
import 'form_widgets.dart';

/// 関数ビューの定義ダイアログ(6.6-8)。OKで定義済みのビューを返す(新規はIDが0)。
/// [initial] がnullのとき新規。[onManageMethods] は、メソッド選択欄の「…」(メソッド管理を開く)。
Future<ViewEntity?> showFunctionViewDialog(
  BuildContext context,
  ErModel model, {
  required String nameFormat,
  ViewEntity? initial,
  required Future<void> Function() onManageMethods,
}) {
  return showDialog<ViewEntity>(
    context: context,
    builder: (c) => _FunctionViewDialog(model: model, nameFormat: nameFormat, initial: initial, onManageMethods: onManageMethods),
  );
}

class _FunctionViewDialog extends StatefulWidget {
  const _FunctionViewDialog({required this.model, required this.nameFormat, this.initial, required this.onManageMethods});
  final ErModel model;
  final String nameFormat;
  final ViewEntity? initial;
  final Future<void> Function() onManageMethods;

  @override
  State<_FunctionViewDialog> createState() => _FunctionViewDialogState();
}

class _FunctionViewDialogState extends State<_FunctionViewDialog> {
  late final ViewEntity _v = widget.initial?.copy() ??
      ViewEntity(id: 0, viewType: ViewType.function, physicalName: _defaultName());
  String? _error;
  int _gen = 0;

  String _defaultName() {
    final used = widget.model.entities.map((e) => e.physicalName.toLowerCase()).toSet();
    var n = 1;
    while (used.contains('view_$n')) {
      n++;
    }
    return 'view_$n';
  }

  ErModel get _m => widget.model;

  String? _physicalError() {
    final e = nameFormatError(_v.physicalName, widget.nameFormat);
    if (e != null) return e;
    if (_m.entities.any((x) => x.id != _v.id && x.physicalName.toLowerCase() == _v.physicalName.toLowerCase())) {
      return '同じ物理名のエンティティが存在します';
    }
    return null;
  }

  String? _colError(FunctionReturnColumn c) {
    final e = nameFormatError(c.name, widget.nameFormat);
    if (e != null) return e;
    if (_v.function.columns.any((x) => !identical(x, c) && x.name.toLowerCase() == c.name.toLowerCase())) {
      return '戻り列名が重複しています';
    }
    return null;
  }

  void _ok() {
    final f = _v.function;
    final err = _physicalError() ??
        (f.methodId == null || _m.methodById(f.methodId!) == null ? '関数を選択してください' : null) ??
        (f.columns.isEmpty ? '戻り列を1つ以上入力してください' : null) ??
        f.columns.map(_colError).whereType<String>().firstOrNull;
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    _v.viewType = ViewType.function;
    Navigator.pop(context, _v);
  }

  @override
  Widget build(BuildContext context) {
    final f = _v.function;
    final methods = _m.methods.where((x) => x.kind == MethodKind.function).toList();
    return AlertDialog(
      title: Text(widget.initial == null ? '関数ビューの追加' : '関数ビューの定義を編集'),
      content: SizedBox(
        width: 720,
        height: 540,
        child: ListView(key: ValueKey(_gen), children: [
          Row(children: [
            Expanded(child: textField('論理名', _v.logicalName, (v) => _v.logicalName = v, key: const ValueKey('vl'))),
            const SizedBox(width: 8),
            Expanded(
              child: textField('物理名', _v.physicalName, (v) => setState(() => _v.physicalName = v),
                  key: const ValueKey('vp'), error: _physicalError()),
            ),
          ]),
          textField('コメント', _v.comment, (v) => _v.comment = v, key: const ValueKey('vc')),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(
              child: DropdownButtonFormField<int>(
                key: ValueKey('method${f.methodId}$_gen'),
                initialValue: methods.any((x) => x.id == f.methodId) ? f.methodId : null,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'メソッド(種別がファンクション)', isDense: true, border: OutlineInputBorder()),
                items: [for (final x in methods) DropdownMenuItem(value: x.id, child: Text(x.name))],
                onChanged: (v) => setState(() => f.methodId = v),
              ),
            ),
            IconButton(
              tooltip: 'メソッド管理を開く',
              icon: const Icon(Icons.more_horiz),
              onPressed: () async {
                await widget.onManageMethods();
                if (mounted) setState(() => _gen++);
              },
            ),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            const Expanded(child: Text('引数(式として、そのまま出力)')),
            TextButton.icon(
                onPressed: () => setState(() => f.args.add('')), icon: const Icon(Icons.add, size: 16), label: const Text('追加')),
          ]),
          for (var i = 0; i < f.args.length; i++)
            Row(key: ValueKey('arg$i$_gen'), children: [
              Expanded(child: textField('引数${i + 1}', f.args[i], (v) => f.args[i] = v, key: ValueKey('a$i$_gen'))),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 18),
                onPressed: () => setState(() {
                  f.args.removeAt(i);
                  _gen++;
                }),
              ),
            ]),
          const SizedBox(height: 8),
          Row(children: [
            const Expanded(child: Text('戻り列(名前と型を入力)')),
            TextButton.icon(
              onPressed: () => setState(() {
                var n = 1;
                while (f.columns.any((c) => c.name == 'column_$n')) {
                  n++;
                }
                f.columns.add(FunctionReturnColumn(name: 'column_$n', typeId: 'integer'));
              }),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('追加'),
            ),
          ]),
          for (final c in f.columns)
            Card(
              key: ValueKey('rc${f.columns.indexOf(c)}$_gen'),
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Column(children: [
                  Row(children: [
                    Expanded(child: textField('論理名', c.logicalName, (v) => c.logicalName = v, key: ValueKey('rl${f.columns.indexOf(c)}$_gen'))),
                    const SizedBox(width: 4),
                    Expanded(
                      child: textField('列名', c.name, (v) => setState(() => c.name = v),
                          key: ValueKey('rn${f.columns.indexOf(c)}$_gen'), error: _colError(c)),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 18),
                      onPressed: () => setState(() {
                        f.columns.remove(c);
                        _gen++;
                      }),
                    ),
                  ]),
                  TypeAndParams(
                    types: _m.types,
                    typeId: c.typeId,
                    length: c.length,
                    precision: c.precision,
                    scale: c.scale,
                    onChanged: (t, l, p, s) => setState(() {
                      c.typeId = t;
                      c.length = l;
                      c.precision = p;
                      c.scale = s;
                    }),
                  ),
                ]),
              ),
            ),
          const SizedBox(height: 4),
          Text('出力: SELECT * FROM <メソッド名>(引数)', style: Theme.of(context).textTheme.bodySmall),
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

/// ビュー定義をコマンド引数(JSON)へ。
Map<String, Object?> viewToMap(ViewEntity v) => PeroEncoder.entityToMap(v);
