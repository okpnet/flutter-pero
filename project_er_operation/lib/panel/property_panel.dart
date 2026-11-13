import 'package:flutter/material.dart' hide Orientation;

import '../command/command.dart';
import '../common/common.dart';
import '../dialog/dialog.dart';
import '../model/model.dart';
import '../session/session.dart';
import 'trigger_editor.dart';

/// プロパティペイン(3.6)。右ペイン上。
/// 項目は機能別のタブに分け、入力欄は1項目1行で縦に並べる(3.6-7、3.6-8)。
class PropertyPanel extends StatefulWidget {
  const PropertyPanel({
    super.key,
    required this.session,
    required this.nameFocus,
    required this.onManageMethods,
    required this.onEditView,
  });
  final EditorSession session;

  /// ダブルクリックでフォーカスを移す論理名入力(3.4-7)。
  final FocusNode nameFocus;

  /// メソッド管理ダイアログを開く(メソッド選択欄の「…」)。
  final Future<void> Function() onManageMethods;

  /// 関数ビューの定義ダイアログを開く。
  final Future<void> Function(int viewId) onEditView;

  @override
  State<PropertyPanel> createState() => _PropertyPanelState();
}

/// 選択するオブジェクトの種類ごとのタブ。
class _Kind {
  const _Kind(this.name, this.tabs);
  final String name;
  final List<String> tabs;
}

const _modelKind = _Kind('model', ['モデル', 'ダイアグラム']);
const _tableKind = _Kind('table', ['基本', '列', '制約', 'トリガー', 'クエリ']);
const _viewKind = _Kind('view', ['基本', '定義', 'クエリ']);
const _relKind = _Kind('rel', ['基本', '列対応', '参照規則']);

class _PropertyPanelState extends State<PropertyPanel> {
  /// 種類ごとの選択中のタブ。同じ種類の間は保持する(3.6-7)。
  final Map<String, int> _tab = {};

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final sel = session.selection.toList();
    if (sel.length > 1) {
      return ListView(
        padding: _padding,
        children: [_MultiProps(session: session, ids: sel)],
      );
    }
    final id = sel.isEmpty ? null : sel.single;
    final e = id == null ? null : session.model.entityById(id);
    final r = id == null ? null : session.model.relationshipById(id);
    final _Kind kind = e is TableEntity
        ? _tableKind
        : e is ViewEntity
        ? _viewKind
        : r != null
        ? _relKind
        : _modelKind;
    final tab = (_tab[kind.name] ?? 0).clamp(0, kind.tabs.length - 1);

    final Widget body;
    if (e is TableEntity) {
      body = _TableProps(
        key: ValueKey('t$id'),
        session: session,
        id: id!,
        tab: tab,
        nameFocus: widget.nameFocus,
        onManageMethods: widget.onManageMethods,
      );
    } else if (e is ViewEntity) {
      body = _ViewProps(
        key: ValueKey('v$id'),
        session: session,
        id: id!,
        tab: tab,
        nameFocus: widget.nameFocus,
        onEdit: () => widget.onEditView(id),
      );
    } else if (r != null) {
      body = _RelationshipProps(
        key: ValueKey('r$id'),
        session: session,
        id: id!,
        tab: tab,
      );
    } else {
      body = _ModelProps(session: session, tab: tab);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TabStrip(
          labels: kind.tabs,
          index: tab,
          onChanged: (i) => setState(() => _tab[kind.name] = i),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView(
            key: ValueKey('props-${kind.name}-$tab'),
            padding: _padding,
            children: [body],
          ),
        ),
      ],
    );
  }
}

const EdgeInsets _padding = EdgeInsets.fromLTRB(12, 12, 12, 24);

/// タブの見出し(幅が狭いときは折り返す)。
class _TabStrip extends StatelessWidget {
  const _TabStrip({
    required this.labels,
    required this.index,
    required this.onChanged,
  });
  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        children: [
          for (var i = 0; i < labels.length; i++)
            ChoiceChip(
              label: Text(labels[i]),
              selected: i == index,
              visualDensity: VisualDensity.compact,
              onSelected: (_) => onChanged(i),
            ),
        ],
      ),
    );
  }
}

