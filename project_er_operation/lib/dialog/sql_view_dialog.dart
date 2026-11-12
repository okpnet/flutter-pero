import 'package:flutter/material.dart';

import '../common/common.dart';
import '../model/model.dart';
import 'form_widgets.dart';

/// SQLビューの定義ダイアログ(6.6-14)。OKで定義済みのビューを返す(新規はIDが0)。
/// [initial] がnullのとき新規。SELECT文をそのまま持ち、出力列は表示用に手入力する(任意)。
Future<ViewEntity?> showSqlViewDialog(
  BuildContext context,
  ErModel model, {
  required String nameFormat,
  ViewEntity? initial,
}) {
  return showDialog<ViewEntity>(
    context: context,
    builder: (c) => _SqlViewDialog(model: model, nameFormat: nameFormat, initial: initial),
  );
}

class _SqlViewDialog extends StatefulWidget {
  const _SqlViewDialog({required this.model, required this.nameFormat, this.initial});
  final ErModel model;
  final String nameFormat;
  final ViewEntity? initial;

  @override
  State<_SqlViewDialog> createState() => _SqlViewDialogState();
}

class _SqlViewDialogState extends State<_SqlViewDialog> {
  late final ViewEntity _v = widget.initial?.copy() ??
      ViewEntity(id: 0, viewType: ViewType.sql, physicalName: _defaultName());
  String? _error;
  int _gen = 0;

  ErModel get _m => widget.model;

  String _defaultName() {
    final used = widget.model.entities.map((e) => e.physicalName.toLowerCase()).toSet();
    var n = 1;
    while (used.contains('view_$n')) {
      n++;
    }
    return 'view_$n';
  }

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
    if (_v.sql.columns.any((x) => !identical(x, c) && x.name.toLowerCase() == c.name.toLowerCase())) {
      return '列名が重複しています';
    }
    return null;
  }

  void _ok() {
    final s = _v.sql;
    final err = _physicalError() ??
        (s.sql.trim().isEmpty ? 'SQL(SELECT文)を入力してください' : null) ??
        s.columns.map(_colError).whereType<String>().firstOrNull;
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    _v.viewType = ViewType.sql;
    Navigator.pop(context, _v);
  }

  @override
  Widget build(BuildContext context) {
    final s = _v.sql;
    return AlertDialog(
      title: Text(widget.initial == null ? 'SQLビューの追加' : 'SQLビューの定義を編集'),
      content: SizedBox(
        width: 720,
        height: 560,
        child: ListView(key: ValueKey(_gen), children: [
          Row(children: [
            Expanded(child: textField('論理名', _v.logicalName, (v) => _v.logicalName = v, key: const ValueKey('sl'))),
            const SizedBox(width: 8),
            Expanded(
              child: textField('物理名', _v.physicalName, (v) => setState(() => _v.physicalName = v),
                  key: const ValueKey('sp'), error: _physicalError()),
            ),
          ]),
          textField('コメント', _v.comment, (v) => _v.comment = v, key: const ValueKey('sc'), multiline: true),
          const SizedBox(height: 6),
          textField('SQL(SELECT文。CREATE VIEW 名前 AS の後にそのまま出力)', s.sql, (v) => s.sql = v,
              key: const ValueKey('ssql'), multiline: true),
          const SizedBox(height: 8),
          Row(children: [
            const Expanded(child: Text('列(キャンバスへの表示用。任意)')),
            TextButton.icon(
              onPressed: () => setState(() {
                var n = 1;
                while (s.columns.any((c) => c.name == 'column_$n')) {
                  n++;
                }
                s.columns.add(FunctionReturnColumn(name: 'column_$n', typeId: 'varchar', length: 255));
              }),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('追加'),
            ),
          ]),
          for (final c in s.columns)
            Card(
              key: ValueKey('sc${s.columns.indexOf(c)}$_gen'),
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Column(children: [
                  Row(children: [
                    Expanded(child: textField('論理名', c.logicalName, (v) => c.logicalName = v, key: ValueKey('scl${s.columns.indexOf(c)}$_gen'))),
                    const SizedBox(width: 4),
                    Expanded(
                      child: textField('列名', c.name, (v) => setState(() => c.name = v),
                          key: ValueKey('scn${s.columns.indexOf(c)}$_gen'), error: _colError(c)),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 18),
                      onPressed: () => setState(() {
                        s.columns.remove(c);
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
                    onChanged: (t, l, p, sc) => setState(() {
                      c.typeId = t;
                      c.length = l;
                      c.precision = p;
                      c.scale = sc;
                    }),
                  ),
                ]),
              ),
            ),
          const SizedBox(height: 4),
          Text('出力: CREATE VIEW <物理名> AS <SQL>', style: Theme.of(context).textTheme.bodySmall),
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
