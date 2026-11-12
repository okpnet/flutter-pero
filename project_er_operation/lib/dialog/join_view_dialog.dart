import 'package:flutter/material.dart';

import '../command/command.dart';
import '../common/common.dart';
import '../model/model.dart';
import 'form_widgets.dart';

/// 結合ビューの定義ダイアログ(6.6-3〜6.6-7)。OKで定義済みのビューを返す(新規はIDが0)。
/// [initial] がnullのとき新規。
Future<ViewEntity?> showJoinViewDialog(
  BuildContext context,
  ErModel model, {
  required String nameFormat,
  ViewEntity? initial,
}) {
  return showDialog<ViewEntity>(
    context: context,
    builder: (c) => _JoinViewDialog(model: model, nameFormat: nameFormat, initial: initial),
  );
}

class _JoinViewDialog extends StatefulWidget {
  const _JoinViewDialog({required this.model, required this.nameFormat, this.initial});
  final ErModel model;
  final String nameFormat;
  final ViewEntity? initial;

  @override
  State<_JoinViewDialog> createState() => _JoinViewDialogState();
}

class _JoinViewDialogState extends State<_JoinViewDialog> {
  late final ViewEntity _v = widget.initial?.copy() ??
      ViewEntity(id: 0, viewType: ViewType.join, physicalName: _defaultName());
  List<String> _problems = [];
  int _gen = 0; // 構造が変わったときにフィールドを作り直す

  ErModel get _m => widget.model;
  ViewJoinDef get _j => _v.join;

  String _defaultName() {
    final used = widget.model.entities.map((e) => e.physicalName.toLowerCase()).toSet();
    var n = 1;
    while (used.contains('view_$n')) {
      n++;
    }
    return 'view_$n';
  }

  List<TableEntity> get _tables => (_m.tables.toList()..sort((a, b) => a.physicalName.compareTo(b.physicalName)));

  void _rebuild() => setState(() => _gen++);

  // ---- ソース ----

  void _addSource(TableEntity t) {
    final s = ViewSource(alias: uniqueAlias(t.physicalName, _j.sources.map((x) => x.alias)), entityId: t.id);
    if (_j.sources.isNotEmpty) {
      s.on = suggestJoinConditions(_m, _j.sources, s); // 既存のリレーションシップから初期値を提案(編集できる)
    }
    _j.sources.add(s);
    _rebuild();
  }

  List<ExpandedColumn> _colsOf(int entityId) {
    final t = _m.tableById(entityId);
    return t == null ? [] : _m.expand(t).columns;
  }

  String _colLabel(ExpandedColumn x) =>
      '${x.column.physicalName}  ${_m.typeLabel(x.column)}${x.isCommon ? '  (共通列)' : ''}';

  // ---- 出力列 ----

  void _addOutput(ViewSource s, ExpandedColumn x) {
    final name = uniqueOutputName(x.column.physicalName, s.alias, _j.columns.map((c) => c.name));
    _j.columns.add(ViewOutputColumn(
        alias: s.alias, columnId: x.column.id, name: name, logicalName: x.column.logicalName));
  }

  void _addAllOutputs(ViewSource s) {
    for (final x in _colsOf(s.entityId)) {
      if (_j.columns.any((c) => c.alias == s.alias && c.columnId == x.column.id)) continue;
      _addOutput(s, x);
    }
    _rebuild();
  }

