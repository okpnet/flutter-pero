import '../model/model.dart';
import '../persistence/persistence.dart';
import 'command_base.dart';
import 'entity_commands.dart';

/// ダイアグラムの追加(3.2)。
class AddDiagramCommand extends ModelCommand {
  AddDiagramCommand({this.pageSize = PageSize.a3, this.orientation = Orientation.landscape});
  final PageSize pageSize;
  final Orientation orientation;
  int? createdId;

  @override
  String get type => 'addDiagram';
  @override
  Map<String, Object?> argsToJson() =>
      {'pageSize': pageSize.wire, 'orientation': orientation.wire};

  @override
  void apply(CommandContext ctx) {
    final m = ctx.model;
    final names = m.diagrams.map((d) => d.name).toSet();
    final n = m.smallestUnusedNumber((n) => names.contains('ダイアグラム$n'));
    final d = Diagram(
        id: m.allocateId(), name: 'ダイアグラム$n', pageSize: pageSize, orientation: orientation);
    m.diagrams.add(d);
    createdId = d.id;
  }
}

class RenameDiagramCommand extends ModelCommand {
  RenameDiagramCommand(this.id, this.name);
  final int id;
  final String name;

  @override
  String get type => 'renameDiagram';
  @override
  Map<String, Object?> argsToJson() => {'id': id, 'name': name};

  @override
  void apply(CommandContext ctx) {
    final m = ctx.model;
    final d = m.diagramById(id);
    if (d == null) throw CommandException('ダイアグラムが存在しません');
    if (name.trim().isEmpty) throw CommandException('名前を入力してください');
    if (m.diagrams.any((x) => x.id != id && x.name.toLowerCase() == name.toLowerCase())) {
      throw CommandException('同じ名前のダイアグラムが存在します');
    }
    d.name = name;
  }
}

/// ダイアグラムのスキーマの変更(5.2-1)。
class SetDiagramSchemaCommand extends ModelCommand {
  SetDiagramSchemaCommand(this.id, this.schema);
  final int id;
  final String schema;

  @override
  String get type => 'setDiagramSchema';
  @override
  Map<String, Object?> argsToJson() => {'id': id, 'schema': schema};

  @override
  void apply(CommandContext ctx) {
    final d = ctx.model.diagramById(id);
    if (d == null) throw CommandException('ダイアグラムが存在しません');
    d.schema = schema;
  }
}

/// ダイアグラムの削除。削除されるのは配置だけ(3.2-4)。最後の1つは削除できない。
class RemoveDiagramCommand extends ModelCommand {
  RemoveDiagramCommand(this.id);
  final int id;

  @override
  String get type => 'removeDiagram';
  @override
  Map<String, Object?> argsToJson() => {'id': id};

  @override
  void apply(CommandContext ctx) {
    final m = ctx.model;
    if (m.diagrams.length <= 1) throw CommandException('最後のダイアグラムは削除できません');
    m.diagrams.removeWhere((d) => d.id == id);
  }
}

/// ダイアグラムの並べ替え(ドラッグ)。
class MoveDiagramCommand extends ModelCommand {
  MoveDiagramCommand(this.id, this.newIndex);
  final int id;
  final int newIndex;

  @override
  String get type => 'moveDiagram';
  @override
  Map<String, Object?> argsToJson() => {'id': id, 'newIndex': newIndex};

  @override
  void apply(CommandContext ctx) {
    final list = ctx.model.diagrams;
    final i = list.indexWhere((d) => d.id == id);
    if (i < 0) return;
    final d = list.removeAt(i);
    list.insert(newIndex.clamp(0, list.length), d);
  }
}

/// 用紙サイズ・向きの変更(5.2-5)。座標は変えずにグリッドを再計算する。
class UpdateDiagramPageCommand extends ModelCommand {
  UpdateDiagramPageCommand(this.id, this.pageSize, this.orientation);
  final int id;
  final PageSize pageSize;
  final Orientation orientation;

  @override
  String get type => 'updateDiagramPage';
  @override
  Map<String, Object?> argsToJson() =>
      {'id': id, 'pageSize': pageSize.wire, 'orientation': orientation.wire};

  @override
  void apply(CommandContext ctx) {
    final d = ctx.model.diagramById(id);
    if (d == null) throw CommandException('ダイアグラムが存在しません');
    d.pageSize = pageSize;
    d.orientation = orientation;
    d.pageRows = 1;
    d.pageCols = 1;
    ctx.recalcPages(d);
  }
}

