import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../canvas/canvas.dart';
import '../command/command.dart';
import 'file_dialogs.dart';
import '../common/common.dart';
import '../dialog/dialog.dart';
import '../generation/generation.dart';
import '../model/model.dart';
import '../persistence/persistence.dart';
import '../runner/runner.dart';
import '../session/session.dart';
import '../settings/settings.dart';

/// メニュー・ショートカット・右クリックメニューから呼ばれる操作(4)。
/// ダイアログを伴う操作をここに集約する。
class EditorActions implements CanvasHost {
  EditorActions({
    required this.session,
    required this.contextProvider,
    required this.canvasKey,
    required this.nameFocus,
    required this.settingsStore,
    this.dialogs = const FileDialogs(),
    required this.onSettingsApplied,
    required this.requestExit,
  });

  final EditorSession session;
  final BuildContext Function() contextProvider;
  final GlobalKey<DiagramCanvasState> canvasKey;
  final FocusNode nameFocus;
  final SettingsStore settingsStore;

  /// ファイル選択ダイアログ。
  final FileDialogs dialogs;
  final void Function(AppSettings) onSettingsApplied;
  final Future<void> Function() requestExit;

  BuildContext get _ctx => contextProvider();

  // ---- 未保存確認(4.1-8) ----

  /// 続行してよいなら true。
  Future<bool> confirmDiscard() async {
    if (!session.isDirty) return true;
    final choice = await showUnsavedDialog(_ctx);
    switch (choice) {
      case UnsavedChoice.cancel:
        return false;
      case UnsavedChoice.discard:
        return true;
      case UnsavedChoice.save:
        return saveOverwrite();
    }
  }

  // ---- ファイル(4.1) ----

  Future<void> newModel() async {
    if (!await confirmDiscard()) return;
    session.newModel();
  }

  Future<String> _documentsDir() async {
    try {
      return (await getApplicationDocumentsDirectory()).path;
    } on Object {
      return Platform.environment['USERPROFILE'] ?? Directory.current.path;
    }
  }

  Future<void> openFile() async {
    if (!await confirmDiscard()) return;
    final dir = session.settings.lastFolder.isNotEmpty ? session.settings.lastFolder : await _documentsDir();
    final path = await dialogs.pickOpen(title: Strings.fileOpen, extensions: ['pero'], initialDirectory: dir);
    if (path == null) return;
    await openPath(path, skipConfirm: true);
  }

  Future<void> openPath(String path, {bool skipConfirm = false}) async {
    if (!skipConfirm && !await confirmDiscard()) return;
    if (!File(path).existsSync()) {
      session.settings.recentFiles.remove(path);
      if (_ctx.mounted) {
        await showMessageDialog(_ctx, title: Strings.error, message: 'ファイルが存在しません:\n$path');
      }
      session.notify(null);
      return;
    }
    final r = await session.open(path);
    if (!_ctx.mounted) return;
    if (r.model == null) {
      await showMessageDialog(_ctx, title: Strings.error, message: r.error ?? 'ファイルを開けませんでした');
      return;
    }
    if (!r.repairs.isEmpty) {
      await showMessageDialog(_ctx,
          title: '整合性確認',
          message: 'ファイルの不整合を修復しました。元のファイルは .bak に退避しました。',
          detail: r.repairs.summary());
    }
  }

  /// 「ファイルに保存」。キャンセルは false。
  Future<bool> saveAs() async {
    final cur = session.filePath;
    final dir = cur != null
        ? cur.substring(0, cur.lastIndexOf(Platform.pathSeparator))
        : (session.settings.lastFolder.isNotEmpty ? session.settings.lastFolder : await _documentsDir());
    final name = cur != null ? cur.substring(cur.lastIndexOf(Platform.pathSeparator) + 1) : '${Strings.untitled}.pero';
    final SaveResult? r;
    try {
      r = await session.saveVia((bytes) => dialogs.saveBytes(
            title: Strings.fileSaveAs,
            fileName: name,
            bytes: bytes,
            extension: 'pero',
            initialDirectory: dir,
          ));
    } on FileSystemException catch (e) {
      if (_ctx.mounted) await showMessageDialog(_ctx, title: Strings.error, message: '書込みに失敗しました: ${e.message}');
      return false;
    }
    if (r == null) return false;
    return _afterSave(r);
  }

