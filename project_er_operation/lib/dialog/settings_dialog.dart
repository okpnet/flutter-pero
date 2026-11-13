import 'package:flutter/material.dart' hide Orientation;

import '../common/common.dart';
import '../logging/logging.dart';
import '../model/model.dart';
import '../settings/settings.dart';
import 'type_editor.dart';

enum _Kind { boolean, integer, decimal, text, choice }

class _Item {
  _Item(this.category, this.label, this.kind,
      {required this.get, required this.set, this.min, this.max, this.choices, this.note});
  final String category;
  final String label;
  final _Kind kind;
  final Object? Function(AppSettings) get;
  final void Function(AppSettings, Object?) set;
  final num? min;
  final num? max;
  final Map<Object, String>? choices;
  final String? note;
}

List<_Item> _items() => [
      _Item('バックアップ', '有効', _Kind.boolean, get: (s) => s.backupEnabled, set: (s, v) => s.backupEnabled = v as bool),
      _Item('バックアップ', 'フォルダ(空で既定)', _Kind.text, get: (s) => s.backupFolder, set: (s, v) => s.backupFolder = v as String),
      _Item('バックアップ', 'サイクルタイム(分)', _Kind.integer, min: 1, max: 60, get: (s) => s.backupCycleMinutes, set: (s, v) => s.backupCycleMinutes = v as int),
      _Item('バックアップ', '保存期間(日)', _Kind.integer, min: 1, max: 180, get: (s) => s.backupRetentionDays, set: (s, v) => s.backupRetentionDays = v as int),
      _Item('ファイル', '最近使ったファイルの数', _Kind.integer, min: 0, max: 20, get: (s) => s.recentFileCount, set: (s, v) => s.recentFileCount = v as int),
      _Item('ポストファイル', 'フォルダ(空で既定)', _Kind.text, get: (s) => s.postFolder, set: (s, v) => s.postFolder = v as String),
      _Item('ポストファイル', 'ファイル', _Kind.text, get: (s) => s.postFile, set: (s, v) => s.postFile = v as String),
      _Item('ポストファイル', '種類(kind)の関連付け', _Kind.text, get: (s) => s.postKindsText, set: (s, v) => s.postKindsText = v as String, note: 'メタ情報の targetDb が postgresql / mysql / sqlserver / sqlite 以外のポストファイルを、既存の種類として扱います。「ファイル名=種類」をカンマ区切りで指定します(例: mariadb.post=mysql)'),
      _Item('ポストファイル', '実行タイムアウト(秒)', _Kind.integer, min: 1, max: 300, get: (s) => s.postTimeoutSeconds, set: (s, v) => s.postTimeoutSeconds = v as int),
      _Item('生成', '生成ファイルの拡張子', _Kind.text, get: (s) => s.generatedExtension, set: (s, v) => s.generatedExtension = v as String),
      _Item('生成', '改行コード', _Kind.choice, choices: {true: 'CRLF', false: 'LF'}, get: (s) => s.crlf, set: (s, v) => s.crlf = v as bool),
      _Item('生成', '主キー制約名のプリフィクス', _Kind.text, get: (s) => s.pkPrefix, set: (s, v) => s.pkPrefix = v as String, note: '主キー制約名は「プリフィクス + テーブル物理名 + サフィックス」です'),
      _Item('生成', '主キー制約名のサフィックス', _Kind.text, get: (s) => s.pkSuffix, set: (s, v) => s.pkSuffix = v as String),
      _Item('生成', '再実行用のDROP文を付ける', _Kind.boolean, get: (s) => s.dropBeforeCreate, set: (s, v) => s.dropBeforeCreate = v as bool, note: 'ユーザー定義型・テーブル(CASCADE)・ビューのCREATEの前に DROP ... IF EXISTS を出力します'),
      _Item('キャンバス', '用紙サイズ', _Kind.choice, choices: {for (final p in PageSize.values) p: p.wire}, get: (s) => s.paperSize, set: (s, v) => s.paperSize = v as PageSize),
      _Item('キャンバス', '向き', _Kind.choice, choices: {Orientation.landscape: '横', Orientation.portrait: '縦'}, get: (s) => s.orientation, set: (s, v) => s.orientation = v as Orientation),
      _Item('キャンバス', '解像度(dpi)', _Kind.integer, min: 100, max: 600, get: (s) => s.dpi, set: (s, v) => s.dpi = v as int),
      _Item('キャンバス', '整列スペース(px)', _Kind.decimal, min: 10, max: 200, get: (s) => s.alignSpace, set: (s, v) => s.alignSpace = v as double),
      _Item('キャンバス', 'グリッドスナップ(px。0で無効)', _Kind.decimal, min: 0, max: 50, get: (s) => s.gridSnap, set: (s, v) => s.gridSnap = v as double),
      _Item('キャンバス', 'Undo履歴の上限', _Kind.integer, min: 10, max: 1000, get: (s) => s.undoLimit, set: (s, v) => s.undoLimit = v as int),
      _Item('表示', '色テーマ', _Kind.choice, choices: {ThemeChoice.system: 'システムテーマ', ThemeChoice.dark: 'ダークテーマ', ThemeChoice.light: 'ライトテーマ', ThemeChoice.user: 'ユーザーテーマ'}, get: (s) => s.theme, set: (s, v) => s.theme = v as ThemeChoice),
      _Item('表示', 'ユーザーテーマのファイル(テーマのJSON)', _Kind.text, get: (s) => s.userThemeFile, set: (s, v) => s.userThemeFile = v as String, note: '色テーマが「ユーザーテーマ」のとき、theme_lib のテーマJSON(schemaVersion / id / name / light.seedColor など)を読み込みます。読み込めないときはシステムテーマで表示します'),
      _Item('表示', 'ヘッダに論理名を表示', _Kind.boolean, get: (s) => s.headerLogical, set: (s, v) => s.headerLogical = v as bool, note: '論理名・物理名の少なくとも一方は表示します'),
      _Item('表示', 'ヘッダに物理名を表示', _Kind.boolean, get: (s) => s.headerPhysical, set: (s, v) => s.headerPhysical = v as bool),
      _Item('表示', '列に論理名を表示', _Kind.boolean, get: (s) => s.colLogical, set: (s, v) => s.colLogical = v as bool),
      _Item('表示', '列に物理名を表示', _Kind.boolean, get: (s) => s.colPhysical, set: (s, v) => s.colPhysical = v as bool),
      _Item('表示', '列に型を表示', _Kind.boolean, get: (s) => s.colType, set: (s, v) => s.colType = v as bool),
      _Item('表示', '列にデフォルト値を表示', _Kind.boolean, get: (s) => s.colDefault, set: (s, v) => s.colDefault = v as bool),
      _Item('表示', '列にコメントを表示', _Kind.boolean, get: (s) => s.colComment, set: (s, v) => s.colComment = v as bool),
      _Item('表示', '物理名の形式(正規表現)', _Kind.text, get: (s) => s.nameFormat, set: (s, v) => s.nameFormat = v as String),
      _Item('文字', '基準フォントサイズ(px)', _Kind.decimal, min: 8, max: 32, get: (s) => s.fontSize, set: (s, v) => s.fontSize = v as double),
      _Item('文字', 'フォント(空でOS標準)', _Kind.text, get: (s) => s.fontFamily, set: (s, v) => s.fontFamily = v as String),
      _Item('文字', 'ヘッダの倍率', _Kind.decimal, min: 0.5, max: 3, get: (s) => s.headerScale, set: (s, v) => s.headerScale = v as double),
      _Item('文字', '標準の倍率', _Kind.decimal, min: 0.5, max: 3, get: (s) => s.normalScale, set: (s, v) => s.normalScale = v as double),
      _Item('文字', '補足の倍率', _Kind.decimal, min: 0.3, max: 3, get: (s) => s.supplementScale, set: (s, v) => s.supplementScale = v as double),
      _Item('ログ', 'レベル', _Kind.choice, choices: {for (final l in LogLevel.values) l: l.name}, get: (s) => s.logLevel, set: (s, v) => s.logLevel = v as LogLevel),
      _Item('ログ', '保持日数', _Kind.integer, min: 1, max: 90, get: (s) => s.logRetentionDays, set: (s, v) => s.logRetentionDays = v as int),
    ];

