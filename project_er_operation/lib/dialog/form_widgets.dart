import 'package:flutter/material.dart';

import '../model/model.dart';

/// ダイアログ内の単純な文字列入力(入力のたびに作業コピーへ反映する)。
Widget textField(
  String label,
  String value,
  void Function(String) onChanged, {
  Key? key,
  String? error,
  bool multiline = false,
  bool enabled = true,
  TextInputType? keyboardType,
}) =>
    Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: TextFormField(
        key: key,
        initialValue: value,
        enabled: enabled,
        maxLines: multiline ? 6 : 1,
        minLines: multiline ? 3 : 1,
        keyboardType: keyboardType,
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          errorText: error,
          border: const OutlineInputBorder(),
        ),
        onChanged: onChanged,
      ),
    );

/// 対象DBごとのタブ(8.1-3-6)。[values] を直接書き換える。
class PerDbTabs extends StatelessWidget {
  const PerDbTabs({
    super.key,
    required this.entries,
    this.height = 220,
  });

  /// (ラベル, 値のMap, 複数行か) の並び。各タブに全項目を縦に並べる。
  final List<(String, Map<DbKind, String>, bool)> entries;
  final double height;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: DbKind.values.length,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        TabBar(tabs: [for (final d in DbKind.values) Tab(text: d.wire)]),
        SizedBox(
          height: height,
          child: TabBarView(children: [
            for (final d in DbKind.values)
              ListView(padding: const EdgeInsets.only(top: 6), children: [
                for (final e in entries)
                  textField(e.$1, e.$2[d] ?? '', (v) => e.$2[d] = v,
                      key: ValueKey('${e.$1}-${d.wire}'), multiline: e.$3),
              ]),
          ]),
        ),
      ]),
    );
  }
}

/// 物理名の検証(形式)。問題なければnull。
String? nameFormatError(String name, String format) {
  if (name.isEmpty) return '必須です';
  try {
    if (!RegExp(format).hasMatch(name)) return '形式($format)に一致しません';
  } on FormatException {
    return null;
  }
  return null;
}

/// 作業コピー内で使うID採番(モデルの `nextId` から始め、コマンド実行時に引き上げる)。
class LocalIds {
  LocalIds(this._next);
  int _next;
  int next() => _next++;
}

/// 型の選択と、型が必要とするパラメータ(長さ、または精度とスケール)の入力。
class TypeAndParams extends StatelessWidget {
  const TypeAndParams({
    super.key,
    required this.types,
    required this.typeId,
    required this.length,
    required this.precision,
    required this.scale,
    required this.onChanged,
    this.enabled = true,
  });

  final List<DataType> types;
  final String typeId;
  final int? length;
  final int? precision;
  final int? scale;
  final bool enabled;

  /// (型ID, 長さ, 精度, スケール)
  final void Function(String typeId, int? length, int? precision, int? scale) onChanged;

  @override
  Widget build(BuildContext context) {
    final t = types.where((x) => x.id == typeId).firstOrNull;
    int? parse(String v) => int.tryParse(v);
    return Row(children: [
      Expanded(
        flex: 3,
        child: DropdownButtonFormField<String>(
          key: ValueKey('type-$typeId'),
          initialValue: t == null ? null : typeId,
          isExpanded: true,
          decoration: const InputDecoration(labelText: '型', isDense: true, border: OutlineInputBorder()),
          items: [for (final x in types) DropdownMenuItem(value: x.id, child: Text(x.displayName, overflow: TextOverflow.ellipsis))],
          onChanged: !enabled
              ? null
              : (v) {
                  if (v == null) return;
                  final n = types.firstWhere((x) => x.id == v);
                  onChanged(
                    v,
                    n.paramKind == ParamKind.length ? n.defaultLength : null,
                    n.paramKind == ParamKind.precisionScale ? n.defaultPrecision : null,
                    n.paramKind == ParamKind.precisionScale ? n.defaultScale : null,
                  );
                },
        ),
      ),
      if (t?.paramKind == ParamKind.length) ...[
        const SizedBox(width: 4),
        Expanded(
          flex: 2,
          child: textField('長さ', '${length ?? ''}', (v) => onChanged(typeId, parse(v), precision, scale),
              key: ValueKey('len-$typeId'), keyboardType: TextInputType.number, enabled: enabled),
        ),
      ],
      if (t?.paramKind == ParamKind.precisionScale) ...[
        const SizedBox(width: 4),
        Expanded(
          child: textField('精度', '${precision ?? ''}', (v) => onChanged(typeId, length, parse(v), scale),
              key: ValueKey('prec-$typeId'), keyboardType: TextInputType.number, enabled: enabled),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: textField('スケール', '${scale ?? ''}', (v) => onChanged(typeId, length, precision, parse(v)),
              key: ValueKey('scale-$typeId'), keyboardType: TextInputType.number, enabled: enabled),
        ),
      ],
    ]);
  }
}