  /// 上書き保存。未保存の新規は「ファイルに保存」。
  Future<bool> saveOverwrite() async {
    final p = session.filePath;
    if (p == null) return saveAs();
    return _saveTo(p);
  }

  Future<bool> _saveTo(String path) async => _afterSave(await session.save(path));

  /// 保存結果の表示(エラー、修復の通知)。成功なら true。
  Future<bool> _afterSave(SaveResult r) async {
    if (!r.isOk) {
      if (_ctx.mounted) await showMessageDialog(_ctx, title: Strings.error, message: r.error!);
      return false;
    }
    if (!r.repairs.isEmpty && _ctx.mounted) {
      await showMessageDialog(_ctx,
          title: '整合性確認', message: '保存時に不整合を修復しました。', detail: r.repairs.summary());
    }
    return true;
  }

  Future<void> openSettings() async {
    await showSettingsDialog(_ctx, session.settings, onApply: (applied) {
      // 自動保存の項目は、設定画面の外で変わっている可能性があるため現在値を引き継ぐ。
      final cur = session.settings;
      applied
        ..rightPaneRatio = cur.rightPaneRatio
        ..propsRatio = cur.propsRatio
        ..windowX = cur.windowX
        ..windowY = cur.windowY
        ..windowWidth = cur.windowWidth
        ..windowHeight = cur.windowHeight
        ..windowMaximized = cur.windowMaximized
        ..lastFolder = cur.lastFolder
        ..recentFiles = cur.recentFiles;
      onSettingsApplied(applied);
      final msg = settingsStore.save(applied);
      session.notify(msg);
    });
  }

  // ---- 操作(4.2) ----

  void addTableAt(Offset p) => session.run(AddTableCommand(diagramId: session.diagram.id, x: p.dx, y: p.dy));

  @override
  void onAddTableAt(Offset modelPos) {
    final cmd = AddTableCommand(
        diagramId: session.diagram.id, x: _snap(modelPos.dx), y: _snap(modelPos.dy));
    if (session.run(cmd)) session.setSelection([cmd.createdId!]);
  }

  double _snap(double v) {
    final s = session.settings.gridSnap;
    return s <= 0 ? v : (v / s).round() * s;
  }

  @override
  void onAddViewAt(Offset modelPos, ViewType type) {
    if (type == ViewType.function) {
      addFunctionView(modelPos);
      return;
    }
    if (type == ViewType.sql) {
      addSqlView(modelPos);
      return;
    }
    addJoinView(modelPos);
  }

  void addViewAtCenter(ViewType type) =>
      onAddViewAt(canvasKey.currentState?.viewCenterModel ?? const Offset(40, 40), type);

  // ---- 共有リソースの管理(4.2-10) ----

  Future<void> manageMethods({MethodKind kind = MethodKind.function}) async {
    final r = await showMethodDialog(_ctx, session.model,
        nameFormat: session.settings.nameFormat, initialKind: kind);
    if (r != null) session.run(ReplaceSharedResourcesCommand.of(methods: r));
  }

  Future<void> managePatterns() async {
    final r = await showPatternDialog(_ctx, session.model, nameFormat: session.settings.nameFormat);
    if (r != null) session.run(ReplaceSharedResourcesCommand.of(patterns: r));
  }

  Future<void> manageTypes() async {
    final r = await showTypeManagerDialog(_ctx, session.model);
    if (r != null) {
      session.run(ReplaceSharedResourcesCommand.of(types: r.$1, typeReplacements: r.$2));
    }
  }

  // ---- 関数ビュー(6.6-8) ----

  Future<void> addFunctionView(Offset modelPos) async {
    final v = await showFunctionViewDialog(_ctx, session.model,
        nameFormat: session.settings.nameFormat, onManageMethods: manageMethods);
    if (v == null) return;
    final cmd = AddViewCommand(
        diagramId: session.diagram.id,
        x: _snap(modelPos.dx),
        y: _snap(modelPos.dy),
        entityMap: PeroEncoder.entityToMap(v));
    if (session.run(cmd)) session.setSelection([cmd.createdId!]);
  }

  Future<void> addSqlView(Offset modelPos) async {
    final v = await showSqlViewDialog(_ctx, session.model, nameFormat: session.settings.nameFormat);
    if (v == null) return;
    final cmd = AddViewCommand(
        diagramId: session.diagram.id,
        x: _snap(modelPos.dx),
        y: _snap(modelPos.dy),
        entityMap: PeroEncoder.entityToMap(v));
    if (session.run(cmd)) session.setSelection([cmd.createdId!]);
  }

