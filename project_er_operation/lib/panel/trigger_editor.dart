import 'package:flutter/material.dart';

import '../common/common.dart';
import '../model/model.dart';
import '../session/session.dart';

InputDecoration _deco(String label) => InputDecoration(
  labelText: label,
  floatingLabelBehavior: FloatingLabelBehavior.always,
  isDense: true,
  border: const OutlineInputBorder(),
  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
);

/// テーブルのトリガー編集(6.5)。一覧(順、名前、タイミング、イベント)、追加、削除、ドラッグ&ドロップによる順の変更。
/// 変更は [onEdit] へ(テーブルの複製に対する書き換え)渡し、1回の確定を1コマンドにする。
class TriggerEditor extends StatelessWidget {
  const TriggerEditor({
    super.key,
    required this.session,
    required this.table,
    required this.enabled,
    required this.onEdit,
    required this.onManageMethods,
  });

  final EditorSession session;
  final TableEntity table;
  final bool enabled;
  final void Function(void Function(TableEntity t) f) onEdit;
  final Future<void> Function() onManageMethods;

  @override
  Widget build(BuildContext context) {
    final m = session.model;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        FilledButton.tonalIcon(
          onPressed: enabled ? () => onEdit((t) => t.triggers.add(TriggerDef(id: session.model.allocateId()))) : null,
          icon: const Icon(Icons.add, size: 16),
          label: const Text('追加'),
        ),
      ]),
      ReorderableListView(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        buildDefaultDragHandles: enabled,
        onReorderItem: (from, to) {
          if (!enabled) return;
          onEdit((t) => t.triggers.insert(to, t.triggers.removeAt(from)));
        },
        children: [
          for (var i = 0; i < table.triggers.length; i++)
            _TriggerCard(
              key: ValueKey('trg${table.triggers[i].id}'),
              session: session,
              table: table,
              trigger: table.triggers[i],
              index: i,
              enabled: enabled,
              methods: m.methods.where((x) => x.kind == MethodKind.trigger).toList(),
              onEdit: (f) => onEdit((t) => f(t.triggers.firstWhere((g) => g.id == table.triggers[i].id))),
              onDelete: () => onEdit((t) => t.triggers.removeWhere((g) => g.id == table.triggers[i].id)),
              onManageMethods: onManageMethods,
            ),
        ],
      ),
    ]);
  }
}

class _TriggerCard extends StatefulWidget {
  const _TriggerCard({
    super.key,
    required this.session,
    required this.table,
    required this.trigger,
    required this.index,
    required this.enabled,
    required this.methods,
    required this.onEdit,
    required this.onDelete,
    required this.onManageMethods,
  });
  final EditorSession session;
  final TableEntity table;
  final TriggerDef trigger;
  final int index;
  final bool enabled;
  final List<MethodDef> methods;
  final void Function(void Function(TriggerDef g) f) onEdit;
  final VoidCallback onDelete;
  final Future<void> Function() onManageMethods;

  @override
  State<_TriggerCard> createState() => _TriggerCardState();
}

class _TriggerCardState extends State<_TriggerCard> {
  DbKind _bodyDb = DbKind.postgresql;

