import 'package:flutter/material.dart';

import '../common/common.dart';
import '../model/model.dart';
import '../session/session.dart';

/// テーブルリスト(3.5)。右ペイン下。
class TableListPanel extends StatefulWidget {
  const TableListPanel(
      {super.key, required this.session, required this.onReveal, required this.onPlace});
  final EditorSession session;

  /// 配置済みエンティティをクリックしたとき、その位置へスクロールする。
  final void Function(int entityId) onReveal;

  /// 未配置のエンティティをダブルクリックしたとき、現在のダイアグラムへ配置する。
  final void Function(int entityId) onPlace;

  @override
  State<TableListPanel> createState() => _TableListPanelState();
}

class _TableListPanelState extends State<TableListPanel> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    final m = s.model;
    final q = _query.toLowerCase();
    final all = m.entities.toList()..sort((a, b) => a.id.compareTo(b.id));
    final shown = all
        .where((e) =>
            q.isEmpty ||
            e.logicalName.toLowerCase().contains(q) ||
            e.physicalName.toLowerCase().contains(q))
        .toList();
    final theme = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 2),
        child: Text('${Strings.tableListHeader}（${all.length}）',
            style: theme.textTheme.titleSmall),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: TextField(
          decoration: const InputDecoration(
              hintText: Strings.search, isDense: true, prefixIcon: Icon(Icons.search, size: 18)),
          onChanged: (v) => setState(() => _query = v),
        ),
      ),
      Expanded(
        child: ListView.builder(
          itemCount: shown.length,
          itemBuilder: (context, i) {
            final e = shown[i];
            final placed = s.diagram.placementOf(e.id) != null;
            final cols = e is TableEntity
                ? m.expand(e).columns.length
                : (e as ViewEntity).viewType == ViewType.function
                    ? e.function.columns.length
                    : e.viewType == ViewType.sql
                        ? e.sql.columns.length
                        : e.join.columns.length;
            final selected = s.selection.contains(e.id);
            final color = placed ? theme.colorScheme.onSurface : theme.disabledColor;
            return InkWell(
              onTap: () {
                s.setSelection([e.id]);
                if (placed) widget.onReveal(e.id);
              },
              onDoubleTap: () {
                if (!placed) widget.onPlace(e.id);
              },
              child: Container(
                color: selected ? theme.colorScheme.primary.withValues(alpha: 0.15) : null,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                child: Row(children: [
                  if (e is ViewEntity)
                    Container(
                      margin: const EdgeInsets.only(right: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                          border: Border.all(color: color), borderRadius: BorderRadius.circular(3)),
                      child: Text('VIEW', style: TextStyle(fontSize: 9, color: color)),
                    ),
                  Expanded(
                      child: Text(e.displayLabel,
                          overflow: TextOverflow.ellipsis, style: TextStyle(color: color))),
                  if (e is TableEntity && e.triggers.isNotEmpty)
                    Container(
                      key: ValueKey('trg${e.id}'),
                      margin: const EdgeInsets.only(right: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                          border: Border.all(color: color), borderRadius: BorderRadius.circular(3)),
                      child: Text('トリガー${e.triggers.length}', style: TextStyle(fontSize: 10, color: color)),
                    ),
                  Text('$cols', style: TextStyle(color: color)),
                ]),
              ),
            );
          },
        ),
      ),
    ]);
  }
}