  Future<void> addJoinView(Offset modelPos) async {
    if (session.model.tables.isEmpty) {
      await showMessageDialog(_ctx, title: 'ビューの追加', message: 'ソースにするテーブルがありません。先にテーブルを追加してください。');
      return;
    }
    final v = await showJoinViewDialog(_ctx, session.model, nameFormat: session.settings.nameFormat);
    if (v == null) return;
    final cmd = AddViewCommand(
        diagramId: session.diagram.id,
        x: _snap(modelPos.dx),
        y: _snap(modelPos.dy),
        entityMap: PeroEncoder.entityToMap(v));
    if (session.run(cmd)) session.setSelection([cmd.createdId!]);
  }

  Future<void> editView(int id) async {
    final e = session.model.entityById(id);
    if (e is! ViewEntity) return;
    if (e.viewType == ViewType.join) {
      final v = await showJoinViewDialog(_ctx, session.model, nameFormat: session.settings.nameFormat, initial: e);
      if (v != null) session.run(ReplaceEntityCommand.of(v));
      return;
    }
    if (e.viewType == ViewType.sql) {
      final v = await showSqlViewDialog(_ctx, session.model,
          nameFormat: session.settings.nameFormat, initial: e);
      if (v != null) session.run(ReplaceEntityCommand.of(v));
      return;
    }
    final v = await showFunctionViewDialog(_ctx, session.model,
        nameFormat: session.settings.nameFormat, initial: e, onManageMethods: manageMethods);
    if (v != null) session.run(ReplaceEntityCommand.of(v));
  }

  @override
  void onFocusEntityName(int entityId) {
    session.setSelection([entityId]);
    WidgetsBinding.instance.addPostFrameCallback((_) => nameFocus.requestFocus());
  }

  /// 列のドラッグ&ドロップでリレーションシップを作る。ドラッグ元が親、ドロップ先が子。
  @override
  void onConnectColumns(int sourceEntityId, int sourceColumnId, int targetEntityId, int? targetColumnId) {
    final m = session.model;
    final parent = m.tableById(sourceEntityId), child = m.tableById(targetEntityId);
    if (parent == null || child == null) {
      session.notify('リレーションシップはテーブル同士でのみ作成できます');
      return;
    }
    final cmd = AddRelationshipCommand(
      tableAId: parent.id,
      tableBId: child.id,
      parentId: parent.id,
      parentColumnId: sourceColumnId,
      childColumnId: targetColumnId,
    );
    if (session.run(cmd)) session.setSelection([cmd.createdId!]);
  }

  void addTableAtCenter() {
    final c = canvasKey.currentState?.viewCenterModel ?? const Offset(40, 40);
    onAddTableAt(c);
  }

  Set<int> get _selectedEntityIds =>
      session.selection.where((id) => session.model.entityById(id) != null).toSet();

  bool get canRemoveFromDiagram {
    final ids = _selectedEntityIds;
    return ids.isNotEmpty && ids.every((id) => !(session.model.entityById(id)!.locked));
  }

  void removeFromDiagram() {
    final sel = session.selection.toList();
    if (sel.any((id) => session.model.relationshipById(id) != null) && _selectedEntityIds.isEmpty) {
      deleteFromModel(); // リレーションシップの Delete は削除(4.2-4-3)
      return;
    }
    if (!canRemoveFromDiagram) return;
    session.run(RemovePlacementsCommand(session.diagram.id, _selectedEntityIds.toList()));
  }

  Future<void> deleteFromModel() async {
    final m = session.model;
    final rels = session.selection.where((id) => m.relationshipById(id) != null).toList();
    final ents = _selectedEntityIds.toList();
    if (ents.isEmpty && rels.isNotEmpty) {
      session.run(RemoveRelationshipCommand(rels));
      return;
    }
    if (ents.isEmpty) return;
    final problems = DeleteEntitiesCommand.blockers(m, ents);
    if (problems.isNotEmpty) {
      await showMessageDialog(_ctx, title: '削除できません', message: problems.join('\n'));
      return;
    }
    final affected = DeleteEntitiesCommand.affectedRelationships(m, ents);
    final ok = await showConfirmDialog(
      _ctx,
      title: '${Strings.opDeleteFromModel}の確認',
      message: '次のエンティティをモデルから削除します。\n'
          '${ents.map((id) => '・${m.entityById(id)!.displayLabel}').join('\n')}'
          '${affected.isEmpty ? '' : '\n\n巻き込まれるリレーションシップ:\n${affected.map((r) => '・${m.foreignKeyName(r)}').join('\n')}'}',
    );
    if (ok) session.run(DeleteEntitiesCommand(ents));
  }

