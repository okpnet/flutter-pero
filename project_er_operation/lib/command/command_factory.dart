import '../model/model.dart';
import 'clipboard_commands.dart';
import 'column_commands.dart';
import 'command_base.dart';
import 'entity_commands.dart';
import 'model_commands.dart';
import 'relationship_commands.dart';

Map<String, Object?> _m(Object? v) => Map<String, Object?>.from(v as Map);
List<Map<String, Object?>>? _ml(Object? v) =>
    v == null ? null : [for (final e in v as List) _m(e)];

/// JSONからコマンドを復元する(キャッシュの再生。9.2)。未知の種別は [CommandException]。
ModelCommand commandFromJson(Map<String, Object?> json) {
  final type = json['type'];
  final a = _m(json['args']);
  switch (type) {
    case 'addTable':
      return AddTableCommand(
          diagramId: a['diagramId'] as int,
          x: (a['x'] as num).toDouble(),
          y: (a['y'] as num).toDouble());
    case 'addView':
      return AddViewCommand(
          diagramId: a['diagramId'] as int,
          x: (a['x'] as num).toDouble(),
          y: (a['y'] as num).toDouble(),
          entityMap: _m(a['entity']));
    case 'replaceEntity':
      return ReplaceEntityCommand(_m(a['entity']));
    case 'setLocked':
      return SetLockedCommand(List<int>.from(a['ids'] as List), a['locked'] as bool);
    case 'movePlacements':
      return MovePlacementsCommand(a['diagramId'] as int, {
        for (final e in _m(a['moves']).entries)
          int.parse(e.key): [for (final v in e.value as List) (v as num).toDouble()]
      });
    case 'setCollapsed':
      return SetCollapsedCommand(
          a['diagramId'] as int, a['entityId'] as int, a['collapsed'] as bool);
    case 'addPlacements':
      return AddPlacementsCommand(a['diagramId'] as int, [
        for (final it in a['items'] as List) [for (final v in it as List) (v as num).toDouble()]
      ]);
    case 'removePlacements':
      return RemovePlacementsCommand(
          a['diagramId'] as int, List<int>.from(a['entityIds'] as List));
    case 'deleteEntities':
      return DeleteEntitiesCommand(List<int>.from(a['ids'] as List));
    case 'addRelationship':
      return AddRelationshipCommand(
          tableAId: a['a'] as int,
          tableBId: a['b'] as int,
          parentId: a['parentId'] as int?,
          parentColumnId: a['parentColumnId'] as int?,
          childColumnId: a['childColumnId'] as int?);
    case 'removeRelationship':
      return RemoveRelationshipCommand(List<int>.from(a['ids'] as List));
    case 'updateRelationship':
      return UpdateRelationshipCommand(a['id'] as int, _m(a['patch']),
          link: a['link'] as bool? ?? false);
    case 'swapRelationship':
      return SwapRelationshipDirectionCommand(a['id'] as int);
    case 'addColumn':
      return AddColumnCommand(a['entityId'] as int);
    case 'removeColumn':
      return RemoveColumnCommand(a['entityId'] as int, a['columnId'] as int);
    case 'addDiagram':
      return AddDiagramCommand(
          pageSize: enumFromWire(PageSize.values, a['pageSize']) ?? PageSize.a3,
          orientation: enumFromWire(Orientation.values, a['orientation']) ?? Orientation.landscape);
    case 'renameDiagram':
      return RenameDiagramCommand(a['id'] as int, a['name'] as String);
    case 'removeDiagram':
      return RemoveDiagramCommand(a['id'] as int);
    case 'moveDiagram':
      return MoveDiagramCommand(a['id'] as int, a['newIndex'] as int);
    case 'updateDiagramPage':
      return UpdateDiagramPageCommand(
          a['id'] as int,
          enumFromWire(PageSize.values, a['pageSize']) ?? PageSize.a3,
          enumFromWire(Orientation.values, a['orientation']) ?? Orientation.landscape);
    case 'updateModelProperties':
      return UpdateModelPropertiesCommand(_m(a['patch']));
    case 'replaceShared':
      return ReplaceSharedResourcesCommand(
          types: _ml(a['types']),
          methods: _ml(a['methods']),
          patterns: _ml(a['patterns']),
          typeReplacements: {
            for (final e in _m(a['typeReplacements'] ?? {}).entries) e.key: e.value as String
          });
    case 'deleteType':
      return DeleteTypeCommand(a['typeId'] as String, a['replacementId'] as String?);
    case 'deleteMethod':
      return DeleteMethodCommand(a['methodId'] as int);
    case 'pasteEntities':
      return PasteEntitiesCommand(
          diagramId: a['diagramId'] as int,
          data: ClipboardData.fromJson(_m(a['data'])),
          dx: (a['dx'] as num).toDouble(),
          dy: (a['dy'] as num).toDouble(),
          pasteCount: a['pasteCount'] as int);
  }
  throw CommandException('未知のコマンド種別: $type');
}

/// 記録(`exec` / `undo` / `redo`)を順に再生する。
void replayJournal(CommandHistory history, Iterable<Map<String, Object?>> events) {
  for (final ev in events) {
    switch (ev['op']) {
      case 'exec':
        history.execute(commandFromJson(_m(ev['cmd'])), journal: false);
      case 'undo':
        history.undo(journal: false);
      case 'redo':
        history.redo(journal: false);
      default:
        throw CommandException('未知の記録: ${ev['op']}');
    }
  }
}