/// 入力欄の行間(3.6-8)。
Widget _gap([double h = 16]) => SizedBox(height: h);

/// 入力欄の見た目。ラベルは入力欄の上に置く(3.6-8)。
InputDecoration _deco(String label) => InputDecoration(
  labelText: label,
  floatingLabelBehavior: FloatingLabelBehavior.always,
  isDense: true,
  border: const OutlineInputBorder(),
  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
);

Widget _hint(BuildContext context, String text) =>
    Text(text, style: Theme.of(context).textTheme.bodySmall);

/// 選択肢の入力欄(1項目1行)。
Widget _dropdown<T>({
  required Key key,
  required String label,
  required T? value,
  required List<DropdownMenuItem<T>> items,
  required ValueChanged<T?>? onChanged,
}) => DropdownButtonFormField<T>(
  key: key,
  initialValue: value,
  isExpanded: true,
  decoration: _deco(label),
  items: items,
  onChanged: onChanged,
);

Widget _switch(
  String title,
  bool value,
  ValueChanged<bool>? onChanged,
) => SwitchListTile(
  contentPadding: EdgeInsets.zero,
  title: Text(title),
  value: value,
  onChanged: onChanged,
);

// ---- モデル・ダイアグラム ----

class _ModelProps extends StatelessWidget {
  const _ModelProps({required this.session, required this.tab});
  final EditorSession session;
  final int tab;

