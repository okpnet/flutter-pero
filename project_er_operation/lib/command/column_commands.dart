import '../model/model.dart';
import 'command_base.dart';
import 'entity_commands.dart';

/// 列の追加(6.2-6)。
class AddColumnCommand extends ModelCommand {
  AddColumnCommand(this.entityId);
  final int entityId;
  int? createdId;

  @override
  String get type => 'addColumn';
  @override
  Map<String, Object?> argsToJson() => {'entityId': entityId};

  @override
  void apply(CommandContext ctx) {
    final m = ctx.model;
    final t = m.tableById(entityId);
    if (t == null) throw CommandException('テーブルが存在しません');
    if (t.locked) throw CommandException(lockedMessage);
    final used = m.expand(t).columns.map((c) => c.column.physicalName.toLowerCase()).toSet();
    final n = m.smallestUnusedNumber((n) => used.contains('column_$n'));
    final c = ColumnDef(
      id: m.allocateId(),
      logicalName: '列$n',
      physicalName: 'column_$n',
      typeId: 'varchar',
      length: 255,
    );
    t.columns.add(c);
    createdId = c.id;
    ctx.recalcAllPages();
  }
}

/// 列の削除と影響(6.2-7)。
class RemoveColumnCommand extends ModelCommand {
  RemoveColumnCommand(this.entityId, this.columnId);
  final int entityId;
  final int columnId;

  @override
  String get type => 'removeColumn';
  @override
  Map<String, Object?> argsToJson() => {'entityId': entityId, 'columnId': columnId};

  /// 削除できない理由。空なら削除できる。
  static List<String> blockers(ErModel m, int entityId, int columnId) {
    final out = <String>[];
    final t = m.tableById(entityId);
    if (t == null) return ['テーブルが存在しません'];
    if (t.locked) out.add('テーブル「${t.displayLabel}」はロック中です。ロックを解除してください');
    for (final v in m.viewsUsingColumn(columnId)) {
      out.add('ビュー「${v.displayLabel}」がこの列を使っています。先にビューを修正してください');
    }
    for (final r in _relsUsing(m, columnId)) {
      final other = m.entityById(r.parentId == entityId ? r.childId : r.parentId);
      if (r.locked || (other?.locked ?? false)) {
        out.add('この列を使うリレーションシップがロック中です。ロックを解除してください');
      }
    }
    return out;
  }

  /// 確認ダイアログに表示する影響の一覧。
  static List<String> impacts(ErModel m, int entityId, int columnId) {
    final t = m.tableById(entityId);
    if (t == null) return [];
    final out = <String>[];
    for (final c in t.indexes) {
      if (c.columnIds.contains(columnId)) {
        out.add('インデックス ${m.indexName(t, c)}: 列を除外${c.columnIds.length == 1 ? '(列が0になるため削除)' : ''}');
      }
    }
    for (final c in t.uniques) {
      if (c.columnIds.contains(columnId)) {
        out.add('ユニーク ${m.uniqueName(t, c)}: 列を除外${c.columnIds.length == 1 ? '(列が0になるため削除)' : ''}');
      }
    }
    for (final r in _relsUsing(m, columnId)) {
      out.add('リレーションシップ ${m.foreignKeyName(r)}: 削除');
    }
    for (final k in t.checks) {
      if (k.conditions.any((x) => x.columnId == columnId)) {
        out.add('CHECK制約 ${m.checkName(t, k)}: 条件を除外${k.conditions.length == 1 ? '(条件が0になるため削除)' : ''}');
      }
    }
    for (final g in t.triggers) {
      if (g.updateColumnIds.contains(columnId)) {
        out.add('トリガー ${m.triggerName(t, g)}: UPDATE列から除外');
      }
    }
    return out;
  }

  static List<Relationship> _relsUsing(ErModel m, int columnId) => m.relationships
      .where((r) => r.columnPairs.any((p) => p.parentColumnId == columnId || p.childColumnId == columnId))
      .toList();

  @override
  void apply(CommandContext ctx) {
    final m = ctx.model;
    final problems = blockers(m, entityId, columnId);
    if (problems.isNotEmpty) throw CommandException(problems.first);
    final t = m.tableById(entityId)!;
    if (t.columnById(columnId) == null) throw CommandException('列が存在しません');
    m.relationships.removeWhere((r) => _relsUsing(m, columnId).contains(r));
    for (final list in [t.indexes, t.uniques]) {
      for (final c in list) {
        c.columnIds.remove(columnId);
      }
      list.removeWhere((c) => c.columnIds.isEmpty);
    }
    // 条件に使っている列は、条件から除外する。条件が0になった制約は削除する。
    final emptied = <int>{};
    for (final k in t.checks) {
      if (!k.conditions.any((x) => x.columnId == columnId)) continue;
      k.conditions.removeWhere((x) => x.columnId == columnId);
      if (k.conditions.isEmpty) emptied.add(k.id);
    }
    t.checks.removeWhere((k) => emptied.contains(k.id));
    for (final g in t.triggers) {
      g.updateColumnIds.remove(columnId);
    }
    t.columns.removeWhere((c) => c.id == columnId);
    ctx.recalcAllPages();
  }
}