  /// テーブルがちょうど2つ選択されているときの追加の可否(4.2-5)。
  String? addRelationshipBlocker() {
    final tables = _selectedEntityIds.map(session.model.tableById).whereType<TableEntity>().toList();
    final n = _selectedEntityIds.length;
    if ((n != 1 && n != 2) || tables.length != n) {
      return '追加するにはテーブルを1つ(自己参照)または2つ選択してください';
    }
    return relationshipAddBlocker(session.model, tables[0], tables.last);
  }

  bool get canAddRelationship => addRelationshipBlocker() == null;

  void addRelationship() {
    final b = addRelationshipBlocker();
    if (b != null) {
      session.notify(b);
      return;
    }
    final ids = _selectedEntityIds.toList();
    final cmd = AddRelationshipCommand(tableAId: ids.first, tableBId: ids.last);
    if (session.run(cmd)) session.setSelection([cmd.createdId!]);
  }

  bool get canRemoveRelationship {
    final m = session.model;
    final sel = session.selection.where((id) => m.relationshipById(id) != null).toList();
    if (sel.isEmpty) return false;
    return sel.every((id) {
      final r = m.relationshipById(id)!;
      return !r.locked &&
          !(m.entityById(r.parentId)?.locked ?? false) &&
          !(m.entityById(r.childId)?.locked ?? false);
    });
  }

  void removeRelationship() {
    final ids = session.selection.where((id) => session.model.relationshipById(id) != null).toList();
    if (ids.isNotEmpty) session.run(RemoveRelationshipCommand(ids));
  }

  void selectAll() => session.setSelection([
        for (final p in session.diagram.placements) p.entityId,
        for (final r in session.model.relationships)
          if (session.diagram.placementOf(r.parentId) != null || session.diagram.placementOf(r.childId) != null) r.id,
      ]);

  void autoLayout() {
    try {
      final sel = _selectedEntityIds;
      final moves = computeAutoLayout(session.model, session.diagram, session.layouter,
          selected: sel, spacing: session.settings.alignSpace);
      if (moves.isEmpty) {
        session.notify(Strings.autoLayoutNothing);
        return;
      }
      if (!session.run(MovePlacementsCommand(session.diagram.id, moves))) return;
      // 配置し直した結果が見えるように、配置した範囲の左上へスクロールする(元の位置のままだと変化が見えない)。
      final minX = moves.values.map((v) => v[0]).reduce(math.min);
      final minY = moves.values.map((v) => v[1]).reduce(math.min);
      session.setView(scrollX: math.max(0, minX - 40), scrollY: math.max(0, minY - 40));
      session.notify(Strings.autoLayoutDone(moves.length));
    } on Object catch (e, st) {
      session.logger.error('自動配置に失敗', e, st);
      session.notify('${Strings.autoLayoutFailed}: $e');
    }
  }

  void toggleLockSelection() {
    final ids = session.selection.toList();
    if (ids.isEmpty) return;
    bool locked(int id) =>
        session.model.entityById(id)?.locked ?? session.model.relationshipById(id)?.locked ?? false;
    session.run(SetLockedCommand(ids, !ids.every(locked)));
  }

  // ---- ダイアグラム(3.2) ----

  void addDiagram() {
    final cmd = AddDiagramCommand(pageSize: session.settings.paperSize, orientation: session.settings.orientation);
    if (session.run(cmd)) session.currentDiagramId = cmd.createdId!;
  }

  Future<void> renameDiagram(int id) async {
    final d = session.model.diagramById(id);
    if (d == null) return;
    final v = await showTextPrompt(_ctx, title: Strings.opRenameDiagram, initial: d.name, validator: (v) {
      if (v.trim().isEmpty) return '名前を入力してください';
      if (session.model.diagrams.any((x) => x.id != id && x.name.toLowerCase() == v.toLowerCase())) {
        return '同じ名前のダイアグラムが存在します';
      }
      return null;
    });
    if (v != null) session.run(RenameDiagramCommand(id, v));
  }