  void _ok() {
    final problems = joinViewProblems(_m, _v,
        nameFormat: RegExp(widget.nameFormat), selfId: widget.initial?.id);
    if (problems.isNotEmpty) {
      setState(() => _problems = problems);
      return;
    }
    // 出力列名が空のものは、元の列の物理名にする(6.6-3-6)。
    for (final c in _j.columns) {
      if (c.name.isEmpty) {
        final src = _j.sources.firstWhere((s) => s.alias == c.alias);
        c.name = _m.findExpandedColumn(_m.tableById(src.entityId)!, c.columnId)!.column.physicalName;
      }
    }
    _v.viewType = ViewType.join;
    Navigator.pop(context, _v);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(widget.initial == null ? '結合ビューの追加' : '結合ビューの定義を編集'),
      content: SizedBox(
        width: 860,
        height: 600,
        child: ListView(key: ValueKey(_gen), children: [
          Row(children: [
            Expanded(child: textField('論理名', _v.logicalName, (v) => _v.logicalName = v, key: const ValueKey('jl'))),
            const SizedBox(width: 8),
            Expanded(child: textField('物理名', _v.physicalName, (v) => _v.physicalName = v, key: const ValueKey('jp'))),
          ]),
          textField('コメント', _v.comment, (v) => _v.comment = v, key: const ValueKey('jc')),
          const Divider(height: 24),
          Row(children: [
            Expanded(child: Text('ソース(最初のテーブルが FROM)', style: theme.textTheme.titleSmall)),
            PopupMenuButton<int>(
              tooltip: 'ソースのテーブルを追加',
              onSelected: (id) => _addSource(_m.tableById(id)!),
              itemBuilder: (_) => [for (final t in _tables) PopupMenuItem(value: t.id, child: Text(t.displayLabel))],
              child: const Padding(
                padding: EdgeInsets.all(6),
                child: Row(children: [Icon(Icons.add, size: 18), SizedBox(width: 4), Text('ソースを追加')]),
              ),
            ),
          ]),
          for (var i = 0; i < _j.sources.length; i++) _source(i),
          const Divider(height: 24),
          Text('出力列(ソースの実列・共通列から選択)', style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          Wrap(spacing: 8, children: [
            for (final s in _j.sources)
              OutlinedButton(
                onPressed: () => _addAllOutputs(s),
                child: Text('${s.alias} の全列を追加'),
              ),
          ]),
          for (var i = 0; i < _j.columns.length; i++) _output(i),
          const Divider(height: 24),
          textField('WHERE(任意。内容は検証しません)', _j.where, (v) => _j.where = v, key: const ValueKey('jw'), multiline: true),
          const SizedBox(height: 8),
          textField('生成前実行クエリ', _v.preQuery, (v) => _v.preQuery = v, key: const ValueKey('jpre'), multiline: true),
          textField('生成後実行クエリ', _v.postQuery, (v) => _v.postQuery = v, key: const ValueKey('jpost'), multiline: true),
          if (_problems.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_problems.join('\n'), style: const TextStyle(color: Colors.red)),
            ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text(Strings.cancel)),
        FilledButton(onPressed: _ok, child: const Text(Strings.ok)),
      ],
    );
  }

  /// ソース1件: テーブル、エイリアス、(2つ目以降は)結合種別と結合条件。
  Widget _source(int i) {
    final s = _j.sources[i];
    final cols = _colsOf(s.entityId);
    return Card(
      key: ValueKey('src$i$_gen'),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Text(i == 0 ? 'FROM' : '${i + 1}つ目', style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(width: 8),
            Expanded(
              flex: 3,
              child: DropdownButtonFormField<int>(
                key: ValueKey('srct$i${s.entityId}$_gen'),
                initialValue: _m.tableById(s.entityId) == null ? null : s.entityId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'テーブル', isDense: true, border: OutlineInputBorder()),
                items: [for (final t in _tables) DropdownMenuItem(value: t.id, child: Text(t.displayLabel, overflow: TextOverflow.ellipsis))],
                onChanged: (v) {
                  if (v == null) return;
                  changeSourceEntity(_j, s, v);
                  if (i > 0) s.on = suggestJoinConditions(_m, _j.sources.sublist(0, i), s);
                  _rebuild();
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: TextFormField(
                key: ValueKey('alias$i$_gen'),
                initialValue: s.alias,
                decoration: const InputDecoration(labelText: 'エイリアス', isDense: true, border: OutlineInputBorder()),
                onChanged: (v) {
                  renameAlias(_j, s.alias, v);
                  s.alias = v;
                },
              ),
            ),
            IconButton(
              tooltip: 'ソースを削除',
              icon: const Icon(Icons.delete_outline, size: 18),
              onPressed: () {
                removeSource(_j, s.alias);
                _rebuild();
              },
            ),
          ]),
          if (i > 0) ...[
            const SizedBox(height: 8),
            Row(children: [
              SizedBox(
                width: 160,
                child: DropdownButtonFormField<JoinType>(
                  key: ValueKey('jt$i${s.joinType}$_gen'),
                  initialValue: s.joinType,
                  decoration: const InputDecoration(labelText: '結合種別', isDense: true, border: OutlineInputBorder()),
                  items: [for (final t in JoinType.values) DropdownMenuItem(value: t, child: Text(t.wire))],
                  onChanged: (v) => setState(() => s.joinType = v ?? JoinType.inner),
                ),
              ),
              const SizedBox(width: 8),
              const Expanded(child: Text('結合条件(複数はANDで結ぶ。追加時にリレーションシップから提案)')),
              TextButton.icon(
                onPressed: cols.isEmpty
                    ? null
                    : () {
                        final left = _j.sources.first;
                        final lc = _colsOf(left.entityId);
                        if (lc.isEmpty) return;
                        s.on.add(JoinOn(leftAlias: left.alias, leftColumnId: lc.first.column.id, rightColumnId: cols.first.column.id));
                        _rebuild();
                      },
                icon: const Icon(Icons.add, size: 16),
                label: const Text('条件を追加'),
              ),
            ]),
            for (var k = 0; k < s.on.length; k++) _on(i, s, k),
          ],
        ]),
      ),
    );
  }

  /// 結合条件1組: 左のソースの列 = このソースの列。
  Widget _on(int i, ViewSource s, int k) {
    final o = s.on[k];
    final earlier = _j.sources.sublist(0, i);
    final leftSrc = earlier.where((x) => x.alias == o.leftAlias).firstOrNull ?? earlier.first;
    final leftCols = _colsOf(leftSrc.entityId);
    final rightCols = _colsOf(s.entityId);
    return Padding(
      key: ValueKey('on$i$k$_gen'),
      padding: const EdgeInsets.only(top: 6),
      child: Row(children: [
        SizedBox(
          width: 130,
          child: DropdownButtonFormField<String>(
            key: ValueKey('ola$i$k${o.leftAlias}$_gen'),
            initialValue: earlier.any((x) => x.alias == o.leftAlias) ? o.leftAlias : null,
            isExpanded: true,
            decoration: const InputDecoration(labelText: '左のソース', isDense: true, border: OutlineInputBorder()),
            items: [for (final x in earlier) DropdownMenuItem(value: x.alias, child: Text(x.alias, overflow: TextOverflow.ellipsis))],
            onChanged: (v) {
              if (v == null) return;
              final ns = earlier.firstWhere((x) => x.alias == v);
              final nc = _colsOf(ns.entityId);
              o.leftAlias = v;
              if (!nc.any((c) => c.column.id == o.leftColumnId)) {
                o.leftColumnId = nc.isEmpty ? o.leftColumnId : nc.first.column.id;
              }
              _rebuild();
            },
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: DropdownButtonFormField<int>(
            key: ValueKey('olc$i$k${o.leftColumnId}$_gen'),
            initialValue: leftCols.any((c) => c.column.id == o.leftColumnId) ? o.leftColumnId : null,
            isExpanded: true,
            decoration: const InputDecoration(labelText: '左の列', isDense: true, border: OutlineInputBorder()),
            items: [for (final c in leftCols) DropdownMenuItem(value: c.column.id, child: Text(_colLabel(c), overflow: TextOverflow.ellipsis))],
            onChanged: (v) => setState(() => o.leftColumnId = v ?? o.leftColumnId),
          ),
        ),
        const Padding(padding: EdgeInsets.symmetric(horizontal: 6), child: Text('=')),
        Expanded(
          child: DropdownButtonFormField<int>(
            key: ValueKey('orc$i$k${o.rightColumnId}$_gen'),
            initialValue: rightCols.any((c) => c.column.id == o.rightColumnId) ? o.rightColumnId : null,
            isExpanded: true,
            decoration: InputDecoration(labelText: '${s.alias} の列', isDense: true, border: const OutlineInputBorder()),
            items: [for (final c in rightCols) DropdownMenuItem(value: c.column.id, child: Text(_colLabel(c), overflow: TextOverflow.ellipsis))],
            onChanged: (v) => setState(() => o.rightColumnId = v ?? o.rightColumnId),
          ),
        ),
        IconButton(
          tooltip: '条件を削除',
          icon: const Icon(Icons.close, size: 16),
          onPressed: () {
            s.on.removeAt(k);
            _rebuild();
          },
        ),
      ]),
    );
  }

  /// 出力列1件: ソースと列、出力列名(別名)、論理名。
  Widget _output(int i) {
    final c = _j.columns[i];
    final src = _j.sources.where((s) => s.alias == c.alias).firstOrNull;
    final cols = src == null ? <ExpandedColumn>[] : _colsOf(src.entityId);
    return Padding(
      key: ValueKey('out$i$_gen'),
      padding: const EdgeInsets.only(top: 6),
      child: Row(children: [
        SizedBox(
          width: 120,
          child: DropdownButtonFormField<String>(
            key: ValueKey('oa$i${c.alias}$_gen'),
            initialValue: _j.sources.any((s) => s.alias == c.alias) ? c.alias : null,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'ソース', isDense: true, border: OutlineInputBorder()),
            items: [for (final s in _j.sources) DropdownMenuItem(value: s.alias, child: Text(s.alias, overflow: TextOverflow.ellipsis))],
            onChanged: (v) {
              if (v == null) return;
              final ns = _j.sources.firstWhere((s) => s.alias == v);
              final nc = _colsOf(ns.entityId);
              c.alias = v;
              if (!nc.any((x) => x.column.id == c.columnId) && nc.isNotEmpty) {
                c.columnId = nc.first.column.id;
                c.name = uniqueOutputName(nc.first.column.physicalName, v, _j.columns.where((x) => x != c).map((x) => x.name));
              }
              _rebuild();
            },
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          flex: 3,
          child: DropdownButtonFormField<int>(
            key: ValueKey('oc$i${c.columnId}$_gen'),
            initialValue: cols.any((x) => x.column.id == c.columnId) ? c.columnId : null,
            isExpanded: true,
            decoration: const InputDecoration(labelText: '列', isDense: true, border: OutlineInputBorder()),
            items: [for (final x in cols) DropdownMenuItem(value: x.column.id, child: Text(_colLabel(x), overflow: TextOverflow.ellipsis))],
            onChanged: (v) {
              if (v == null) return;
              final x = cols.firstWhere((e) => e.column.id == v);
              c.columnId = v;
              c.name = uniqueOutputName(x.column.physicalName, c.alias, _j.columns.where((e) => e != c).map((e) => e.name));
              c.logicalName = x.column.logicalName;
              _rebuild();
            },
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          flex: 2,
          child: TextFormField(
            key: ValueKey('on$i${c.name.hashCode}$_gen'),
            initialValue: c.name,
            decoration: const InputDecoration(labelText: '出力列名(別名)', isDense: true, border: OutlineInputBorder()),
            onChanged: (v) => c.name = v,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          flex: 2,
          child: TextFormField(
            key: ValueKey('ol$i$_gen'),
            initialValue: c.logicalName,
            decoration: const InputDecoration(labelText: '論理名', isDense: true, border: OutlineInputBorder()),
            onChanged: (v) => c.logicalName = v,
          ),
        ),
        IconButton(
          tooltip: '出力列を削除',
          icon: const Icon(Icons.close, size: 16),
          onPressed: () {
            _j.columns.removeAt(i);
            _rebuild();
          },
        ),
      ]),
    );
  }
}
