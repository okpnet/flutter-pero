import '../model/model.dart';
import 'command_base.dart';
import 'entity_commands.dart';

/// 親の鍵の列(主キー列。無ければ最初のユニーク制約の列)。7-4。
List<ColumnDef> parentKeyColumns(ErModel m, TableEntity parent) {
  final pk = parent.primaryKeyColumns;
  if (pk.isNotEmpty) return pk;
  for (final u in parent.uniques) {
    final cols = <ColumnDef>[];
    for (final id in u.columnIds) {
      final c = m.findExpandedColumn(parent, id)?.column;
      if (c != null) cols.add(c);
    }
    if (cols.isNotEmpty) return cols;
  }
  return [];
}

/// リレーションシップを追加できるか。できないときは理由(4.2-5)。
String? relationshipAddBlocker(ErModel m, TableEntity a, TableEntity b) {
  if (a.id == b.id) return '自己参照のリレーションシップは作成できません';
  if (a.locked || b.locked) return 'ロック中のテーブルがあります。ロックを解除してください';
  final parent = a.id < b.id ? a : b;
  if (parentKeyColumns(m, parent).isEmpty) {
    return '親になるテーブル「${parent.displayLabel}」に主キーまたはユニーク制約がありません';
  }
  return null;
}

/// 依存関係などの変更に伴う、子の外部キー列のPK/NotNullの連動計画(7-6-5)。
/// 戻り値は (pk, notNull)。nullは変更しない。
(bool?, bool?) linkagePlan(Relationship oldR, Relationship newR) {
  final oldDep = oldR.dependency, newDep = newR.dependency;
  if (!oldDep && newDep) {
    return newR.noReferentialRule ? (null, true) : (true, true);
  }
  if (oldDep && !newDep) return (false, false);
  if (oldDep && newDep) {
    if (!oldR.noReferentialRule && newR.noReferentialRule) return (false, null);
    if (oldR.noReferentialRule && !newR.noReferentialRule) return (true, null);
  }
  return (null, null);
}

String _uniquePhysicalName(ErModel m, TableEntity child, String base) {
  final used = m.expand(child).columns.map((c) => c.column.physicalName.toLowerCase()).toSet();
  if (!used.contains(base.toLowerCase())) return base;
  var n = 2;
  while (used.contains('${base}_$n'.toLowerCase())) {
    n++;
  }
  return '${base}_$n';
}

/// 親の鍵の列ごとに、子の外部キー列を決める(7-5)。必要なら子に列を作る。
/// [excludeRelationshipId] は、割当済みの判定から外すリレーションシップ(入替時)。
List<ColumnPair> assignForeignKeyColumns(
  ErModel m,
  TableEntity parent,
  TableEntity child, {
  required bool dependency,
  int? excludeRelationshipId,
  Map<int, int> preset = const {},
}) {
  final taken = <int>{
    for (final r in m.relationships)
      if (r.parentId == parent.id && r.childId == child.id && r.id != excludeRelationshipId)
        for (final p in r.columnPairs) p.childColumnId
  };
  final pairs = <ColumnPair>[];
  for (final p in parentKeyColumns(m, parent)) {
    final fixed = preset[p.id];
    if (fixed != null) {
      taken.add(fixed);
      pairs.add(ColumnPair(parentColumnId: p.id, childColumnId: fixed));
      continue;
    }
    final pn = p.physicalName.toLowerCase();
    ColumnDef? found;
    bool free(ColumnDef c) => !taken.contains(c.id);
    for (final c in child.columns) {
      if (free(c) && c.physicalName.toLowerCase() == pn) {
        found = c;
        break;
      }
    }
    if (found == null && pn.isNotEmpty) {
      for (final c in child.columns) {
        if (free(c) && c.physicalName.toLowerCase().contains(pn)) {
          found = c;
          break;
        }
      }
    }
    if (found == null) {
      final t = m.typeById(p.typeId);
      final isAuto = t?.category == TypeCategory.auto;
      final nc = ColumnDef(
        id: m.allocateId(),
        logicalName: '${parent.logicalName}_${p.logicalName}',
        physicalName: _uniquePhysicalName(m, child, '${parent.physicalName}_${p.physicalName}'),
        typeId: isAuto ? 'integer' : p.typeId,
        length: p.length,
        precision: p.precision,
        scale: p.scale,
        notNull: dependency,
      );
      if (dependency) {
        final lastPk = child.columns.lastIndexWhere((c) => c.pk);
        child.columns.insert(lastPk + 1, nc);
      } else {
        child.columns.add(nc);
      }
      found = nc;
    }
    taken.add(found.id);
    pairs.add(ColumnPair(parentColumnId: p.id, childColumnId: found.id));
  }
  return pairs;
}