/// モデルのプロパティ(5.1)の変更。
class UpdateModelPropertiesCommand extends ModelCommand {
  UpdateModelPropertiesCommand(this.patch);

  /// outputFileName, outputFolder, targetDb, postPath, startQuery, endQuery, schema, includeSchema
  final Map<String, Object?> patch;

  @override
  String get type => 'updateModelProperties';
  @override
  Map<String, Object?> argsToJson() => {'patch': patch};

  @override
  void apply(CommandContext ctx) {
    final p = ctx.model.properties;
    String? s(String k) => patch[k] is String ? patch[k] as String : null;
    p.outputFileName = s('outputFileName') ?? p.outputFileName;
    p.schema = s('schema') ?? p.schema;
    if (patch['includeSchema'] is bool) p.includeSchema = patch['includeSchema'] as bool;
    p.outputFolder = s('outputFolder') ?? p.outputFolder;
    p.postPath = s('postPath') ?? p.postPath;
    p.startQuery = s('startQuery') ?? p.startQuery;
    p.endQuery = s('endQuery') ?? p.endQuery;
    p.targetDb = enumFromWire(DbKind.values, patch['targetDb']) ?? p.targetDb;
  }
}

/// 共有リソース(型、メソッド、共通列パターン)の一括置換(ダイアログのOK。9.1-3)。
class ReplaceSharedResourcesCommand extends ModelCommand {
  ReplaceSharedResourcesCommand({
    this.types,
    this.methods,
    this.patterns,
    this.typeReplacements = const {},
  });

  /// 削除する型の置換先(使用中の型を削除するとき。6.3-9)。
  final Map<String, String> typeReplacements;
  final List<Map<String, Object?>>? types;
  final List<Map<String, Object?>>? methods;
  final List<Map<String, Object?>>? patterns;

  factory ReplaceSharedResourcesCommand.of(
          {List<DataType>? types,
          List<MethodDef>? methods,
          List<CommonColumnPattern>? patterns,
          Map<String, String> typeReplacements = const {}}) =>
      ReplaceSharedResourcesCommand(
        types: types?.map(PeroEncoder.typeToMap).toList(),
        methods: methods?.map(PeroEncoder.methodToMap).toList(),
        patterns: patterns?.map(PeroEncoder.patternToMap).toList(),
        typeReplacements: typeReplacements,
      );

  @override
  String get type => 'replaceShared';
  @override
  Map<String, Object?> argsToJson() =>
      {'types': types, 'methods': methods, 'patterns': patterns, 'typeReplacements': typeReplacements};

  @override
  void apply(CommandContext ctx) {
    final m = ctx.model;
    if (types != null) {
      final next = [for (final x in types!) PeroDecoder.typeFromMap(x)!];
      final keep = next.map((t) => t.id).toSet();
      for (final old in m.types.where((t) => !keep.contains(t.id)).toList()) {
        DeleteTypeCommand.perform(m, old.id, typeReplacements[old.id]);
      }
      m.types = next;
    }
    if (methods != null) {
      final next = [for (final x in methods!) PeroDecoder.methodFromMap(x)!];
      final keep = next.map((t) => t.id).toSet();
      for (final old in m.methods.where((t) => !keep.contains(t.id)).toList()) {
        DeleteMethodCommand.perform(m, old.id);
      }
      m.methods = next;
      bumpNextId(m, next.map((x) => x.id));
    }
    if (patterns != null) {
      m.patterns = [for (final x in patterns!) PeroDecoder.patternFromMap(x)!];
      bumpNextId(m, [for (final p in m.patterns) ...[p.id, ...p.columns.map((c) => c.id)]]);
    }
    ctx.recalcAllPages();
  }
}

/// 型の削除(6.3-9)。使用中なら置換先へ付け替える。
class DeleteTypeCommand extends ModelCommand {
  DeleteTypeCommand(this.typeId, this.replacementId);
  final String typeId;
  final String? replacementId;

  @override
  String get type => 'deleteType';
  @override
  Map<String, Object?> argsToJson() => {'typeId': typeId, 'replacementId': replacementId};

  /// 型を使っている列とビューの戻り列の件数。
  static int usageCount(ErModel m, String typeId) {
    var n = 0;
    for (final t in m.tables) {
      n += t.columns.where((c) => c.typeId == typeId).length;
    }
    for (final p in m.patterns) {
      n += p.columns.where((c) => c.typeId == typeId).length;
    }
    for (final v in m.views) {
      n += v.function.columns.where((c) => c.typeId == typeId).length;
      n += v.sql.columns.where((c) => c.typeId == typeId).length;
    }
    for (final t in m.types) {
      n += t.fields.where((f) => f.typeId == typeId).length;
    }
    return n;
  }