  @override
  Widget build(BuildContext context) {
    final g = widget.trigger;
    final m = widget.session.model;
    final name = m.triggerName(widget.table, g);
    final en = widget.enabled;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 3),
      child: ExpansionTile(
        dense: true,
        tilePadding: const EdgeInsets.symmetric(horizontal: 8),
        childrenPadding: const EdgeInsets.all(8),
        title: Text('${widget.index + 1}. $name', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        subtitle: Text('${g.timing.wire}  ${g.events.map((e) => e.wire).join(' / ')}', style: const TextStyle(fontSize: 11)),
        trailing: IconButton(
          tooltip: 'トリガーを削除',
          icon: const Icon(Icons.delete_outline, size: 18),
          onPressed: en ? widget.onDelete : null,
        ),
        children: [
          SegmentedButton<TriggerSource>(
            segments: const [
              ButtonSegment(value: TriggerSource.public, label: Text('パブリック')),
              ButtonSegment(value: TriggerSource.inline, label: Text('入力')),
            ],
            selected: {g.source},
            onSelectionChanged: en ? (s) => widget.onEdit((x) => x.source = s.first) : null,
          ),
          const SizedBox(height: 16),
          if (g.source == TriggerSource.public)
            Row(children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  key: ValueKey('tm${g.id}${g.methodId}'),
                  initialValue: widget.methods.any((x) => x.id == g.methodId) ? g.methodId : null,
                  isExpanded: true,
                  decoration: _deco('メソッド(種別がトリガー)'),
                  items: [for (final x in widget.methods) DropdownMenuItem(value: x.id, child: Text(x.name))],
                  onChanged: en ? (v) => widget.onEdit((x) => x.methodId = v) : null,
                ),
              ),
              IconButton(tooltip: 'メソッド管理を開く', icon: const Icon(Icons.more_horiz), onPressed: en ? widget.onManageMethods : null),
            ])
          else ...[
            DropdownButtonFormField<DbKind>(
              key: ValueKey('tdb${g.id}${_bodyDb.wire}'),
              initialValue: _bodyDb,
              isExpanded: true,
              decoration: _deco('本体を入力する対象DB'),
              items: [for (final d in DbKind.values) DropdownMenuItem(value: d, child: Text(d.wire))],
              onChanged: (v) => setState(() => _bodyDb = v ?? _bodyDb),
            ),
            const SizedBox(height: 16),
            CommitTextField(
              key: ValueKey('tb${g.id}${_bodyDb.wire}'),
              label: '本体(${_bodyDb.wire}。{{table}} {{trigger}} を置換)',
              value: g.inlineBodies[_bodyDb] ?? '',
              enabled: en,
              multiline: true,
              onCommit: (v) => widget.onEdit((x) => x.inlineBodies[_bodyDb] = v),
            ),
          ],
          const SizedBox(height: 16),
          DropdownButtonFormField<NameMode>(
            key: ValueKey('tnm${g.id}${g.nameMode}'),
            initialValue: g.nameMode,
            isExpanded: true,
            decoration: _deco('名前の決め方'),
            items: const [
              DropdownMenuItem(value: NameMode.auto, child: Text('自動')),
              DropdownMenuItem(value: NameMode.manual, child: Text('手動')),
            ],
            onChanged: en
                ? (v) => widget.onEdit((x) {
                      x.nameMode = v ?? NameMode.auto;
                      if (x.nameMode == NameMode.manual && x.name.isEmpty) x.name = name;
                    })
                : null,
          ),
          const SizedBox(height: 16),
          if (g.nameMode == NameMode.auto)
            Text(name, style: Theme.of(context).textTheme.bodySmall)
          else
            CommitTextField(
              key: ValueKey('tn${g.id}'),
              label: 'トリガー名',
              value: g.name,
              enabled: en,
              validator: (v) {
                if (v.isEmpty) return '名前は必須です';
                for (final t in m.tables) {
                  for (final o in t.triggers) {
                    if (o.id != g.id && m.triggerName(t, o).toLowerCase() == v.toLowerCase()) return '同じ名前が存在します';
                  }
                }
                return null;
              },
              onCommit: (v) => widget.onEdit((x) => x.name = v),
            ),
          const SizedBox(height: 16),
          DropdownButtonFormField<TriggerTiming>(
            key: ValueKey('tt${g.id}${g.timing}'),
            initialValue: g.timing,
            isExpanded: true,
            decoration: _deco('タイミング'),
            items: [for (final t in TriggerTiming.values) DropdownMenuItem(value: t, child: Text(t.wire))],
            onChanged: en ? (v) => widget.onEdit((x) => x.timing = v ?? TriggerTiming.before) : null,
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<TriggerForEach>(
            key: ValueKey('tf${g.id}${g.forEach}'),
            initialValue: g.forEach,
            isExpanded: true,
            decoration: _deco('行単位'),
            items: [for (final t in TriggerForEach.values) DropdownMenuItem(value: t, child: Text(t.wire))],
            onChanged: en ? (v) => widget.onEdit((x) => x.forEach = v ?? TriggerForEach.row) : null,
          ),
          const SizedBox(height: 16),
          Text('イベント', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 4),
          Wrap(spacing: 6, children: [
            for (final e in TriggerEvent.values)
              FilterChip(
                label: Text(e.wire),
                selected: g.events.contains(e),
                onSelected: en
                    ? (sel) => widget.onEdit((x) {
                          if (sel) {
                            if (!x.events.contains(e)) x.events.add(e);
                          } else if (x.events.length > 1) {
                            x.events.remove(e); // イベントは1つ以上(6.5-2-6)
                          }
                        })
                    : null,
              ),
          ]),
          const SizedBox(height: 16),
          CommitTextField(
            key: ValueKey('tw${g.id}'),
            label: '条件(WHEN)',
            value: g.when,
            enabled: en,
            onCommit: (v) => widget.onEdit((x) => x.when = v),
          ),
        ],
      ),
    );
  }
}