/// 子の外部キー列へPK/NotNullを反映する(共通列は連動しない。7-6-7)。
void applyLinkage(TableEntity child, List<ColumnPair> pairs, bool? pk, bool? notNull) {
  for (final pair in pairs) {
    final c = child.columnById(pair.childColumnId);
    if (c == null) continue;
    if (pk != null) c.pk = pk;
    if (notNull != null) c.notNull = notNull;
    if (c.pk) c.notNull = true;
  }
}

/// リレーションシップの追加(外部キー列の自動作成を含めて1コマンド。9.1-3)。
class AddRelationshipCommand extends ModelCommand {
  AddRelationshipCommand({
    required this.tableAId,
    required this.tableBId,
    this.parentId,
    this.parentColumnId,
    this.childColumnId,
  });
  final int tableAId;
  final int tableBId;

  /// 親を明示するとき。省略時はIDの小さい方が親(7-3)。
  final int? parentId;

  /// 列のドラッグで作るときの、親の列と、それに対応させる子の列(7-5-3)。
  final int? parentColumnId;
  final int? childColumnId;
  int? createdId;

  @override
  String get type => 'addRelationship';
  @override
  Map<String, Object?> argsToJson() => {
        'a': tableAId,
        'b': tableBId,
        if (parentId != null) 'parentId': parentId,
        if (parentColumnId != null) 'parentColumnId': parentColumnId,
        if (childColumnId != null) 'childColumnId': childColumnId,
      };

  @override
  void apply(CommandContext ctx) {
    final m = ctx.model;
    final a = m.tableById(tableAId), b = m.tableById(tableBId);
    if (a == null || b == null) throw CommandException('テーブルが存在しません');
    final parent = parentId != null ? (parentId == a.id ? a : b) : (a.id < b.id ? a : b);
    final child = parent.id == a.id ? b : a;
    if (a.locked || b.locked) throw CommandException(lockedMessage);
    if (a.id == b.id) throw CommandException('自己参照のリレーションシップは作成できません');
    if (parentKeyColumns(m, parent).isEmpty) {
      throw CommandException('親になるテーブル「${parent.displayLabel}」に主キーまたはユニーク制約がありません');
    }
    const dependency = true;
    final r = Relationship(
        id: m.allocateId(), parentId: parent.id, childId: child.id, dependency: dependency);
    final preset = <int, int>{};
    if (parentColumnId != null && childColumnId != null) {
      if (!parentKeyColumns(m, parent).any((c) => c.id == parentColumnId)) {
        throw CommandException('親の列は主キーまたはユニーク制約の列を指定してください');
      }
      if (m.findExpandedColumn(child, childColumnId!) == null) {
        throw CommandException('子の列が存在しません');
      }
      preset[parentColumnId!] = childColumnId!;
    }
    r.columnPairs = assignForeignKeyColumns(m, parent, child, dependency: dependency, preset: preset);
    applyLinkage(child, r.columnPairs, true, true);
    m.relationships.add(r);
    createdId = r.id;
    ctx.recalcAllPages();
  }
}

class RemoveRelationshipCommand extends ModelCommand {
  RemoveRelationshipCommand(this.ids);
  final List<int> ids;

  @override
  String get type => 'removeRelationship';
  @override
  Map<String, Object?> argsToJson() => {'ids': ids};