  @override
  Widget build(BuildContext context) {
    final m = session.model;
    final p = m.properties;
    final d = session.diagram;
    void upd(Map<String, Object?> patch) =>
        session.run(UpdateModelPropertiesCommand(patch));
    if (tab == 0) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
          _dropdown<DbKind>(
            key: ValueKey('db${p.targetDb}'),
            label: '対象のデータベース',
            value: p.targetDb,
            items: [
              for (final k in DbKindFilter.visible)
                DropdownMenuItem(value: k, child: Text(k.wire)),
            ],
            onChanged: (v) {
              if (v == null) return;
              // 現在のポストファイルがその種類でなければ、その種類のポストファイルへ切り替える。
              final assoc = session.settings.postKinds;
              final cur = session.postCatalog.byPath(p.postPath);
              final candidates = session.postCatalog.forKind(v, assoc);
              final switchPost = candidates.isNotEmpty && (cur == null || cur.kindOf(assoc) != v);
              upd({'targetDb': v.wire, if (switchPost) 'postPath': candidates.first.path});
            },
          ),
          _gap(),
          _dropdown<String>(
            key: ValueKey('postPick${p.postPath}'),
            label: 'ポストファイル(一覧から選択。対象DBはメタ情報で決まる)',
            value: session.postCatalog.byPath(p.postPath)?.path,
            items: [
              for (final f in session.postCatalog.valid)
                DropdownMenuItem(value: f.path, child: Text(f.label, overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (path) {
              final f = path == null ? null : session.postCatalog.byPath(path);
              final kind = f?.kindOf(session.settings.postKinds);
              if (f == null || kind == null) return;
              upd({'postPath': f.path, 'targetDb': kind.wire});
            },
          ),
          _gap(),
          CommitTextField(
            key: const ValueKey('postPath'),
            label: 'ポストファイルのパス',
            value: p.postPath,
            onCommit: (v) => upd({'postPath': v}),
          ),
          _gap(),
          _switch(
            '出力にスキーマを含める',
            p.includeSchema,
            (v) => upd({'includeSchema': v}),
          ),
          _gap(8),
          CommitTextField(
            key: const ValueKey('schema'),
            label: 'スキーマ(ダイアグラムのスキーマが空のときに使う)',
            value: p.schema,
            onCommit: (v) => upd({'schema': v}),
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
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
        CommitTextField(
          key: ValueKey('dsc${d.id}'),
          label: 'スキーマ(空でモデルのスキーマ)',
          value: d.schema,
          onCommit: (v) => session.run(SetDiagramSchemaCommand(d.id, v)),
        ),
        _gap(),
        _dropdown<PageSize>(
          key: ValueKey('ps${d.id}${d.pageSize}'),
          label: '用紙サイズ',
          value: d.pageSize,
          items: [
            for (final k in PageSize.values)
              DropdownMenuItem(value: k, child: Text(k.wire)),
          ],
          onChanged: (v) => v == null
              ? null
              : session.run(UpdateDiagramPageCommand(d.id, v, d.orientation)),
        ),
        _gap(),
        _dropdown<Orientation>(
          key: ValueKey('or${d.id}${d.orientation}'),
          label: '向き',
          value: d.orientation,
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
        _gap(),
        _switch('ロック', all, (v) => session.run(SetLockedCommand(ids, v))),
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
    required this.tab,
    required this.nameFocus,
    required this.onManageMethods,
  });
  final EditorSession session;
  final int id;
  final int tab;
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
    final dis = t.locked; // ロック中はロック以外を無効表示(5.3-2-5)
    return switch (tab) {
      0 => _basic(t, dis),
      1 => _columns(context, t, dis),
      2 => _constraints(t, dis),
      3 => TriggerEditor(
        session: session,
        table: t,
        enabled: !dis,
        onEdit: _edit,
        onManageMethods: onManageMethods,
      ),
      _ => _queries(t, dis),
    };
  }

  Widget _basic(TableEntity t, bool dis) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
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
      _gap(),
      _switch(
        'ロック',
        t.locked,
        (v) => session.run(SetLockedCommand([id], v)),
      ),
    ],
  );

  Widget _columns(BuildContext context, TableEntity t, bool dis) {
    final m = session.model;
    final exp = m.expand(t).columns;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.tonalIcon(
            onPressed: dis ? null : () => session.run(AddColumnCommand(id)),
            icon: const Icon(Icons.add, size: 16),
            label: const Text('列を追加'),
          ),
        ),
        _gap(8),
        ReorderableListView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          onReorderItem: (from, to) {
            if (dis) return;
            _edit((c) {
              final col = c.columns.removeAt(from);
              c.columns.insert(to, col);
            });
          },
          children: [
            for (var i = 0; i < t.columns.length; i++)
              _ColumnEditor(
                key: ValueKey('col${t.columns[i].id}'),
                session: session,
                table: t,
                column: t.columns[i],
                index: i,
                enabled: !dis,
                onEdit: (f) =>
                    _edit((c) => f(c.columnById(t.columns[i].id)!)),
                onDelete: () => deleteColumnWithConfirm(
                  context,
                  session,
                  t.id,
                  t.columns[i].id,
                ),
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
      ],
    );
  }

  Widget _constraints(TableEntity t, bool dis) {
    final m = session.model;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ConstraintsEditor(
          title: 'インデックス',
          list: t.indexes,
          table: t,
          session: session,
          enabled: !dis,
          nameOf: (c) => m.indexName(t, c),
          onChange: (f) => _edit((c) => f(c.indexes)),
        ),
        _gap(24),
        _ConstraintsEditor(
          title: 'ユニーク',
          list: t.uniques,
          table: t,
          session: session,
          enabled: !dis,
          nameOf: (c) => m.uniqueName(t, c),
          onChange: (f) => _edit((c) => f(c.uniques)),
          nullsNotDistinctOption: true,
        ),
        _gap(24),
        _ChecksEditor(
          table: t,
          session: session,
          enabled: !dis,
          onChange: (f) => _edit((c) => f(c.checks)),
        ),
      ],
    );
  }

  Widget _queries(TableEntity t, bool dis) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
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
    ],
  );
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