  Future<void> deleteDiagram(int id) async {
    if (session.model.diagrams.length <= 1) {
      await showMessageDialog(_ctx, title: Strings.error, message: '最後のダイアグラムは削除できません');
      return;
    }
    final d = session.model.diagramById(id);
    final ok = await showConfirmDialog(_ctx,
        title: Strings.opDeleteDiagram,
        message: 'ダイアグラム「${d?.name}」を削除します。削除されるのは配置だけで、エンティティはモデルに残ります。');
    if (ok) session.run(RemoveDiagramCommand(id));
  }

  // ---- 右クリックメニュー(4.4) ----

  @override
  Future<void> onContextMenu(Offset globalPos, Offset modelPos, int? hitId) async {
    final m = session.model;
    final overlay = Overlay.of(_ctx).context.findRenderObject() as RenderBox;
    final entries = <PopupMenuEntry<String>>[];
    PopupMenuItem<String> item(String v, String label, {bool enabled = true}) =>
        PopupMenuItem(value: v, enabled: enabled, height: 32, child: Text(label));

    final isRel = hitId != null && m.relationshipById(hitId) != null;
    final isEntity = hitId != null && m.entityById(hitId) != null;
    final multi = session.selection.length > 1;
    if (hitId == null) {
      entries.addAll([
        item('addTable', Strings.opAddTable),
        item('addJoin', Strings.opAddJoinView),
        item('addFunc', Strings.opAddFunctionView),
        item('addSql', Strings.opAddSqlView),
        if (session.clipboard != null) item('paste', Strings.opPaste),
        item('selectAll', Strings.opSelectAll),
        item('autoLayout', Strings.opAutoLayout),
      ]);
    } else if (isRel && !multi) {
      entries.addAll([
        item('removeRel', Strings.opRemoveRelationship, enabled: canRemoveRelationship),
        item('toggleLock', m.relationshipById(hitId)!.locked ? Strings.opUnlock : Strings.opLock),
      ]);
    } else if (isEntity && !multi) {
      entries.addAll([
        item('editProp', Strings.opEditProperty),
        item('remove', Strings.opRemoveFromDiagram, enabled: canRemoveFromDiagram),
        item('delete', Strings.opDeleteFromModel, enabled: canRemoveFromDiagram),
        const PopupMenuDivider(),
        for (final d in m.diagrams)
          CheckedPopupMenuItem(
            value: 'diag:${d.id}',
            checked: d.placementOf(hitId) != null,
            height: 32,
            child: Text(d.name),
          ),
        const PopupMenuDivider(),
        if (canAddRelationship) item('addRel', Strings.opAddRelationship),
        item('copy', Strings.opCopy),
        item('dup', Strings.opDuplicate),
        item('toggleLock', m.entityById(hitId)!.locked ? Strings.opUnlock : Strings.opLock),
      ]);
    } else {
      entries.addAll([
        item('remove', Strings.opRemoveFromDiagram, enabled: canRemoveFromDiagram),
        item('delete', Strings.opDeleteFromModel, enabled: canRemoveFromDiagram),
        if (canAddRelationship) item('addRel', Strings.opAddRelationship),
        item('copy', Strings.opCopy),
        item('dup', Strings.opDuplicate),
        item('toggleLock', Strings.opLock),
      ]);
    }
    final pos = RelativeRect.fromRect(globalPos & const Size(1, 1), Offset.zero & overlay.size);
    final v = await showMenu<String>(context: _ctx, position: pos, items: entries);
    if (v == null) return;
    switch (v) {
      case 'addTable':
        onAddTableAt(modelPos);
      case 'addJoin':
        onAddViewAt(modelPos, ViewType.join);
      case 'addFunc':
        onAddViewAt(modelPos, ViewType.function);
      case 'addSql':
        onAddViewAt(modelPos, ViewType.sql);
      case 'paste':
        session.paste();
      case 'selectAll':
        selectAll();
      case 'autoLayout':
        autoLayout();
      case 'removeRel':
        removeRelationship();
      case 'toggleLock':
        toggleLockSelection();
      case 'editProp':
        onFocusEntityName(hitId!);
      case 'remove':
        removeFromDiagram();
      case 'delete':
        await deleteFromModel();
      case 'addRel':
        addRelationship();
      case 'copy':
        session.copySelection();
      case 'dup':
        session.duplicateSelection();
      default:
        if (v.startsWith('diag:')) toggleEntityInDiagram(hitId!, int.parse(v.substring(5)));
    }
  }

