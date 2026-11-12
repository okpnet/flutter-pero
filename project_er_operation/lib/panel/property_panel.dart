import 'package:flutter/material.dart' hide Orientation;

import '../command/command.dart';
import '../common/common.dart';
import '../dialog/dialog.dart';
import '../model/model.dart';
import '../session/session.dart';
import 'trigger_editor.dart';

/// プロパティペイン(3.6)。右ペイン上。
class PropertyPanel extends StatelessWidget {
  const PropertyPanel({
    super.key,
    required this.session,
    required this.nameFocus,
    required this.onManageMethods,
    required this.onEditFunctionView,
  });
  final EditorSession session;

  /// ダブルクリックでフォーカスを移す論理名入力(3.4-7)。
  final FocusNode nameFocus;

  /// メソッド管理ダイアログを開く(メソッド選択欄の「…」)。
  final Future<void> Function() onManageMethods;

  /// 関数ビューの定義ダイアログを開く。
  final Future<void> Function(int viewId) onEditFunctionView;

  @override
  Widget build(BuildContext context) {
    final sel = session.selection.toList();
    final Widget body;
    if (sel.isEmpty) {
      body = _ModelProps(session: session);
    } else if (sel.length > 1) {
      body = _MultiProps(session: session, ids: sel);
    } else {
      final id = sel.single;
      final e = session.model.entityById(id);
      final r = session.model.relationshipById(id);
      if (e is TableEntity) {
        body = _TableProps(
          key: ValueKey('t$id'),
          session: session,
          id: id,
          nameFocus: nameFocus,
          onManageMethods: onManageMethods,
        );
      } else if (e is ViewEntity) {
        body = _ViewProps(
          key: ValueKey('v$id'),
          session: session,
          id: id,
          nameFocus: nameFocus,
          onEdit: () => onEditFunctionView(id),
        );
      } else if (r != null) {
        body = _RelationshipProps(
          key: ValueKey('r$id'),
          session: session,
          id: id,
        );
      } else {
        body = _ModelProps(session: session);
      }
    }
    return ListView(padding: const EdgeInsets.all(8), children: [body]);
  }
}

Widget _gap([double h = 8]) => SizedBox(height: h);

Widget _section(BuildContext context, String title) => Padding(
  padding: const EdgeInsets.only(top: 12, bottom: 4),
  child: Text(title, style: Theme.of(context).textTheme.titleSmall),
);

// ---- モデル・ダイアグラム ----

class _ModelProps extends StatelessWidget {
  const _ModelProps({required this.session});
  final EditorSession session;