  @override
  void apply(CommandContext ctx) => perform(ctx.model, typeId, replacementId);

  /// 型の削除の本体(共有リソースの一括置換からも使う)。
  static void perform(ErModel m, String typeId, String? replacementId) {
    final t = m.typeById(typeId);
    if (t == null) throw CommandException('型が存在しません');
    if (t.isStandard) throw CommandException('標準型は削除できません');
    final used = usageCount(m, typeId);
    if (used > 0) {
      if (replacementId == null || replacementId == typeId || m.typeById(replacementId) == null) {
        throw CommandException('置換先の型を選択してください');
      }
      if (m.tables.any((x) => x.locked && x.columns.any((c) => c.typeId == typeId))) {
        throw CommandException(lockedMessage);
      }
      for (final x in m.tables) {
        for (final c in x.columns) {
          if (c.typeId == typeId) c.typeId = replacementId;
        }
      }
      for (final p in m.patterns) {
        for (final c in p.columns) {
          if (c.typeId == typeId) c.typeId = replacementId;
        }
      }
      for (final v in m.views) {
        for (final c in [...v.function.columns, ...v.sql.columns]) {
          if (c.typeId == typeId) c.typeId = replacementId;
        }
      }
      for (final x in m.types) {
        for (final f in x.fields) {
          if (f.typeId == typeId) f.typeId = replacementId;
        }
      }
    }
    m.types.removeWhere((x) => x.id == typeId);
  }
}

/// メソッドの削除(8.1-9)。参照を解除してから削除する。
class DeleteMethodCommand extends ModelCommand {
  DeleteMethodCommand(this.methodId);
  final int methodId;

  @override
  String get type => 'deleteMethod';
  @override
  Map<String, Object?> argsToJson() => {'methodId': methodId};

  /// 参照元の説明の一覧(警告の表示用)。
  static List<String> references(ErModel m, int methodId) {
    final out = <String>[];
    for (final t in m.tables) {
      for (final c in t.columns) {
        if (c.defaultKind == DefaultKind.method && c.defaultMethodId == methodId) {
          out.add('${t.displayLabel}.${c.physicalName}(デフォルト)');
        }
      }
      for (final g in t.triggers) {
        if (g.source == TriggerSource.public && g.methodId == methodId) {
          out.add('${t.displayLabel}(トリガー ${m.triggerName(t, g)})');
        }
      }
    }
    for (final p in m.patterns) {
      for (final c in p.columns) {
        if (c.defaultMethodId == methodId && c.defaultKind == DefaultKind.method) {
          out.add('共通列 ${p.name}.${c.physicalName}(デフォルト)');
        }
      }
    }
    for (final v in m.views) {
      if (v.viewType == ViewType.function && v.function.methodId == methodId) {
        out.add('ビュー ${v.displayLabel}');
      }
    }
    return out;
  }

  @override
  void apply(CommandContext ctx) => perform(ctx.model, methodId);

  /// メソッドの削除の本体(参照を解除する。共有リソースの一括置換からも使う)。
  static void perform(ErModel m, int methodId) {
    for (final v in m.views) {
      if (v.function.methodId == methodId && v.viewType == ViewType.function) {
        throw CommandException('関数ビュー「${v.displayLabel}」が参照しています。先にビューを修正してください');
      }
    }
    for (final t in m.tables) {
      final uses = t.columns.any((c) => c.defaultMethodId == methodId) ||
          t.triggers.any((g) => g.methodId == methodId);
      if (uses && t.locked) throw CommandException(lockedMessage);
    }
    for (final t in m.tables) {
      for (final c in t.columns) {
        if (c.defaultMethodId == methodId) {
          c.defaultMethodId = null;
          if (c.defaultKind == DefaultKind.method) c.defaultKind = DefaultKind.none;
        }
      }
      t.triggers.removeWhere((g) => g.source == TriggerSource.public && g.methodId == methodId);
    }
    for (final p in m.patterns) {
      for (final c in p.columns) {
        if (c.defaultMethodId == methodId) {
          c.defaultMethodId = null;
          if (c.defaultKind == DefaultKind.method) c.defaultKind = DefaultKind.none;
        }
      }
    }
    m.methods.removeWhere((x) => x.id == methodId);
  }
}