/// 設定画面(3.8)。OK / 適用 で [onApply] が呼ばれる。
Future<void> showSettingsDialog(BuildContext context, AppSettings current,
    {required void Function(AppSettings applied) onApply}) {
  return showDialog<void>(
    context: context,
    builder: (c) => _SettingsDialog(current: current, onApply: onApply),
  );
}

class _SettingsDialog extends StatefulWidget {
  const _SettingsDialog({required this.current, required this.onApply});
  final AppSettings current;
  final void Function(AppSettings) onApply;

  @override
  State<_SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<_SettingsDialog> {
  late AppSettings _work = widget.current.copy();
  final _items0 = _items();
  late final List<String> _categories = [..._items0.map((i) => i.category).toSet(), '型'];
  late String _category = _categories.first;
  final Map<_Item, String> _errors = {};
  int _generation = 0; // 既定に戻したときにフィールドを作り直す

  /// 入力値の検証と反映。エラーがあれば false。
  bool _validateAll() {
    if (!_work.headerLogical && !_work.headerPhysical) {
      _errors[_items0.firstWhere((i) => i.label == 'ヘッダに論理名を表示')] = '論理名・物理名の少なくとも一方は表示してください';
    }
    try {
      RegExp(_work.nameFormat);
    } on FormatException {
      _errors[_items0.firstWhere((i) => i.label.startsWith('物理名の形式'))] = '正規表現が不正です';
    }
    return _errors.isEmpty;
  }

  void _apply({required bool close}) {
    _errors.removeWhere((k, v) => k.label != 'ヘッダに論理名を表示' && !v.startsWith('範囲'));
    if (_errors.values.any((v) => v.startsWith('範囲'))) {
      setState(() {});
      return;
    }
    _errors.clear();
    if (!_validateAll()) {
      setState(() {});
      return;
    }
    widget.onApply(_work.copy());
    if (close) Navigator.pop(context);
  }

  void _resetCategory() {
    final d = AppSettings();
    setState(() {
      if (_category == '型') _work.typeTable = standardTypes();
      for (final i in _items0.where((i) => i.category == _category)) {
        i.set(_work, i.get(d));
        _errors.remove(i);
      }
      _generation++;
    });
  }

  void _resetAll() {
    final keep = _work;
    final d = AppSettings();
    // 自動保存の項目(ウィンドウなど)は戻さない。
    d
      ..rightPaneRatio = keep.rightPaneRatio
      ..propsRatio = keep.propsRatio
      ..windowX = keep.windowX
      ..windowY = keep.windowY
      ..windowWidth = keep.windowWidth
      ..windowHeight = keep.windowHeight
      ..windowMaximized = keep.windowMaximized
      ..lastFolder = keep.lastFolder
      ..recentFiles = keep.recentFiles;
    setState(() {
      _work = d;
      _errors.clear();
      _generation++;
    });
  }

  Widget _field(_Item i) {
    switch (i.kind) {
      case _Kind.boolean:
        return SwitchListTile(
          dense: true,
          title: Text(i.label),
          subtitle: i.note == null ? null : Text(i.note!),
          value: i.get(_work) as bool,
          onChanged: (v) => setState(() {
            i.set(_work, v);
            _errors.remove(i);
          }),
        );
      case _Kind.choice:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: DropdownButtonFormField<Object>(
            key: ValueKey('${i.label}$_generation'),
            initialValue: i.get(_work),
            decoration: InputDecoration(labelText: i.label, border: const OutlineInputBorder(), isDense: true),
            items: [for (final e in i.choices!.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
            onChanged: (v) => i.set(_work, v),
          ),
        );
      case _Kind.text:
      case _Kind.integer:
      case _Kind.decimal:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: TextFormField(
            key: ValueKey('${i.label}$_generation'),
            initialValue: '${i.get(_work)}',
            decoration: InputDecoration(
                labelText: i.label,
                border: const OutlineInputBorder(),
                isDense: true,
                errorText: _errors[i]),
            onChanged: (v) {
              if (i.kind == _Kind.text) {
                setState(() {
                  i.set(_work, v);
                  _errors.remove(i);
                });
                return;
              }
              final n = i.kind == _Kind.integer ? int.tryParse(v) : double.tryParse(v);
              setState(() {
                if (n == null || n < i.min! || n > i.max!) {
                  _errors[i] = '範囲は${i.min}〜${i.max}です';
                } else {
                  _errors.remove(i);
                  i.set(_work, i.kind == _Kind.integer ? n : n.toDouble());
                }
              });
            },
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items0.where((i) => i.category == _category).toList();
    return AlertDialog(
      title: const Text(Strings.fileSettings),
      content: SizedBox(
        width: 760,
        height: 460,
        child: Row(children: [
          SizedBox(
            width: 170,
            child: ListView(children: [
              for (final c in _categories)
                ListTile(
                  dense: true,
                  selected: c == _category,
                  title: Text(c),
                  onTap: () => setState(() => _category = c),
                ),
            ]),
          ),
          const VerticalDivider(),
          Expanded(
            child: _category == '型'
                ? TypeEditor(
                    // 設定の型テーブルは新規モデルの雛形。既存のモデルには影響しない(6.3-5)。
                    key: ValueKey('types$_generation'),
                    types: _work.typeTable,
                    usageCount: (_) => 0,
                    onReplacement: (_, _) {},
                  )
                : ListView(children: [for (final i in items) _field(i)]),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: _resetCategory, child: const Text('このカテゴリを既定に戻す')),
        TextButton(onPressed: _resetAll, child: const Text('すべて既定に戻す')),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text(Strings.cancel)),
        TextButton(onPressed: () => _apply(close: false), child: const Text(Strings.apply)),
        FilledButton(onPressed: () => _apply(close: true), child: const Text(Strings.ok)),
      ],
    );
  }
}
