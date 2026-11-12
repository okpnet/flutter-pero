import 'data_type.dart';
import 'diagram.dart';
import 'entity.dart';
import 'enums.dart';
import 'shared_resources.dart';

/// モデルのプロパティ(5.1)。
class ModelProperties {
  ModelProperties({
    this.outputFileName = '',
    this.outputFolder = '',
    this.targetDb = DbKind.postgresql,
    this.postPath = '',
    this.startQuery = '',
    this.endQuery = '',
  });
  String outputFileName;
  String outputFolder;
  DbKind targetDb;
  String postPath;
  String startQuery;
  String endQuery;

  ModelProperties copy() => ModelProperties(
      outputFileName: outputFileName,
      outputFolder: outputFolder,
      targetDb: targetDb,
      postPath: postPath,
      startQuery: startQuery,
      endQuery: endQuery);
}

/// モデル(`.pero` ファイル1つに対応するデータ全体。ルート)。
class ErModel {
  ErModel({
    required this.id,
    this.nextId = 1,
    this.appVersion = '0.1.0',
    ModelProperties? properties,
    List<DataType>? types,
    List<MethodDef>? methods,
    List<CommonColumnPattern>? patterns,
    List<Entity>? entities,
    List<Relationship>? relationships,
    List<Diagram>? diagrams,
  })  : properties = properties ?? ModelProperties(),
        types = types ?? [],
        methods = methods ?? [],
        patterns = patterns ?? [],
        entities = entities ?? [],
        relationships = relationships ?? [],
        diagrams = diagrams ?? [];

  /// 空のモデルを作る(4.1-1)。[typeTemplate] は設定の型テーブル(省略時は標準型)。
  factory ErModel.empty({
    List<DataType>? typeTemplate,
    PageSize pageSize = PageSize.a3,
    Orientation orientation = Orientation.landscape,
    String postPath = '',
  }) {
    final m = ErModel(
      id: DateTime.now().millisecondsSinceEpoch % 2000000000,
      types: (typeTemplate ?? standardTypes()).map((t) => t.copy()).toList(),
      properties: ModelProperties(postPath: postPath),
    );
    m.diagrams.add(Diagram(
        id: m.allocateId(), name: 'ダイアグラム1', pageSize: pageSize, orientation: orientation));
    return m;
  }

  int id;
  int nextId;
  String appVersion;
  ModelProperties properties;
  List<DataType> types;
  List<MethodDef> methods;
  List<CommonColumnPattern> patterns;
  List<Entity> entities;
  List<Relationship> relationships;
  List<Diagram> diagrams;

  /// 未知のキー(9.4-7)。保存時に書き戻す。
  Map<String, Object?> unknownKeys = {};

  int allocateId() => nextId++;

  // ---- 検索 ----
  Entity? entityById(int id) {
    for (final e in entities) {
      if (e.id == id) return e;
    }
    return null;
  }

  TableEntity? tableById(int id) {
    final e = entityById(id);
    return e is TableEntity ? e : null;
  }

  Relationship? relationshipById(int id) {
    for (final r in relationships) {
      if (r.id == id) return r;
    }
    return null;
  }

  Diagram? diagramById(int id) {
    for (final d in diagrams) {
      if (d.id == id) return d;
    }
    return null;
  }

  DataType? typeById(String id) {
    for (final t in types) {
      if (t.id == id) return t;
    }
    return null;
  }

  MethodDef? methodById(int id) {
    for (final m in methods) {
      if (m.id == id) return m;
    }
    return null;
  }

  Iterable<TableEntity> get tables => entities.whereType<TableEntity>();
  Iterable<ViewEntity> get views => entities.whereType<ViewEntity>();

  // ---- 共通列の展開(8.2-3) ----
  ExpansionResult expand(TableEntity t) {
    final taken = {for (final c in t.columns) c.physicalName.toLowerCase()};
    final start = <ExpandedColumn>[];
    final end = <ExpandedColumn>[];
    final skipped = <(String, ColumnDef)>[];
    for (final p in patterns) {
      if (!p.appliesTo(t.physicalName)) continue;
      for (final c in p.columns) {
        final key = c.physicalName.toLowerCase();
        if (taken.contains(key)) {
          skipped.add((p.name, c));
          continue;
        }
        taken.add(key);
        (p.position == PatternPosition.start ? start : end)
            .add(ExpandedColumn(c, patternName: p.name));
      }
    }
    return ExpansionResult(
        [...start, ...t.columns.map(ExpandedColumn.new), ...end], skipped);
  }

