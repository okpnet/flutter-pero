import '../model/model.dart';
import '../persistence/persistence.dart';
import 'command_base.dart';

Diagram _diagramOrThrow(ErModel m, int id) {
  final d = m.diagramById(id);
  if (d == null) throw CommandException('ダイアグラム($id)が存在しません');
  return d;
}

const String lockedMessage = 'ロック中のオブジェクトが含まれます。ロックを解除してください';

/// テーブルの追加(4.2-2)。
class AddTableCommand extends ModelCommand {
  AddTableCommand({required this.diagramId, required this.x, required this.y});
  final int diagramId;
  final double x;
  final double y;

  /// 実行後に設定される、作成したテーブルのID。
  int? createdId;

  @override
  String get type => 'addTable';
  @override
  Map<String, Object?> argsToJson() => {'diagramId': diagramId, 'x': x, 'y': y};

  @override
  void apply(CommandContext ctx) {
    final m = ctx.model;
    final d = _diagramOrThrow(m, diagramId);
    final names = m.entities.map((e) => e.physicalName.toLowerCase()).toSet();
    final n = m.smallestUnusedNumber((n) => names.contains('table_$n'));
    final t = TableEntity(
      id: m.allocateId(),
      logicalName: 'テーブル$n',
      physicalName: 'table_$n',
      columns: [
        ColumnDef(
            id: m.allocateId(),
            logicalName: 'ID',
            physicalName: 'id',
            typeId: 'auto',
            pk: true,
            notNull: true),
      ],
    );
    m.entities.add(t);
    d.placements.add(Placement(entityId: t.id, x: x, y: y));
    createdId = t.id;
    ctx.recalcPages(d);
  }
}

/// ビューの追加(定義ダイアログのOK後)。[entityMap] のIDは無視して採番する。
class AddViewCommand extends ModelCommand {
  AddViewCommand(
      {required this.diagramId, required this.x, required this.y, required this.entityMap});
  final int diagramId;
  final double x;
  final double y;
  final Map<String, Object?> entityMap;
  int? createdId;

  @override
  String get type => 'addView';
  @override
  Map<String, Object?> argsToJson() =>
      {'diagramId': diagramId, 'x': x, 'y': y, 'entity': entityMap};

  @override
  void apply(CommandContext ctx) {
    final m = ctx.model;
    final d = _diagramOrThrow(m, diagramId);
    final e = PeroDecoder.entityFromMap({...entityMap, 'id': m.allocateId()});
    if (e is! ViewEntity) throw CommandException('ビューの定義が不正です');
    m.entities.add(e);
    d.placements.add(Placement(entityId: e.id, x: x, y: y));
    createdId = e.id;
    ctx.recalcPages(d);
  }
}

/// エンティティ全体の置換(プロパティペイン・ダイアログのOK。9.1-3)。
/// ロック中は変更できない(ロックの切替はSetLockedCommand)。
class ReplaceEntityCommand extends ModelCommand {
  ReplaceEntityCommand(this.entityMap);
  factory ReplaceEntityCommand.of(Entity e) =>
      ReplaceEntityCommand(PeroEncoder.entityToMap(e));
  final Map<String, Object?> entityMap;

  @override
  String get type => 'replaceEntity';
  @override
  Map<String, Object?> argsToJson() => {'entity': entityMap};

  @override
  void apply(CommandContext ctx) {
    final m = ctx.model;
    final ne = PeroDecoder.entityFromMap(entityMap);
    if (ne == null) throw CommandException('エンティティの定義が不正です');
    final i = m.entities.indexWhere((e) => e.id == ne.id);
    if (i < 0) throw CommandException('エンティティ(${ne.id})が存在しません');
    if (m.entities[i].locked) throw CommandException(lockedMessage);
    ne.locked = m.entities[i].locked;
    m.entities[i] = ne;
    // ダイアログ/プロパティ入力で採番したID(列・制約・トリガー)との衝突を避ける。
    if (ne is TableEntity) {
      bumpNextId(m, [
        ...ne.columns.map((c) => c.id),
        ...ne.indexes.map((c) => c.id),
        ...ne.uniques.map((c) => c.id),
        ...ne.triggers.map((c) => c.id),
      ]);
    }
    ctx.recalcAllPages();
  }
}

/// ロックの一括切替(5.3)。エンティティとリレーションシップのIDを混在できる。
class SetLockedCommand extends ModelCommand {
  SetLockedCommand(this.ids, this.locked);
  final List<int> ids;
  final bool locked;

  @override
  String get type => 'setLocked';
  @override
  Map<String, Object?> argsToJson() => {'ids': ids, 'locked': locked};

  @override
  void apply(CommandContext ctx) {
    for (final id in ids) {
      final e = ctx.model.entityById(id);
      if (e != null) {
        e.locked = locked;
        continue;
      }
      ctx.model.relationshipById(id)?.locked = locked;
    }
  }
}

/// ドラッグ移動、自動配置の結果の適用(複数同時を1コマンド。9.1-3)。
/// ロック中のエンティティは動かさない(5.3-5)。
class MovePlacementsCommand extends ModelCommand {
  MovePlacementsCommand(this.diagramId, this.moves);