/// 列の編集。見出しに要約を表示し、開くと項目を1項目1行で縦に並べる(スクロール量を減らす)。
class _ColumnEditor extends StatelessWidget {
  const _ColumnEditor({
    super.key,
    required this.session,
    required this.table,
    required this.column,
    required this.index,
    required this.enabled,
    required this.onEdit,
    required this.onDelete,
    required this.onManageMethods,
  });
  final EditorSession session;
  final TableEntity table;
  final ColumnDef column;
  final int index;
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
    final summary = [
      m.typeLabel(c),
      if (c.pk) 'PK',
      if (c.notNull && !c.pk) 'NotNull',
      if (inUse) 'FK',
    ].join('  ');
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      color: inUse ? Colors.amber.withValues(alpha: 0.12) : null,
      child: ExpansionTile(
        key: ValueKey('colTile${c.id}'),
        tilePadding: const EdgeInsets.symmetric(horizontal: 8),
        childrenPadding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
        expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
        leading: ReorderableDragStartListener(
          index: index,
          enabled: enabled,
          child: const Icon(Icons.drag_indicator, size: 20),
        ),
        title: Text(
          c.physicalName.isEmpty ? '(物理名なし)' : c.physicalName,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          c.logicalName.isEmpty ? summary : '${c.logicalName}  $summary',
          style: const TextStyle(fontSize: 11),
        ),
        children: [
          _gap(8),
          CommitTextField(
            key: ValueKey('cl${c.id}'),
            label: '論理名',
            value: c.logicalName,
            enabled: enabled,
            onCommit: (v) => onEdit((x) => x.logicalName = v),
          ),
          _gap(),
          CommitTextField(
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
          _gap(),
          _dropdown<String>(
            key: ValueKey('ct${c.id}${c.typeId}'),
            label: '型',
            value: type == null ? null : c.typeId,
            items: [
              for (final t in m.types)
                DropdownMenuItem(
                  value: t.id,
                  child: Text(t.displayName, overflow: TextOverflow.ellipsis),
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
                      x.precision = t.paramKind == ParamKind.precisionScale
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
          if (type?.paramKind == ParamKind.length) ...[
            _gap(),
            _intField(
              'cn${c.id}',
              '長さ',
              c.length,
              enabled,
              (v) => onEdit((x) => x.length = v),
            ),
          ],
          if (type?.paramKind == ParamKind.precisionScale) ...[
            _gap(),
            _intField(
              'cpr${c.id}',
              '精度',
              c.precision,
              enabled,
              (v) => onEdit((x) => x.precision = v),
            ),
            _gap(),
            _intField(
              'csc${c.id}',
              'スケール',
              c.scale,
              enabled,
              (v) => onEdit((x) => x.scale = v),
            ),
          ],
          _gap(8),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('PK(主キー)'),
            value: c.pk,
            onChanged: enabled
                ? (v) => onEdit((x) {
                    x.pk = v ?? false;
                    if (x.pk) x.notNull = true;
                  })
                : null,
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('NotNull'),
            value: c.notNull || c.pk,
            onChanged: enabled && !c.pk
                ? (v) => onEdit((x) => x.notNull = v ?? false)
                : null,
          ),
          _gap(8),
          _dropdown<DefaultKind>(
            key: ValueKey('cdk${c.id}${c.defaultKind}$isAuto'),
            label: 'デフォルト',
            value: isAuto ? DefaultKind.none : c.defaultKind,
            items: const [
              DropdownMenuItem(value: DefaultKind.none, child: Text('なし')),
              DropdownMenuItem(value: DefaultKind.value, child: Text('値')),
              DropdownMenuItem(
                value: DefaultKind.method,
                child: Text('メソッド'),
              ),
              DropdownMenuItem(value: DefaultKind.expression, child: Text('式')),
            ],
            onChanged: enabled && !isAuto
                ? (v) => onEdit((x) => x.defaultKind = v ?? DefaultKind.none)
                : null,
          ),
          _gap(),
          if (c.defaultKind == DefaultKind.method && !isAuto)
            Row(
              children: [
                Expanded(
                  child: _dropdown<int>(
                    key: ValueKey('cdm${c.id}${c.defaultMethodId}'),
                    label: 'メソッド',
                    value: methods.any((x) => x.id == c.defaultMethodId)
                        ? c.defaultMethodId
                        : null,
                    items: [
                      for (final x in methods)
                        DropdownMenuItem(value: x.id, child: Text(x.name)),
                    ],
                    onChanged: enabled
                        ? (v) => onEdit((x) => x.defaultMethodId = v)
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
          else if (c.defaultKind == DefaultKind.expression && !isAuto)
            CommitTextField(
              key: ValueKey('cde${c.id}'),
              label: 'デフォルトの式(そのまま出力)',
              value: c.defaultExpression,
              enabled: enabled,
              validator: (v) => v.trim().isEmpty ? '式は空にできません' : null,
              onCommit: (v) => onEdit((x) => x.defaultExpression = v),
            )
          else
            CommitTextField(
              key: ValueKey('cdv${c.id}'),
              label: 'デフォルト値',
              value: c.defaultValue,
              enabled:
                  enabled && c.defaultKind == DefaultKind.value && !isAuto,
              validator: (v) => v.isEmpty ? '値は空にできません' : null,
              onCommit: (v) => onEdit((x) => x.defaultValue = v),
            ),
          _gap(),
          CommitTextField(
            key: ValueKey('cm${c.id}'),
            label: 'コメント',
            value: c.comment,
            enabled: enabled,
            onCommit: (v) => onEdit((x) => x.comment = v),
          ),
          _gap(8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: enabled ? onDelete : null,
              icon: const Icon(Icons.delete_outline, size: 18),
              label: const Text('この列を削除'),
            ),
          ),
        ],
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
    this.nullsNotDistinctOption = false,
  });

  /// ユニークのときtrue。NULLS NOT DISTINCT の切替を表示する(6.4-2)。
  final bool nullsNotDistinctOption;
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
            Expanded(
              child: Text(title, style: Theme.of(context).textTheme.titleSmall),
            ),
            FilledButton.tonalIcon(
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
              icon: const Icon(Icons.add, size: 16),
              label: const Text('追加'),
            ),
          ],
        ),
        _gap(8),
        for (final c in list)
          Card(
            margin: const EdgeInsets.symmetric(vertical: 4),
            child: Padding(
              padding: const EdgeInsets.all(12),
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
                      IconButton(
                        tooltip: '削除',
                        icon: const Icon(Icons.delete_outline, size: 18),
                        onPressed: enabled
                            ? () => onChange(
                                (l) => l.removeWhere((e) => e.id == c.id),
                              )
                            : null,
                      ),
                    ],
                  ),
                  _dropdown<NameMode>(
                    key: ValueKey('nm${c.id}${c.nameMode}'),
                    label: '名前の決め方',
                    value: c.nameMode,
                    items: const [
                      DropdownMenuItem(value: NameMode.auto, child: Text('自動')),
                      DropdownMenuItem(
                        value: NameMode.manual,
                        child: Text('手動'),
                      ),
                    ],
                    onChanged: enabled
                        ? (v) => onChange((l) {
                            final x = l.firstWhere((e) => e.id == c.id);
                            x.nameMode = v ?? NameMode.auto;
                            if (x.nameMode == NameMode.manual &&
                                x.name.isEmpty) {
                              x.name = nameOf(c);
                            }
                          })
                        : null,
                  ),
                  if (c.nameMode == NameMode.manual) ...[
                    _gap(),
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
                  ],
                  if (nullsNotDistinctOption) ...[
                    _gap(),
                    _switch(
                      'NULLを同値として扱う(NULLS NOT DISTINCT)',
                      c.nullsNotDistinct,
                      enabled
                          ? (v) => onChange(
                              (l) => l.firstWhere((e) => e.id == c.id).nullsNotDistinct = v)
                          : null,
                    ),
                  ],
                  _gap(),
                  Text('列', style: Theme.of(context).textTheme.bodySmall),
                  _gap(4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
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

/// CHECK制約(6.4-5)。
class _ChecksEditor extends StatelessWidget {
  const _ChecksEditor({
    required this.table,
    required this.session,
    required this.enabled,
    required this.onChange,
  });
  final TableEntity table;
  final EditorSession session;
  final bool enabled;
  final void Function(void Function(List<CheckDef> l) f) onChange;

  @override
  Widget build(BuildContext context) {
    final m = session.model;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text('CHECK制約', style: Theme.of(context).textTheme.titleSmall)),
            FilledButton.tonalIcon(
              onPressed: enabled
                  ? () => onChange((l) => l.add(CheckDef(id: m.allocateId())))
                  : null,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('追加'),
            ),
          ],
        ),
        _gap(8),
        for (final c in table.checks)
          Card(
            margin: const EdgeInsets.symmetric(vertical: 4),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(m.checkName(table, c),
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                      ),
                      IconButton(
                        tooltip: '削除',
                        icon: const Icon(Icons.delete_outline, size: 18),
                        onPressed: enabled
                            ? () => onChange((l) => l.removeWhere((e) => e.id == c.id))
                            : null,
                      ),
                    ],
                  ),
                  _dropdown<NameMode>(
                    key: ValueKey('ckm${c.id}${c.nameMode}'),
                    label: '名前の決め方',
                    value: c.nameMode,
                    items: const [
                      DropdownMenuItem(value: NameMode.auto, child: Text('自動')),
                      DropdownMenuItem(value: NameMode.manual, child: Text('手動')),
                    ],
                    onChanged: enabled
                        ? (v) => onChange((l) {
                              final x = l.firstWhere((e) => e.id == c.id);
                              x.nameMode = v ?? NameMode.auto;
                              if (x.nameMode == NameMode.manual && x.name.isEmpty) {
                                x.name = m.checkName(table, c);
                              }
                            })
                        : null,
                  ),
                  if (c.nameMode == NameMode.manual) ...[
                    _gap(),
                    CommitTextField(
                      key: ValueKey('ckn${c.id}'),
                      label: '制約名',
                      value: c.name,
                      enabled: enabled,
                      validator: (v) => v.isEmpty ? '制約名は必須です' : null,
                      onCommit: (v) =>
                          onChange((l) => l.firstWhere((e) => e.id == c.id).name = v),
                    ),
                  ],
                  _gap(),
                  CommitTextField(
                    key: ValueKey('cke${c.id}'),
                    label: '検査式(括弧の内側)',
                    value: c.expression,
                    enabled: enabled,
                    multiline: true,
                    validator: (v) => v.trim().isEmpty ? '検査式は必須です' : null,
                    onCommit: (v) =>
                        onChange((l) => l.firstWhere((e) => e.id == c.id).expression = v),
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
    required this.tab,
    required this.nameFocus,
    required this.onEdit,
  });
  final EditorSession session;
  final int id;
  final int tab;
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
      children: switch (tab) {
        0 => [
          _hint(context, 'ビュー(${switch (v.viewType) { ViewType.join => '結合', ViewType.function => '関数', ViewType.sql => 'SQL' }})'),
          _gap(),
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
          _switch('ロック', v.locked, (x) => session.run(SetLockedCommand([id], x))),
        ],
        1 => [
          Text(
            '定義: ${switch (v.viewType) { ViewType.join => 'ソース${v.join.sources.length}件 / 出力列${v.join.columns.length}件', ViewType.function => '戻り列${v.function.columns.length}件', ViewType.sql => 'SQL ${v.sql.sql.length}文字 / 列${v.sql.columns.length}件' }}',
          ),
          _gap(),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.tonalIcon(
              onPressed: dis ? null : onEdit,
              icon: const Icon(Icons.edit, size: 16),
              label: const Text('定義を編集'),
            ),
          ),
            _hint(context, '結合ビューの定義ダイアログは今後のバージョンで対応します(定義は.peroファイルから読み込めます)'),
        ],
        _ => [
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
        ],
      },
    );
  }
}