  /// 実列または展開された共通列から列IDで探す。
  ExpandedColumn? findExpandedColumn(TableEntity t, int columnId) {
    for (final c in expand(t).columns) {
      if (c.column.id == columnId) return c;
    }
    return null;
  }

  /// 共通列パターンの列IDからパターン列を探す(展開の有無を問わない)。
  ColumnDef? patternColumnById(int columnId) {
    for (final p in patterns) {
      for (final c in p.columns) {
        if (c.id == columnId) return c;
      }
    }
    return null;
  }

  /// 列IDが指す列(実列、共通列パターンの列のいずれか)。
  ColumnDef? anyColumnById(int columnId) {
    for (final t in tables) {
      final c = t.columnById(columnId);
      if (c != null) return c;
    }
    return patternColumnById(columnId);
  }

  // ---- 名称(6.4, 6.5, 7-4) ----
  String indexName(TableEntity t, ConstraintDef c) {
    if (c.nameMode == NameMode.manual) return c.name;
    return '${t.physicalName}_idx${t.indexes.indexOf(c) + 1}';
  }

  String uniqueName(TableEntity t, ConstraintDef c) {
    if (c.nameMode == NameMode.manual) return c.name;
    return '${t.physicalName}_unq${t.uniques.indexOf(c) + 1}';
  }

  String triggerName(TableEntity t, TriggerDef g) {
    if (g.nameMode == NameMode.manual) return g.name;
    final n = t.triggers.indexOf(g) + 1;
    return '${t.physicalName}_trg${n.toString().padLeft(2, '0')}';
  }

  String primaryKeyName(TableEntity t) => '${t.physicalName}_pk';

  String foreignKeyName(Relationship r) {
    if (r.nameMode == NameMode.manual) return r.name;
    final child = tableById(r.childId);
    final sameChild = relationships.where((x) => x.childId == r.childId).toList()
      ..sort((a, b) => a.id.compareTo(b.id));
    final n = sameChild.indexOf(r) + 1;
    return '${child?.physicalName ?? ''}_fk$n';
  }

  // ---- 型表示 ----
  /// 列の型の表示名。例: `varchar(255)`。
  String typeLabel(ColumnDef c) {
    final t = typeById(c.typeId);
    if (t == null) return c.typeId;
    switch (t.paramKind) {
      case ParamKind.none:
        return t.id;
      case ParamKind.length:
        return '${t.id}(${c.length ?? t.defaultLength ?? ''})';
      case ParamKind.precisionScale:
        return '${t.id}(${c.precision ?? t.defaultPrecision ?? ''},${c.scale ?? t.defaultScale ?? ''})';
    }
  }

  // ---- 参照の調査 ----
  /// エンティティを参照しているビュー(ソース)。
  List<ViewEntity> viewsUsingEntity(int entityId) => views
      .where((v) =>
          v.viewType == ViewType.join && v.join.sources.any((s) => s.entityId == entityId))
      .toList();

  /// 列をビューが出力列または結合条件に使っているか。
  List<ViewEntity> viewsUsingColumn(int columnId) => views.where((v) {
        if (v.viewType != ViewType.join) return false;
        return v.join.columns.any((c) => c.columnId == columnId) ||
            v.join.sources.any((s) => s.on.any(
                (o) => o.leftColumnId == columnId || o.rightColumnId == columnId));
      }).toList();

  /// エンティティの端点になっているリレーションシップ。
  List<Relationship> relationshipsOf(int entityId) =>
      relationships.where((r) => r.parentId == entityId || r.childId == entityId).toList();

  /// 未使用の最小の正の整数Nを使った名前を返す(例: `テーブルN`)。
  int smallestUnusedNumber(bool Function(int n) used) {
    var n = 1;
    while (used(n)) {
      n++;
    }
    return n;
  }
}