  @override
  Widget build(BuildContext context) {
    final m = session.model;
    final p = m.properties;
    final d = session.diagram;
    void upd(Map<String, Object?> patch) =>
        session.run(UpdateModelPropertiesCommand(patch));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _section(context, 'モデル'),
        CommitTextField(
          key: const ValueKey('outName'),
          label: '出力ファイル名',
          value: p.outputFileName,
          onCommit: (v) => upd({'outputFileName': v}),
        ),
        _gap(),
        CommitTextField(
          key: const ValueKey('outFolder'),
          label: '出力フォルダ',
          value: p.outputFolder,
          onCommit: (v) => upd({'outputFolder': v}),
        ),
        _gap(),
        DropdownButtonFormField<DbKind>(
          initialValue: p.targetDb,
          decoration: const InputDecoration(
            labelText: '対象のデータベース',
            isDense: true,
            border: OutlineInputBorder(),
          ),
          items: [
            for (final k in DbKind.values)
              DropdownMenuItem(value: k, child: Text(k.wire)),
          ],
          onChanged: (v) => v == null ? null : upd({'targetDb': v.wire}),
        ),
        _gap(),
        CommitTextField(
          key: const ValueKey('postPath'),
          label: 'ポストファイルのパス',
          value: p.postPath,
          onCommit: (v) => upd({'postPath': v}),
        ),
        _gap(),
        CommitTextField(
          key: const ValueKey('startQ'),
          label: '開始クエリ',
          value: p.startQuery,
          multiline: true,
          onCommit: (v) => upd({'startQuery': v}),
        ),
        _gap(),
        CommitTextField(
          key: const ValueKey('endQ'),
          label: '終了クエリ',
          value: p.endQuery,
          multiline: true,
          onCommit: (v) => upd({'endQuery': v}),
        ),
        _section(context, 'ダイアグラム'),
        CommitTextField(
          key: ValueKey('dn${d.id}'),
          label: '名前',
          value: d.name,
          validator: (v) {
            if (v.trim().isEmpty) return '名前を入力してください';
            if (m.diagrams.any(
              (x) => x.id != d.id && x.name.toLowerCase() == v.toLowerCase(),
            )) {
              return '同じ名前のダイアグラムが存在します';
            }
            return null;
          },
          onCommit: (v) => session.run(RenameDiagramCommand(d.id, v)),
        ),
        _gap(),
        DropdownButtonFormField<PageSize>(
          key: ValueKey('ps${d.id}${d.pageSize}'),
          initialValue: d.pageSize,
          decoration: const InputDecoration(
            labelText: '用紙サイズ',
            isDense: true,
            border: OutlineInputBorder(),
          ),
          items: [
            for (final k in PageSize.values)
              DropdownMenuItem(value: k, child: Text(k.wire)),
          ],
          onChanged: (v) => v == null
              ? null
              : session.run(UpdateDiagramPageCommand(d.id, v, d.orientation)),
        ),
        _gap(),
        DropdownButtonFormField<Orientation>(
          key: ValueKey('or${d.id}${d.orientation}'),
          initialValue: d.orientation,
          decoration: const InputDecoration(
            labelText: '向き',
            isDense: true,
            border: OutlineInputBorder(),
          ),
          items: const [
            DropdownMenuItem(value: Orientation.landscape, child: Text('横')),
            DropdownMenuItem(value: Orientation.portrait, child: Text('縦')),
          ],
          onChanged: (v) => v == null
              ? null
              : session.run(UpdateDiagramPageCommand(d.id, d.pageSize, v)),
        ),
        _gap(),
        Text('用紙ページ: ${d.pageRows}行 × ${d.pageCols}列'),
      ],
    );
  }
}

// ---- 複数選択 ----

class _MultiProps extends StatelessWidget {
  const _MultiProps({required this.session, required this.ids});
  final EditorSession session;
  final List<int> ids;

  @override
  Widget build(BuildContext context) {
    final m = session.model;
    bool locked(int id) =>
        m.entityById(id)?.locked ?? m.relationshipById(id)?.locked ?? false;
    final all = ids.every(locked);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${ids.length}${Strings.selectedCount}'),
        SwitchListTile(
          dense: true,
          title: const Text('ロック'),
          value: all,
          onChanged: (v) => session.run(SetLockedCommand(ids, v)),
        ),
      ],
    );
  }
}

// ---- テーブル ----

String? _physicalNameError(
  EditorSession s,
  String v, {
  int? entityId,
  TableEntity? inTable,
  int? columnId,
}) {
  if (v.isEmpty) return '物理名は必須です';
  final re = RegExp(s.settings.nameFormat);
  if (!re.hasMatch(v)) return '物理名の形式(${s.settings.nameFormat})に一致しません';
  final lower = v.toLowerCase();
  if (inTable != null) {
    for (final c in s.model.expand(inTable).columns) {
      if (c.column.id != columnId &&
          c.column.physicalName.toLowerCase() == lower) {
        return '同じ列名が存在します';
      }
    }
  } else if (s.model.entities.any(
    (e) => e.id != entityId && e.physicalName.toLowerCase() == lower,
  )) {
    return '同じ物理名のエンティティが存在します';
  }
  return null;
}

class _TableProps extends StatelessWidget {
  const _TableProps({
    super.key,
    required this.session,
    required this.id,
    required this.nameFocus,
    required this.onManageMethods,
  });
  final EditorSession session;
  final int id;
  final FocusNode nameFocus;
  final Future<void> Function() onManageMethods;

  TableEntity? get _t => session.model.tableById(id);

  void _edit(void Function(TableEntity t) f) {
    final t = _t;
    if (t == null) return;
    final c = t.copy();
    f(c);
    session.run(ReplaceEntityCommand.of(c));
  }