// ---- リレーションシップ ----

class _RelationshipProps extends StatelessWidget {
  const _RelationshipProps({
    super.key,
    required this.session,
    required this.id,
    required this.tab,
  });
  final EditorSession session;
  final int id;
  final int tab;

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
      children: switch (tab) {
        0 => [
          Row(
            children: [
              Expanded(
                child: Text('親: ${p.displayLabel}\n子: ${c.displayLabel}'),
              ),
              IconButton(
                tooltip: '親と子を入れ替える',
                icon: const Icon(Icons.swap_vert),
                onPressed: dis
                    ? null
                    : () => session.run(SwapRelationshipDirectionCommand(id)),
              ),
            ],
          ),
          _gap(),
          _switch(
            '依存関係(識別関係)',
            r.dependency,
            dis ? null : (v) => _update(context, r, {'dependency': v}),
          ),
          _gap(8),
          _dropdown<Multiplicity>(
            key: ValueKey('mul$id${r.childMultiplicity}'),
            label: '子側多重度',
            value: r.childMultiplicity,
            items: const [
              DropdownMenuItem(value: Multiplicity.one, child: Text('1')),
              DropdownMenuItem(value: Multiplicity.many, child: Text('多')),
            ],
            onChanged: dis
                ? null
                : (v) => _update(context, r, {'childMultiplicity': v!.wire}),
          ),
          _gap(),
          _switch(
            'ロック',
            r.locked,
            (v) => session.run(SetLockedCommand([id], v)),
          ),
        ],
        1 => [
          for (var i = 0; i < r.columnPairs.length; i++) ...[
            _dropdown<int>(
              key: ValueKey('pair$id$i${r.columnPairs[i].childColumnId}'),
              label:
                  '親の列「${parentCols.where((x) => x.column.id == r.columnPairs[i].parentColumnId).firstOrNull?.column.physicalName ?? '?'}」に対応する子の列',
              value:
                  childCols.any(
                    (x) => x.column.id == r.columnPairs[i].childColumnId,
                  )
                  ? r.columnPairs[i].childColumnId
                  : null,
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
                            'parentColumnId': r.columnPairs[k].parentColumnId,
                            'childColumnId': k == i
                                ? v
                                : r.columnPairs[k].childColumnId,
                          },
                      ];
                      _update(context, r, {'columnPairs': pairs});
                    },
            ),
            _gap(),
          ],
        ],
        _ => [
          _dropdown<NameMode>(
            key: ValueKey('fknm$id${r.nameMode}'),
            label: '外部キー制約名の決め方',
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
          _gap(),
          if (r.nameMode == NameMode.auto)
            Text('制約名: ${m.foreignKeyName(r)}')
          else
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
            _dropdown<RefAction>(
              key: ValueKey('$key$id$value'),
              label: label,
              value: value,
              items: [
                for (final e in _actions.entries)
                  if (!(e.key == RefAction.setNull && childHasNotNull))
                    DropdownMenuItem(value: e.key, child: Text(e.value)),
              ],
              onChanged: dis
                  ? null
                  : (v) => _update(context, r, {key: v!.wire}),
            ),
            _gap(),
          ],
          _dropdown<Deferrable>(
            key: ValueKey('dfr$id${r.deferrable}'),
            label: '遅延可否(DEFERRABLE)',
            value: r.deferrable,
            items: const [
              DropdownMenuItem(value: Deferrable.none, child: Text('指定しない')),
              DropdownMenuItem(
                value: Deferrable.immediate,
                child: Text('DEFERRABLE INITIALLY IMMEDIATE'),
              ),
              DropdownMenuItem(
                value: Deferrable.deferred,
                child: Text('DEFERRABLE INITIALLY DEFERRED'),
              ),
            ],
            onChanged: dis
                ? null
                : (v) => _update(context, r, {'deferrable': v!.wire}),
          ),
          _gap(),
        ],
      },
    );
  }
}