  void toggleEntityInDiagram(int entityId, int diagramId) {
    final d = session.model.diagramById(diagramId);
    if (d == null) return;
    if (d.placementOf(entityId) != null) {
      session.run(RemovePlacementsCommand(diagramId, [entityId]));
    } else {
      final cur = session.diagram.placementOf(entityId);
      session.run(AddPlacementsCommand(diagramId, [
        [entityId.toDouble(), cur?.x ?? 40, cur?.y ?? 40]
      ]));
    }
  }

  // ---- RUN(4.3) ----

  Future<void> generate() async {
    final ctx = _ctx;
    final logger = session.logger;
    // ポストファイルの確認(9.6-1-2)。パスが空のときだけ、ファイルを選ばせる。
    var postPath = session.model.properties.postPath;
    if (postPath.isEmpty) {
      final folder = session.postFolderPath();
      final picked = await dialogs.pickOpen(
        title: 'ポストファイルを選択',
        extensions: ['post'],
        initialDirectory: Directory(folder).existsSync() ? folder : null,
      );
      if (picked == null) return;
      postPath = picked;
      session.run(UpdateModelPropertiesCommand({'postPath': postPath}));
    }
    // 指定されたポストファイルを、生成の間ロックする(存在しないときは処理を止める)。
    final LockedPostFile locked;
    try {
      locked = await LockedPostFile.acquire(postPath);
    } on PostFileException catch (e) {
      logger.error('ポストファイルを開けません: $postPath / ${e.message}');
      if (ctx.mounted) await showMessageDialog(ctx, title: Strings.error, message: e.message);
      return;
    }
    try {
      await _generateWith(locked.text, postPath);
    } finally {
      await locked.release();
    }
  }

  Future<void> _generateWith(String script, String postPath) async {
    final ctx = _ctx;
    final logger = session.logger;
    final meta = parsePostMeta(script);
    final verr = checkPostApiVersion(meta);
    if (verr != null) {
      if (ctx.mounted) await showMessageDialog(ctx, title: Strings.error, message: verr);
      return;
    }
    // どのデータベースを適用するかは、ポストファイルのメタ情報で決める。
    final fileName = postPath.substring(postPath.lastIndexOf(Platform.pathSeparator) + 1);
    final kind = PostFileInfo(path: postPath, fileName: fileName, meta: meta).kindOf(session.settings.postKinds);
    if (kind == null) {
      logger.error('ポストファイルの対象DB(${meta!.targetDb})は未対応です: $postPath');
      if (ctx.mounted) {
        await showMessageDialog(ctx,
            title: Strings.error,
            message: 'ポストファイルの対象DB(${meta.targetDb})は、アプリが扱うデータベースの種類ではありません。\n'
                '設定の「ポストファイル > 種類(kind)の関連付け」で、既存の種類(${DbKind.values.map((k) => k.wire).join(' / ')})に関連付けてください。');
      }
      return;
    }
    if (kind != session.model.properties.targetDb) {
      final before = session.model.properties.targetDb.wire;
      session.run(UpdateModelPropertiesCommand({'targetDb': kind.wire}));
      session.notify('対象のデータベースをポストファイルに合わせて変更しました($before → ${kind.wire})');
      logger.info('対象のデータベースをポストファイルに合わせて変更: $before → ${kind.wire}');
    }
    final model = session.model;
    // 生成前検証 → 生成
    final GenerationOutcome out;
    try {
      out = await GenerationService(JsPostRunner()).generate(
        model,
        script,
        timeout: Duration(seconds: session.settings.postTimeoutSeconds),
        nameFormat: session.settings.nameFormat,
        pkNaming: session.settings.pkNaming,
        dropBeforeCreate: session.settings.dropBeforeCreate,
        onLog: (m) => logger.info('[post] $m'),
      );
    } on PostException catch (e) {
      logger.error('ポストファイルの実行に失敗: ${e.message}\n${e.stack ?? ''}');
      if (ctx.mounted) {
        await showMessageDialog(ctx, title: Strings.error, message: e.message, detail: e.stack);
      }
      return;
    }
    if (!out.isOk) {
      if (ctx.mounted) await showValidationErrors(ctx, out.errors, out.warnings);
      return;
    }
    final path = resolveOutputPath(
      model: model,
      peroFilePath: session.filePath,
      documentsDir: await _documentsDir(),
      extension: session.settings.generatedExtension,
    );
    if (File(path).existsSync() && ctx.mounted) {
      final ok = await showConfirmDialog(ctx, title: '上書きの確認', message: '既存のファイルを上書きしますか?\n$path');
      if (!ok) return;
    }
    try {
      Directory(File(path).parent.path).createSync(recursive: true);
      await writeGeneratedFile(path, out.text!, crlf: session.settings.crlf);
    } on FileSystemException catch (e, st) {
      logger.error('生成ファイルの書込みに失敗: $path', e, st);
      if (ctx.mounted) await showMessageDialog(ctx, title: Strings.error, message: '書込みに失敗しました: ${e.message}');
      return;
    }
    logger.info('生成しました: $path (警告${out.warnings.length}件)');
    if (ctx.mounted) await showGenerationResult(ctx, path: path, warnings: out.warnings);
  }