  @override
  Widget build(BuildContext context) {
    final t = _t;
    if (t == null) return const SizedBox();
    final m = session.model;
    final dis = t.locked; // ロック中はロック以外を無効表示(5.3-2-5)
    final exp = m.expand(t).columns;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _section(context, 'テーブル'),
        CommitTextField(
          key: ValueKey('tl$id'),
          label: '論理名',
          value: t.logicalName,
          enabled: !dis,
          focusNode: nameFocus,
          onCommit: (v) => _edit((c) => c.logicalName = v),
        ),
        _gap(),
        CommitTextField(
          key: ValueKey('tp$id'),
          label: '物理名',
          value: t.physicalName,
          enabled: !dis,
          validator: (v) => _physicalNameError(session, v, entityId: id),
          onCommit: (v) => _edit((c) => c.physicalName = v),
        ),
        _gap(),
        CommitTextField(
          key: ValueKey('tc$id'),
          label: 'コメント',
          value: t.comment,
          enabled: !dis,
          multiline: true,
          onCommit: (v) => _edit((c) => c.comment = v),
        ),
        _section(context, '列'),
        Row(
          children: [
            FilledButton.tonalIcon(
              onPressed: dis ? null : () => session.run(AddColumnCommand(id)),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('追加'),
            ),
          ],
        ),
        _gap(4),
        ReorderableListView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: !dis,
          onReorderItem: (from, to) {
            if (dis) return;
            _edit((c) {
              final col = c.columns.removeAt(from);
              c.columns.insert(to, col);
            });
          },
          children: [
            for (final col in t.columns)
              _ColumnEditor(
                key: ValueKey('col${col.id}'),
                session: session,
                table: t,
                column: col,
                enabled: !dis,
                onEdit: (f) => _edit((c) => f(c.columnById(col.id)!)),
                onDelete: () =>
                    deleteColumnWithConfirm(context, session, t.id, col.id),
                onManageMethods: onManageMethods,
              ),
          ],
        ),
        for (final x in exp.where((c) => c.isCommon))
          Card(
            color: Theme.of(context).disabledColor.withValues(alpha: 0.08),
            child: ListTile(
              dense: true,
              title: Text(
                '${x.column.physicalName}  ${m.typeLabel(x.column)}',
                style: const TextStyle(fontStyle: FontStyle.italic),
              ),
              subtitle: Text('共通列(パターン: ${x.patternName})  読み取り専用'),
            ),
          ),
        _section(context, '制約'),
        _ConstraintsEditor(
          title: 'インデックス',
          list: t.indexes,
          table: t,
          session: session,
          enabled: !dis,
          nameOf: (c) => m.indexName(t, c),
          onChange: (f) => _edit((c) => f(c.indexes)),
        ),
        _ConstraintsEditor(
          title: 'ユニーク',
          list: t.uniques,
          table: t,
          session: session,
          enabled: !dis,
          nameOf: (c) => m.uniqueName(t, c),
          onChange: (f) => _edit((c) => f(c.uniques)),
        ),
        _section(context, 'クエリ'),
        CommitTextField(
          key: ValueKey('tpre$id'),
          label: 'テーブル生成前実行クエリ',
          value: t.preQuery,
          enabled: !dis,
          multiline: true,
          onCommit: (v) => _edit((c) => c.preQuery = v),
        ),
        _gap(),
        CommitTextField(
          key: ValueKey('tpost$id'),
          label: 'テーブル生成後実行クエリ',
          value: t.postQuery,
          enabled: !dis,
          multiline: true,
          onCommit: (v) => _edit((c) => c.postQuery = v),
        ),
        _section(context, 'トリガー'),
        TriggerEditor(
          session: session,
          table: t,
          enabled: !dis,
          onEdit: _edit,
          onManageMethods: onManageMethods,
        ),
        SwitchListTile(
          dense: true,
          title: const Text('ロック'),
          value: t.locked,
          onChanged: (v) => session.run(SetLockedCommand([id], v)),
        ),
      ],
    );
  }
}