  @override
  void apply(CommandContext ctx) {
    final m = ctx.model;
    for (final id in ids) {
      final r = m.relationshipById(id);
      if (r == null) continue;
      if (r.locked ||
          (m.entityById(r.parentId)?.locked ?? false) ||
          (m.entityById(r.childId)?.locked ?? false)) {
        throw CommandException(lockedMessage);
      }
    }
    m.relationships.removeWhere((r) => ids.contains(r.id));
  }
}

/// リレーションシップのプロパティ変更(7-4)。[link] が真のとき、子の外部キー列を連動する(7-6-5)。
class UpdateRelationshipCommand extends ModelCommand {
  UpdateRelationshipCommand(this.id, this.patch, {this.link = false});
  final int id;

  /// dependency, childMultiplicity, nameMode, name, onDelete, onUpdate, columnPairs
  final Map<String, Object?> patch;
  final bool link;

  @override
  String get type => 'updateRelationship';
  @override
  Map<String, Object?> argsToJson() => {'id': id, 'patch': patch, 'link': link};

  /// [patch] を適用した新しい状態(コピー)。UIが連動の要否を判断するときに使う。
  static Relationship applyPatch(Relationship r, Map<String, Object?> patch) {
    final n = r.copy();
    if (patch['dependency'] is bool) n.dependency = patch['dependency'] as bool;
    n.childMultiplicity =
        enumFromWire(Multiplicity.values, patch['childMultiplicity']) ?? n.childMultiplicity;
    n.nameMode = enumFromWire(NameMode.values, patch['nameMode']) ?? n.nameMode;
    if (patch['name'] is String) n.name = patch['name'] as String;
    n.onDelete = enumFromWire(RefAction.values, patch['onDelete']) ?? n.onDelete;
    n.onUpdate = enumFromWire(RefAction.values, patch['onUpdate']) ?? n.onUpdate;
    final cp = patch['columnPairs'];
    if (cp is List) {
      n.columnPairs = [
        for (final p in cp)
          ColumnPair(
              parentColumnId: (p as Map)['parentColumnId'] as int,
              childColumnId: p['childColumnId'] as int)
      ];
    }
    return n;
  }

  @override
  void apply(CommandContext ctx) {
    final m = ctx.model;
    final i = m.relationships.indexWhere((r) => r.id == id);
    if (i < 0) throw CommandException('リレーションシップが存在しません');
    final old = m.relationships[i];
    if (old.locked) throw CommandException(lockedMessage);
    final n = applyPatch(old, patch);
    final child = m.tableById(n.childId);
    if (child == null) throw CommandException('子テーブルが存在しません');
    if (link) {
      if (child.locked) throw CommandException(lockedMessage);
      final (pk, nn) = linkagePlan(old, n);
      applyLinkage(child, n.columnPairs, pk, nn);
    }
    m.relationships[i] = n;
  }
}

/// 方向の入替(7-3)。列対応の決定をやり直す。
class SwapRelationshipDirectionCommand extends ModelCommand {
  SwapRelationshipDirectionCommand(this.id);
  final int id;

  @override
  String get type => 'swapRelationship';
  @override
  Map<String, Object?> argsToJson() => {'id': id};

  @override
  void apply(CommandContext ctx) {
    final m = ctx.model;
    final r = m.relationshipById(id);
    if (r == null) throw CommandException('リレーションシップが存在しません');
    final np = m.tableById(r.childId), nc = m.tableById(r.parentId);
    if (np == null || nc == null) throw CommandException('テーブルが存在しません');
    if (r.locked || np.locked || nc.locked) throw CommandException(lockedMessage);
    if (parentKeyColumns(m, np).isEmpty) {
      throw CommandException('新しい親「${np.displayLabel}」に主キーまたはユニーク制約がありません');
    }
    r.parentId = np.id;
    r.childId = nc.id;
    r.columnPairs =
        assignForeignKeyColumns(m, np, nc, dependency: r.dependency, excludeRelationshipId: r.id);
    applyLinkage(nc, r.columnPairs, r.dependency && !r.noReferentialRule, r.dependency);
  }
}