  Future<void> exportJson() async {
    final ctx = _ctx;
    final model = session.model;
    final v = ModelValidator(model,
            nameFormat: session.settings.nameFormat, pkNaming: session.settings.pkNaming)
        .validate();
    if (v.hasErrors) {
      await showValidationErrors(ctx, v.errors, v.warnings);
      return;
    }
    final dir = await _outputDir();
    final base = model.properties.outputFileName.isNotEmpty ? model.properties.outputFileName : Strings.untitled;
    try {
      final path = await dialogs.saveBytes(
        title: Strings.runJson,
        fileName: '$base.json',
        bytes: Uint8List.fromList(utf8.encode(GenerationJsonBuilder(model,
                pkNaming: session.settings.pkNaming,
                dropBeforeCreate: session.settings.dropBeforeCreate)
            .buildText(indent: true))),
        extension: 'json',
        initialDirectory: dir,
      );
      if (path != null) session.notify('JSONを出力しました: $path');
    } on FileSystemException catch (e) {
      if (ctx.mounted) await showMessageDialog(ctx, title: Strings.error, message: '書込みに失敗しました: ${e.message}');
    }
  }

  /// 保存ダイアログの既定のフォルダ(開いているファイルのフォルダ、無ければドキュメント)。
  Future<String> _outputDir() async {
    final cur = session.filePath;
    return cur != null ? cur.substring(0, cur.lastIndexOf(Platform.pathSeparator)) : await _documentsDir();
  }

  Future<void> exportImage() async {
    final ctx = _ctx;
    final opt = await showImageExportDialog(ctx, session.settings.dpi);
    if (opt == null || !ctx.mounted) return;
    final brightness = Theme.of(ctx).brightness;
    final result = await renderDiagramPng(
      model: session.model,
      diagram: session.diagram,
      layouter: session.layouter,
      colors: CanvasColors.of(brightness),
      dpi: opt.dpi,
      perPage: opt.perPage,
      fontFamily: session.settings.fontFamily.isEmpty ? null : session.settings.fontFamily,
    );
    final dir = await _outputDir();
    final name = session.diagram.name;
    try {
      if (opt.pdf) {
        // PDF: 1ページ=PDFの1ページ(用紙ページごと)、または全体を1ページ(9.8-2)
        final bytes = await buildPdf(result.pages, title: name);
        final path = await dialogs.saveBytes(
            title: Strings.runImage, fileName: '$name.pdf', bytes: bytes, extension: 'pdf', initialDirectory: dir);
        if (path == null) return;
      } else if (result.pages.length == 1) {
        final path = await dialogs.saveBytes(
            title: Strings.runImage,
            fileName: result.pages.single.name,
            bytes: result.pages.single.png,
            extension: 'png',
            initialDirectory: dir);
        if (path == null) return;
      } else {
        final folder = await dialogs.pickFolder(title: '出力先のフォルダ', initialDirectory: dir);
        if (folder == null) return;
        for (final p in result.pages) {
          await File('$folder${Platform.pathSeparator}${p.name}').writeAsBytes(p.png);
        }
      }
      session.notify(result.dpiReduced
          ? '1辺が16000pxを超えるため、解像度を${result.effectiveDpi}dpiに下げて出力しました'
          : '${opt.pdf ? 'PDF' : '画像'}を出力しました');
    } on FileSystemException catch (e) {
      if (ctx.mounted) await showMessageDialog(ctx, title: Strings.error, message: '書込みに失敗しました: ${e.message}');
    }
  }

  // ---- 終了(4.1-7) ----

  Future<void> exit() async {
    if (!await confirmDiscard()) return;
    await requestExit();
  }
}