/// 列の削除(影響の確認つき。6.2-7)。
Future<void> deleteColumnWithConfirm(
  BuildContext context,
  EditorSession s,
  int entityId,
  int columnId,
) async {
  final blockers = RemoveColumnCommand.blockers(s.model, entityId, columnId);
  if (blockers.isNotEmpty) {
    await showMessageDialog(
      context,
      title: Strings.error,
      message: blockers.join('\n'),
    );
    return;
  }
  final impacts = RemoveColumnCommand.impacts(s.model, entityId, columnId);
  final col = s.model.tableById(entityId)?.columnById(columnId);
  final ok = await showConfirmDialog(
    context,
    title: '列の削除',
    message:
        '列「${col?.physicalName ?? ''}」を削除します。'
        '${impacts.isEmpty ? '' : '\n\n影響:\n${impacts.join('\n')}'}',
  );
  if (ok) s.run(RemoveColumnCommand(entityId, columnId));
}

class _ColumnEditor extends StatelessWidget {
  const _ColumnEditor({
    super.key,
    required this.session,
    required this.table,
    required this.column,
    required this.enabled,
    required this.onEdit,
    required this.onDelete,
    required this.onManageMethods,
  });
  final EditorSession session;
  final TableEntity table;
  final ColumnDef column;
  final bool enabled;
  final void Function(void Function(ColumnDef c) f) onEdit;
  final VoidCallback onDelete;
  final Future<void> Function() onManageMethods;