  final int diagramId;

  /// entityId -> [x, y]
  final Map<int, List<double>> moves;

  @override
  String get type => 'movePlacements';
  @override
  Map<String, Object?> argsToJson() => {
        'diagramId': diagramId,
        'moves': {for (final e in moves.entries) '${e.key}': e.value}
      };

  @override
  void apply(CommandContext ctx) {
    final d = _diagramOrThrow(ctx.model, diagramId);
    for (final p in d.placements) {
      final mv = moves[p.entityId];
      if (mv == null) continue;
      if (ctx.model.entityById(p.entityId)?.locked ?? false) continue;
      p.x = mv[0];
      p.y = mv[1];
    }
    ctx.recalcPages(d);
  }
}

class SetCollapsedCommand extends ModelCommand {
  SetCollapsedCommand(this.diagramId, this.entityId, this.collapsed);
  final int diagramId;
  final int entityId;
  final bool collapsed;

  @override
  String get type => 'setCollapsed';
  @override
  Map<String, Object?> argsToJson() =>
      {'diagramId': diagramId, 'entityId': entityId, 'collapsed': collapsed};

  @override
  void apply(CommandContext ctx) {
    _diagramOrThrow(ctx.model, diagramId).placementOf(entityId)?.collapsed = collapsed;
  }
}

/// ダイアグラムへの配置の追加。既に配置済みのものは無視する。
class AddPlacementsCommand extends ModelCommand {
  AddPlacementsCommand(this.diagramId, this.items);
  final int diagramId;

  /// [entityId, x, y]
  final List<List<double>> items;

  @override
  String get type => 'addPlacements';
  @override
  Map<String, Object?> argsToJson() => {'diagramId': diagramId, 'items': items};

  @override
  void apply(CommandContext ctx) {
    final d = _diagramOrThrow(ctx.model, diagramId);
    for (final it in items) {
      final id = it[0].toInt();
      if (ctx.model.entityById(id) == null || d.placementOf(id) != null) continue;
      d.placements.add(Placement(entityId: id, x: it[1], y: it[2]));
    }
    ctx.recalcPages(d);
  }
}

/// 「このダイアグラムから外す」(4.2-4)。ロック中は不可(5.3-3)。
class RemovePlacementsCommand extends ModelCommand {
  RemovePlacementsCommand(this.diagramId, this.entityIds);
  final int diagramId;
  final List<int> entityIds;

  @override
  String get type => 'removePlacements';
  @override
  Map<String, Object?> argsToJson() => {'diagramId': diagramId, 'entityIds': entityIds};

  @override
  void apply(CommandContext ctx) {
    final d = _diagramOrThrow(ctx.model, diagramId);
    for (final id in entityIds) {
      if (ctx.model.entityById(id)?.locked ?? false) throw CommandException(lockedMessage);
    }
    d.placements.removeWhere((p) => entityIds.contains(p.entityId));
    ctx.recalcPages(d);
  }
}

/// 「モデルから削除」(6.1-12)。巻き込まれる削除を含めて1コマンド(9.1-3)。
class DeleteEntitiesCommand extends ModelCommand {
  DeleteEntitiesCommand(this.ids);
  final List<int> ids;

  @override
  String get type => 'deleteEntities';
  @override
  Map<String, Object?> argsToJson() => {'ids': ids};

  /// 削除できない理由の一覧。空なら削除できる。
  static List<String> blockers(ErModel m, List<int> ids) {
    final out = <String>[];
    for (final id in ids) {
      final e = m.entityById(id);
      if (e == null) continue;
      if (e.locked) out.add('「${e.displayLabel}」はロック中です。ロックを解除してください');
      for (final v in m.viewsUsingEntity(id)) {
        if (!ids.contains(v.id)) {
          out.add('「${e.displayLabel}」はビュー「${v.displayLabel}」のソースです。先にビューを修正または削除してください');
        }
      }
    }
    for (final r in m.relationships) {
      if (!(ids.contains(r.parentId) || ids.contains(r.childId))) continue;
      final other = ids.contains(r.parentId) ? r.childId : r.parentId;
      for (final eid in [other]) {
        if (m.entityById(eid)?.locked ?? false) {
          out.add('リレーションシップの相手「${m.entityById(eid)!.displayLabel}」がロック中です。ロックを解除してください');
        }
      }
      if (r.locked) out.add('ロック中のリレーションシップが含まれます。ロックを解除してください');
    }
    return out;
  }

  /// 巻き込まれるリレーションシップ。
  static List<Relationship> affectedRelationships(ErModel m, List<int> ids) => m.relationships
      .where((r) => ids.contains(r.parentId) || ids.contains(r.childId))
      .toList();

  @override
  void apply(CommandContext ctx) {
    final m = ctx.model;
    final problems = blockers(m, ids);
    if (problems.isNotEmpty) throw CommandException(problems.first);
    m.relationships.removeWhere((r) => ids.contains(r.parentId) || ids.contains(r.childId));
    m.entities.removeWhere((e) => ids.contains(e.id));
    for (final d in m.diagrams) {
      d.placements.removeWhere((p) => ids.contains(p.entityId));
      ctx.recalcPages(d);
    }
  }
}
