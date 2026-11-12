import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../canvas/canvas.dart';
import '../command/command.dart';
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
    required this.onSettingsApplied,
    required this.requestExit,
  });

  final EditorSession session;
  final BuildContext Function() contextProvider;
  final GlobalKey<DiagramCanvasState> canvasKey;
  final FocusNode nameFocus;
  final SettingsStore settingsStore;
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
    final r = await FilePicker.platform.pickFiles(
      dialogTitle: Strings.fileOpen,
      type: FileType.custom,
      allowedExtensions: ['pero'],
      initialDirectory: dir,
    );
    final path = r?.files.single.path;
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
    final path = await FilePicker.platform.saveFile(
      dialogTitle: Strings.fileSaveAs,
      fileName: name,
      initialDirectory: dir,
      type: FileType.custom,
      allowedExtensions: ['pero'],
    );
    if (path == null) return false;
    return _saveTo(path.toLowerCase().endsWith('.pero') ? path : '$path.pero');
  }

  /// 上書き保存。未保存の新規は「ファイルに保存」。
  Future<bool> saveOverwrite() async {
    final p = session.filePath;
    if (p == null) return saveAs();
    return _saveTo(p);
  }

  Future<bool> _saveTo(String path) async {
    final r = await session.save(path);
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
    showMessageDialog(_ctx, title: 'ビューの追加', message: '結合ビューの定義ダイアログは今後のバージョンで対応します。');
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

  Future<void> editFunctionView(int id) async {
    final e = session.model.entityById(id);
    if (e is! ViewEntity || e.viewType != ViewType.function) return;
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
    if (_selectedEntityIds.length != 2 || tables.length != 2) return '追加するにはテーブルを2つ選択してください';
    return relationshipAddBlocker(session.model, tables[0], tables[1]);
  }

  bool get canAddRelationship => addRelationshipBlocker() == null;

  void addRelationship() {
    final b = addRelationshipBlocker();
    if (b != null) {
      session.notify(b);
      return;
    }
    final ids = _selectedEntityIds.toList();
    final cmd = AddRelationshipCommand(tableAId: ids[0], tableBId: ids[1]);
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
    final sel = _selectedEntityIds;
    final moves = computeAutoLayout(session.model, session.diagram, session.layouter,
        selected: sel, spacing: session.settings.alignSpace);
    if (moves.isEmpty) return;
    session.run(MovePlacementsCommand(session.diagram.id, moves));
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
    final model = session.model;
    final logger = session.logger;
    // ポストファイルの確認(9.6-1-2)
    var postPath = model.properties.postPath;
    if (postPath.isEmpty || !File(postPath).existsSync()) {
      final folder = session.settings.postFolder.isNotEmpty
          ? session.settings.postFolder
          : '${File(Platform.resolvedExecutable).parent.path}${Platform.pathSeparator}post';
      final r = await FilePicker.platform.pickFiles(
        dialogTitle: 'ポストファイルを選択',
        type: FileType.custom,
        allowedExtensions: ['post'],
        initialDirectory: Directory(folder).existsSync() ? folder : null,
      );
      final picked = r?.files.single.path;
      if (picked == null) return;
      postPath = picked;
      session.run(UpdateModelPropertiesCommand({'postPath': postPath}));
    }
    final String script;
    try {
      script = await File(postPath).readAsString(encoding: utf8);
    } on Object catch (e, st) {
      logger.error('ポストファイルを読めません: $postPath', e, st);
      if (ctx.mounted) await showMessageDialog(ctx, title: Strings.error, message: 'ポストファイルを読めません\n$e');
      return;
    }
    final meta = parsePostMeta(script);
    final verr = checkPostApiVersion(meta);
    if (verr != null) {
      if (ctx.mounted) await showMessageDialog(ctx, title: Strings.error, message: verr);
      return;
    }
    if (meta!.targetDb != model.properties.targetDb.wire && ctx.mounted) {
      final go = await showConfirmDialog(ctx,
          title: '対象DBの不一致',
          message: 'ポストファイルの対象DB(${meta.targetDb})とモデルの対象DB(${model.properties.targetDb.wire})が異なります。続行しますか?',
          yes: '続行',
          no: '中止');
      if (!go) return;
    }
    // 生成前検証 → 生成
    final GenerationOutcome out;
    try {
      out = await GenerationService(QjsPostRunner()).generate(
        model,
        script,
        timeout: Duration(seconds: session.settings.postTimeoutSeconds),
        nameFormat: session.settings.nameFormat,
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
    final v = ModelValidator(model, nameFormat: session.settings.nameFormat).validate();
    if (v.hasErrors) {
      await showValidationErrors(ctx, v.errors, v.warnings);
      return;
    }
    final cur = session.filePath;
    final dir = cur != null ? cur.substring(0, cur.lastIndexOf(Platform.pathSeparator)) : await _documentsDir();
    final base = model.properties.outputFileName.isNotEmpty ? model.properties.outputFileName : Strings.untitled;
    final path = await FilePicker.platform.saveFile(
      dialogTitle: Strings.runJson,
      fileName: '$base.json',
      initialDirectory: dir,
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (path == null) return;
    try {
      await File(path).writeAsString(GenerationJsonBuilder(model).buildText(indent: true), encoding: utf8);
      session.notify('JSONを出力しました: $path');
    } on FileSystemException catch (e) {
      if (ctx.mounted) await showMessageDialog(ctx, title: Strings.error, message: '書込みに失敗しました: ${e.message}');
    }
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
    final dir = session.filePath != null
        ? session.filePath!.substring(0, session.filePath!.lastIndexOf(Platform.pathSeparator))
        : await _documentsDir();
    try {
      if (result.pages.length == 1) {
        final path = await FilePicker.platform.saveFile(
          dialogTitle: Strings.runImage,
          fileName: result.pages.single.name,
          initialDirectory: dir,
          type: FileType.custom,
          allowedExtensions: ['png'],
        );
        if (path == null) return;
        await File(path).writeAsBytes(result.pages.single.png);
      } else {
        final folder = await FilePicker.platform.getDirectoryPath(dialogTitle: '出力先のフォルダ', initialDirectory: dir);
        if (folder == null) return;
        for (final p in result.pages) {
          await File('$folder${Platform.pathSeparator}${p.name}').writeAsBytes(p.png);
        }
      }
      session.notify(result.dpiReduced
          ? '1辺が16000pxを超えるため、解像度を${result.effectiveDpi}dpiに下げて出力しました'
          : '画像を出力しました');
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