  @override
  Widget build(BuildContext context) {
    final m = session.model;
    final c = column;
    final type = m.typeById(c.typeId);
    final isAuto = type?.category == TypeCategory.auto;
    final inUse = m.relationships.any(
      (r) =>
          r.childId == table.id &&
          r.columnPairs.any((p) => p.childColumnId == c.id),
    );
    final methods = m.methods
        .where((x) => x.kind == MethodKind.function)
        .toList();
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 3),
      color: inUse ? Colors.amber.withValues(alpha: 0.12) : null,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: CommitTextField(
                    key: ValueKey('cl${c.id}'),
                    label: '論理名',
                    value: c.logicalName,
                    enabled: enabled,
                    onCommit: (v) => onEdit((x) => x.logicalName = v),
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: CommitTextField(
                    key: ValueKey('cp${c.id}'),
                    label: '物理名',
                    value: c.physicalName,
                    enabled: enabled,
                    validator: (v) => _physicalNameError(
                      session,
                      v,
                      inTable: table,
                      columnId: c.id,
                    ),
                    onCommit: (v) => onEdit((x) => x.physicalName = v),
                  ),
                ),
                IconButton(
                  tooltip: '列を削除',
                  icon: const Icon(Icons.delete_outline, size: 18),
                  onPressed: enabled ? onDelete : null,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: DropdownButtonFormField<String>(
                    key: ValueKey('ct${c.id}${c.typeId}'),
                    initialValue: m.typeById(c.typeId) == null
                        ? null
                        : c.typeId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: '型',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final t in m.types)
                        DropdownMenuItem(
                          value: t.id,
                          child: Text(
                            t.displayName,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: !enabled
                        ? null
                        : (v) {
                            if (v == null) return;
                            final t = m.typeById(v)!;
                            onEdit((x) {
                              x.typeId = v;
                              x.length = t.paramKind == ParamKind.length
                                  ? t.defaultLength
                                  : null;
                              x.precision =
                                  t.paramKind == ParamKind.precisionScale
                                  ? t.defaultPrecision
                                  : null;
                              x.scale = t.paramKind == ParamKind.precisionScale
                                  ? t.defaultScale
                                  : null;
                              if (t.category == TypeCategory.auto) {
                                x.defaultKind = DefaultKind.none;
                              }
                            });
                          },
                  ),
                ),
                if (type?.paramKind == ParamKind.length) ...[
                  const SizedBox(width: 4),
                  Expanded(
                    flex: 2,
                    child: _intField(
                      'cn${c.id}',
                      '長さ',
                      c.length,
                      enabled,
                      (v) => onEdit((x) => x.length = v),
                    ),
                  ),
                ],
                if (type?.paramKind == ParamKind.precisionScale) ...[
                  const SizedBox(width: 4),
                  Expanded(
                    child: _intField(
                      'cpr${c.id}',
                      '精度',
                      c.precision,
                      enabled,
                      (v) => onEdit((x) => x.precision = v),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: _intField(
                      'csc${c.id}',
                      'スケール',
                      c.scale,
                      enabled,
                      (v) => onEdit((x) => x.scale = v),
                    ),
                  ),
                ],
              ],
            ),
            Row(
              children: [
                Checkbox(
                  value: c.pk,
                  onChanged: enabled
                      ? (v) => onEdit((x) {
                          x.pk = v ?? false;
                          if (x.pk) x.notNull = true;
                        })
                      : null,
                ),
                const Text('PK'),
                const SizedBox(width: 8),
                Checkbox(
                  value: c.notNull || c.pk,
                  onChanged: enabled && !c.pk
                      ? (v) => onEdit((x) => x.notNull = v ?? false)
                      : null,
                ),
                const Text('NotNull'),
              ],
            ),
            Row(
              children: [
                SizedBox(
                  width: 96,
                  child: DropdownButtonFormField<DefaultKind>(
                    key: ValueKey('cdk${c.id}${c.defaultKind}$isAuto'),
                    initialValue: isAuto ? DefaultKind.none : c.defaultKind,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'デフォルト',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: DefaultKind.none,
                        child: Text('なし'),
                      ),
                      DropdownMenuItem(
                        value: DefaultKind.value,
                        child: Text('値'),
                      ),
                      DropdownMenuItem(
                        value: DefaultKind.method,
                        child: Text('メソッド'),
                      ),
                    ],
                    onChanged: enabled && !isAuto
                        ? (v) => onEdit(
                            (x) => x.defaultKind = v ?? DefaultKind.none,
                          )
                        : null,
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: c.defaultKind == DefaultKind.method && !isAuto
                      ? Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<int>(
                                key: ValueKey('cdm${c.id}${c.defaultMethodId}'),
                                initialValue:
                                    methods.any(
                                      (x) => x.id == c.defaultMethodId,
                                    )
                                    ? c.defaultMethodId
                                    : null,
                                isExpanded: true,
                                decoration: const InputDecoration(
                                  labelText: 'メソッド',
                                  isDense: true,
                                  border: OutlineInputBorder(),
                                ),
                                items: [
                                  for (final x in methods)
                                    DropdownMenuItem(
                                      value: x.id,
                                      child: Text(x.name),
                                    ),
                                ],
                                onChanged: enabled
                                    ? (v) =>
                                          onEdit((x) => x.defaultMethodId = v)
                                    : null,
                              ),
                            ),
                            IconButton(
                              tooltip: 'メソッド管理を開く',
                              icon: const Icon(Icons.more_horiz, size: 18),
                              onPressed: enabled ? onManageMethods : null,
                            ),
                          ],
                        )
                      : CommitTextField(
                          key: ValueKey('cdv${c.id}'),
                          label: '値',
                          value: c.defaultValue,
                          enabled:
                              enabled &&
                              c.defaultKind == DefaultKind.value &&
                              !isAuto,
                          validator: (v) => v.isEmpty ? '値は空にできません' : null,
                          onCommit: (v) => onEdit((x) => x.defaultValue = v),
                        ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            CommitTextField(
              key: ValueKey('cm${c.id}'),
              label: 'コメント',
              value: c.comment,
              enabled: enabled,
              onCommit: (v) => onEdit((x) => x.comment = v),
            ),
          ],
        ),
      ),
    );
  }

  Widget _intField(
    String key,
    String label,
    int? value,
    bool enabled,
    void Function(int?) onChange,
  ) => CommitTextField(
    key: ValueKey(key),
    label: label,
    value: value?.toString() ?? '',
    enabled: enabled,
    keyboardType: TextInputType.number,
    validator: (v) => v.isEmpty || (int.tryParse(v) != null && int.parse(v) > 0)
        ? null
        : '正の整数を入力してください',
    onCommit: (v) => onChange(v.isEmpty ? null : int.parse(v)),
  );
}

/// インデックス / ユニーク(6.4)。
class _ConstraintsEditor extends StatelessWidget {
  const _ConstraintsEditor({
    required this.title,
    required this.list,
    required this.table,
    required this.session,
    required this.enabled,
    required this.nameOf,
    required this.onChange,
  });
  final String title;
  final List<ConstraintDef> list;
  final TableEntity table;
  final EditorSession session;
  final bool enabled;
  final String Function(ConstraintDef) nameOf;
  final void Function(void Function(List<ConstraintDef> l) f) onChange;

  @override
  Widget build(BuildContext context) {
    final m = session.model;
    final cols = m.expand(table).columns;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text(title)),
            IconButton(
              tooltip: '$titleを追加',
              icon: const Icon(Icons.add, size: 18),
              onPressed: enabled && cols.isNotEmpty
                  ? () => onChange(
                      (l) => l.add(
                        ConstraintDef(
                          id: session.model.allocateId(),
                          columnIds: [cols.first.column.id],
                        ),
                      ),
                    )
                  : null,
            ),
          ],
        ),
        for (final c in list)
          Card(
            margin: const EdgeInsets.symmetric(vertical: 2),
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          nameOf(c),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      DropdownButton<NameMode>(
                        value: c.nameMode,
                        items: const [
                          DropdownMenuItem(
                            value: NameMode.auto,
                            child: Text('自動'),
                          ),
                          DropdownMenuItem(
                            value: NameMode.manual,
                            child: Text('手動'),
                          ),
                        ],
                        onChanged: enabled
                            ? (v) => onChange((l) {
                                final x = l.firstWhere((e) => e.id == c.id);
                                x.nameMode = v ?? NameMode.auto;
                                if (x.nameMode == NameMode.manual && x.name.isEmpty) {
                                  x.name = nameOf(c);
                                }
                              })
                            : null,
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 18),
                        onPressed: enabled
                            ? () => onChange(
                                (l) => l.removeWhere((e) => e.id == c.id),
                              )
                            : null,
                      ),
                    ],
                  ),
                  if (c.nameMode == NameMode.manual)
                    CommitTextField(
                      key: ValueKey('cn${c.id}'),
                      label: '制約名',
                      value: c.name,
                      enabled: enabled,
                      validator: (v) => v.isEmpty ? '制約名は必須です' : null,
                      onCommit: (v) => onChange(
                        (l) => l.firstWhere((e) => e.id == c.id).name = v,
                      ),
                    ),
                  Wrap(
                    spacing: 4,
                    children: [
                      for (final x in cols)
                        FilterChip(
                          label: Text(
                            x.column.physicalName,
                            style: TextStyle(
                              fontSize: 11,
                              fontStyle: x.isCommon ? FontStyle.italic : null,
                            ),
                          ),
                          selected: c.columnIds.contains(x.column.id),
                          onSelected: enabled
                              ? (sel) => onChange((l) {
                                  final e = l.firstWhere((e) => e.id == c.id);
                                  if (sel) {
                                    e.columnIds.add(x.column.id);
                                  } else if (e.columnIds.length > 1) {
                                    e.columnIds.remove(x.column.id);
                                  }
                                })
                              : null,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

// ---- ビュー ----

class _ViewProps extends StatelessWidget {
  const _ViewProps({
    super.key,
    required this.session,
    required this.id,
    required this.nameFocus,
    required this.onEdit,
  });
  final EditorSession session;
  final int id;
  final FocusNode nameFocus;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final v = session.model.entityById(id);
    if (v is! ViewEntity) return const SizedBox();
    final dis = v.locked;
    void edit(void Function(ViewEntity v) f) {
      final c = v.copy();
      f(c);
      session.run(ReplaceEntityCommand.of(c));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _section(context, 'ビュー(${v.viewType == ViewType.join ? '結合' : '関数'})'),
        CommitTextField(
          key: ValueKey('vl$id'),
          label: '論理名',
          value: v.logicalName,
          enabled: !dis,
          focusNode: nameFocus,
          onCommit: (x) => edit((c) => c.logicalName = x),
        ),
        _gap(),
        CommitTextField(
          key: ValueKey('vp$id'),
          label: '物理名',
          value: v.physicalName,
          enabled: !dis,
          validator: (x) => _physicalNameError(session, x, entityId: id),
          onCommit: (x) => edit((c) => c.physicalName = x),
        ),
        _gap(),
        CommitTextField(
          key: ValueKey('vc$id'),
          label: 'コメント',
          value: v.comment,
          enabled: !dis,
          multiline: true,
          onCommit: (x) => edit((c) => c.comment = x),
        ),
        _gap(),
        Text(
          '定義: ${v.viewType == ViewType.join ? 'ソース${v.join.sources.length}件 / 出力列${v.join.columns.length}件' : '戻り列${v.function.columns.length}件'}',
        ),
        if (v.viewType == ViewType.function)
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.tonalIcon(
              onPressed: dis ? null : onEdit,
              icon: const Icon(Icons.edit, size: 16),
              label: const Text('定義を編集'),
            ),
          )
        else
          Text(
            '結合ビューの定義ダイアログは今後のバージョンで対応します(定義は.peroファイルから読み込めます)',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        CommitTextField(
          key: ValueKey('vpre$id'),
          label: '生成前実行クエリ',
          value: v.preQuery,
          enabled: !dis,
          multiline: true,
          onCommit: (x) => edit((c) => c.preQuery = x),
        ),
        _gap(),
        CommitTextField(
          key: ValueKey('vpost$id'),
          label: '生成後実行クエリ',
          value: v.postQuery,
          enabled: !dis,
          multiline: true,
          onCommit: (x) => edit((c) => c.postQuery = x),
        ),
        SwitchListTile(
          dense: true,
          title: const Text('ロック'),
          value: v.locked,
          onChanged: (x) => session.run(SetLockedCommand([id], x)),
        ),
      ],
    );
  }
}

// ---- リレーションシップ ----

class _RelationshipProps extends StatelessWidget {
  const _RelationshipProps({
    super.key,
    required this.session,
    required this.id,
  });
  final EditorSession session;
  final int id;

  static const _actions = {
    RefAction.none: '適用しない',
    RefAction.noAction: 'NO ACTION',
    RefAction.restrict: 'RESTRICT',
    RefAction.cascade: 'CASCADE',
    RefAction.setNull: 'SET NULL',
    RefAction.setDefault: 'SET DEFAULT',
  };

  /// 変更を適用する。連動が必要な場合は確認ダイアログを出す(7-6-5)。
  Future<void> _update(
    BuildContext context,
    Relationship r,
    Map<String, Object?> patch,
  ) async {
    final next = UpdateRelationshipCommand.applyPatch(r, patch);
    final (pk, nn) = linkagePlan(r, next);
    var link = false;
    if (pk != null || nn != null) {
      final msg = [
        if (pk != null) '外部キー列のPKを${pk ? '有効' : '解除'}にします。',
        if (nn != null) '外部キー列のNotNullを${nn ? '有効' : '解除'}にします。',
      ].join('\n');
      link = await showConfirmDialog(
        context,
        title: '外部キー列の連動',
        message: '$msg\nよろしいですか?',
      );
      if (!link) return; // いいえで、その変更を取り消す
    }
    session.run(UpdateRelationshipCommand(r.id, patch, link: link));
  }

  @override
  Widget build(BuildContext context) {
    final m = session.model;
    final r = m.relationshipById(id);
    if (r == null) return const SizedBox();
    final p = m.tableById(r.parentId), c = m.tableById(r.childId);
    if (p == null || c == null) return const SizedBox();
    final dis = r.locked || p.locked || c.locked;
    final childCols = m.expand(c).columns;
    final parentCols = m.expand(p).columns;
    final childHasNotNull = r.columnPairs.any((x) {
      final col = c.columnById(x.childColumnId);
      return col != null && (col.notNull || col.pk);
    });
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _section(context, 'リレーションシップ'),
        Row(
          children: [
            Expanded(child: Text('親: ${p.displayLabel}\n子: ${c.displayLabel}')),
            IconButton(
              tooltip: '親と子を入れ替える',
              icon: const Icon(Icons.swap_vert),
              onPressed: dis
                  ? null
                  : () => session.run(SwapRelationshipDirectionCommand(id)),
            ),
          ],
        ),
        _section(context, '列対応'),
        for (var i = 0; i < r.columnPairs.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    parentCols
                            .where(
                              (x) =>
                                  x.column.id ==
                                  r.columnPairs[i].parentColumnId,
                            )
                            .firstOrNull
                            ?.column
                            .physicalName ??
                        '?',
                  ),
                ),
                const Icon(Icons.arrow_forward, size: 14),
                const SizedBox(width: 4),
                Expanded(
                  flex: 2,
                  child: DropdownButtonFormField<int>(
                    key: ValueKey('pair$id$i${r.columnPairs[i].childColumnId}'),
                    initialValue:
                        childCols.any(
                          (x) => x.column.id == r.columnPairs[i].childColumnId,
                        )
                        ? r.columnPairs[i].childColumnId
                        : null,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final x in childCols)
                        DropdownMenuItem(
                          value: x.column.id,
                          child: Text(
                            x.column.physicalName,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: dis
                        ? null
                        : (v) {
                            if (v == null) return;
                            final pairs = [
                              for (var k = 0; k < r.columnPairs.length; k++)
                                {
                                  'parentColumnId':
                                      r.columnPairs[k].parentColumnId,
                                  'childColumnId': k == i
                                      ? v
                                      : r.columnPairs[k].childColumnId,
                                },
                            ];
                            _update(context, r, {'columnPairs': pairs});
                          },
                  ),
                ),
              ],
            ),
          ),
        SwitchListTile(
          dense: true,
          title: const Text('依存関係(識別関係)'),
          value: r.dependency,
          onChanged: dis ? null : (v) => _update(context, r, {'dependency': v}),
        ),
        DropdownButtonFormField<Multiplicity>(
          key: ValueKey('mul$id${r.childMultiplicity}'),
          initialValue: r.childMultiplicity,
          decoration: const InputDecoration(
            labelText: '子側多重度',
            isDense: true,
            border: OutlineInputBorder(),
          ),
          items: const [
            DropdownMenuItem(value: Multiplicity.one, child: Text('1')),
            DropdownMenuItem(value: Multiplicity.many, child: Text('多')),
          ],
          onChanged: dis
              ? null
              : (v) => _update(context, r, {'childMultiplicity': v!.wire}),
        ),
        _gap(),
        Row(
          children: [
            const Text('外部キー制約名: '),
            DropdownButton<NameMode>(
              value: r.nameMode,
              items: const [
                DropdownMenuItem(value: NameMode.auto, child: Text('自動')),
                DropdownMenuItem(value: NameMode.manual, child: Text('手動')),
              ],
              onChanged: dis
                  ? null
                  : (v) => _update(context, r, {
                      'nameMode': v!.wire,
                      if (v == NameMode.manual && r.name.isEmpty)
                        'name': m.foreignKeyName(r),
                    }),
            ),
          ],
        ),
        if (r.nameMode == NameMode.auto) Text(m.foreignKeyName(r)),
        if (r.nameMode == NameMode.manual)
          CommitTextField(
            key: ValueKey('fkn$id'),
            label: '制約名',
            value: r.name,
            enabled: !dis,
            validator: (v) => v.isEmpty ? '制約名は必須です' : null,
            onCommit: (v) => _update(context, r, {'name': v}),
          ),
        _gap(),
        for (final (label, key, value) in [
          ('ON DELETE', 'onDelete', r.onDelete),
          ('ON UPDATE', 'onUpdate', r.onUpdate),
        ]) ...[
          DropdownButtonFormField<RefAction>(
            key: ValueKey('$key$id$value'),
            initialValue: value,
            decoration: InputDecoration(
              labelText: label,
              isDense: true,
              border: const OutlineInputBorder(),
            ),
            items: [
              for (final e in _actions.entries)
                if (!(e.key == RefAction.setNull && childHasNotNull))
                  DropdownMenuItem(value: e.key, child: Text(e.value)),
            ],
            onChanged: dis ? null : (v) => _update(context, r, {key: v!.wire}),
          ),
          _gap(),
        ],
        SwitchListTile(
          dense: true,
          title: const Text('ロック'),
          value: r.locked,
          onChanged: (v) => session.run(SetLockedCommand([id], v)),
        ),
      ],
    );
  }
}
