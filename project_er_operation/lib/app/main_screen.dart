// window_manager 0.6 の旧API(legacy)を使う。新APIへの移行は今後の課題。
// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/legacy.dart';

import '../actions/editor_actions.dart';
import '../canvas/canvas.dart';
import '../command/command.dart';
import '../common/common.dart';
import '../dialog/dialog.dart';
import '../model/model.dart' hide Orientation;
import '../panel/panel.dart';
import '../session/session.dart';
import '../settings/settings.dart';
import 'single_instance.dart';

/// メイン画面(3.1): メニューバー、サイドメニュー、キャンバス(タブバー)、右ペイン、ステータスバー。
class MainScreen extends StatefulWidget {
  const MainScreen({
    super.key,
    required this.session,
    required this.settingsStore,
    required this.onSettingsApplied,
    this.initialFile,
    this.singleInstance,
  });
  final EditorSession session;
  final SettingsStore settingsStore;
  final void Function(AppSettings) onSettingsApplied;
  final String? initialFile;

  /// 単一インスタンス(2つ目の起動から渡された引数を受け取る)。nullなら多重起動を許す。
  final SingleInstance? singleInstance;

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with WindowListener {
  final canvasKey = GlobalKey<DiagramCanvasState>();
  final nameFocus = FocusNode();
  late final EditorActions actions;
  String _lastTitle = '';
  StreamSubscription<List<String>>? _externalSub;

  EditorSession get s => widget.session;

  @override
  void initState() {
    super.initState();
    actions = EditorActions(
      session: s,
      contextProvider: () => context,
      canvasKey: canvasKey,
      nameFocus: nameFocus,
      settingsStore: widget.settingsStore,
      onSettingsApplied: widget.onSettingsApplied,
      requestExit: _shutdown,
    );
    windowManager.addListener(this);
    _externalSub = widget.singleInstance?.messages.listen(_onExternalArgs);
    windowManager.setPreventClose(true);
    WidgetsBinding.instance.addPostFrameCallback((_) => _startup());
  }

  @override
  void dispose() {
    _externalSub?.cancel();
    windowManager.removeListener(this);
    nameFocus.dispose();
    _searchController.dispose();
    super.dispose();
  }

  /// 2つ目の起動から渡された引数(2-14)。ウィンドウを前面に出し、`.pero` が指定されていれば開く。
  Future<void> _onExternalArgs(List<String> args) async {
    try {
      if (await windowManager.isMinimized()) await windowManager.restore();
      await windowManager.show();
      await windowManager.focus();
    } on Object catch (e) {
      s.logger.warn('ウィンドウを前面に出せません: $e');
    }
    final path = peroPathFromArgs(args);
    s.logger.info('別の起動から引数を受信: ${args.join(' ')}');
    if (path != null && mounted) await actions.openPath(path);
  }

  /// 起動処理(9.2-4)。復元の可否が確定した後にキャッシュを削除し、セッションロックを作る。
  Future<void> _startup() async {
    final cache = s.cache;
    if (cache.previousSessionCrashed) {
      final state = cache.read(corrupt: (e) => s.logger.error('キャッシュが破損しています: $e'));
      if (cache.isRecoverable(state) && mounted) {
        final yes = await showConfirmDialog(context, title: Strings.restoreTitle, message: Strings.restoreMessage);
        if (yes) {
          final r = recoverFromCache(state!, (m) => EntityLayouter(m, s.settings.displayOptions));
          if (r.model != null) {
            s.openRecovered(r.model!, state.filePath);
            s.logger.info('キャッシュから復元しました');
          } else {
            s.logger.error('キャッシュの再生に失敗: ${r.error}');
            if (mounted) {
              await showMessageDialog(context, title: Strings.error, message: '復元に失敗しました。通常どおり起動します。\n${r.error}');
            }
          }
        }
      }
    }
    // 復元中のモデルがあるときは、その基点を保つ必要はない(復元後は未保存の状態)。
    if (s.filePath == null || !s.isDirty) cache.clear();
    cache.createSessionLock();
    s.logger.sink.purgeOld();
    s.startBackupTimer();
    if (widget.initialFile != null && mounted) {
      await actions.openPath(widget.initialFile!, skipConfirm: true);
    }
  }

  /// 正常終了処理(設定の保存、キャッシュとセッションロックの削除。9.2-4)。
  Future<void> _shutdown() async {
    s.logger.info('正常終了処理を開始');
    try {
      final b = await windowManager.getBounds();
      s.settings.windowMaximized = await windowManager.isMaximized();
      if (!s.settings.windowMaximized) {
        s.settings
          ..windowX = b.left
          ..windowY = b.top
          ..windowWidth = b.width
          ..windowHeight = b.height;
      }
    } on Object {
      // ウィンドウ情報が取れなくても終了処理は続ける。
    }
    widget.settingsStore.save(s.settings);
    s.cache.clear();
    s.cache.deleteSessionLock();
    await widget.singleInstance?.close();
    s.logger.info('正常終了');
    await windowManager.setPreventClose(false);
    await windowManager.destroy();
  }

  @override
  void onWindowClose() {
    s.logger.info('onWindowClose: ウィンドウを閉じる要求');
    actions.exit();
  }

  void _updateTitle() {
    final t = '${s.fileNameForTitle}${s.isDirty ? '*' : ''} - ${Strings.appName}';
    if (t != _lastTitle) {
      _lastTitle = t;
      windowManager.setTitle(t);
    }
  }

  // ---- 組み立て ----

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        _updateTitle();
        return CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.keyN, control: true): actions.newModel,
            const SingleActivator(LogicalKeyboardKey.keyO, control: true): actions.openFile,
            const SingleActivator(LogicalKeyboardKey.keyS, control: true): actions.saveOverwrite,
            const SingleActivator(LogicalKeyboardKey.keyS, control: true, shift: true): actions.saveAs,
            const SingleActivator(LogicalKeyboardKey.keyZ, control: true): _undo,
            const SingleActivator(LogicalKeyboardKey.keyY, control: true): _redo,
            const SingleActivator(LogicalKeyboardKey.keyZ, control: true, shift: true): _redo,
            const SingleActivator(LogicalKeyboardKey.keyC, control: true): s.copySelection,
            const SingleActivator(LogicalKeyboardKey.keyV, control: true): s.paste,
            const SingleActivator(LogicalKeyboardKey.keyD, control: true): s.duplicateSelection,
            const SingleActivator(LogicalKeyboardKey.keyA, control: true): actions.selectAll,
            const SingleActivator(LogicalKeyboardKey.delete): actions.removeFromDiagram,
            const SingleActivator(LogicalKeyboardKey.delete, control: true): actions.deleteFromModel,
            const SingleActivator(LogicalKeyboardKey.escape): () => s.setSelection([]),
            const SingleActivator(LogicalKeyboardKey.f5): actions.generate,
            const SingleActivator(LogicalKeyboardKey.comma, control: true): actions.openSettings,
            const SingleActivator(LogicalKeyboardKey.digit0, control: true): () => canvasKey.currentState?.resetZoom(),
          },
          child: Focus(
            autofocus: true,
            child: Scaffold(
              body: Column(children: [
                _topBar(),
                const Divider(height: 1),
                Expanded(child: _body()),
                const Divider(height: 1),
                _statusBar(),
              ]),
            ),
          ),
        );
      },
    );
  }

  void _undo() {
    if (_editingText) return;
    s.undo();
  }

  void _redo() {
    if (_editingText) return;
    s.redo();
  }

  /// テキスト入力中は、テキスト側のUndo/Redoを優先する。
  bool get _editingText {
    final f = FocusManager.instance.primaryFocus;
    return f?.context?.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  // ---- トップバー: 検索(3.9) ----

  final _searchController = TextEditingController();

  Widget _topBar() {
    final q = s.searchQuery;
    final h = s.highlights;
    final theme = Theme.of(context);
    return SizedBox(
      height: 40,
      child: Center(
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(
            width: 240,
            height: 30,
            child: TextField(
              key: const ValueKey('searchField'),
              controller: _searchController,
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                isDense: true,
                hintText: Strings.searchHint,
                prefixIcon: const Icon(Icons.search, size: 16),
                prefixIconConstraints: const BoxConstraints(minWidth: 28),
                suffixIcon: q.isEmpty
                    ? null
                    : InkWell(
                        onTap: () {
                          _searchController.clear();
                          s.searchQuery = q.copyWith(text: '');
                        },
                        child: const Icon(Icons.close, size: 14),
                      ),
                suffixIconConstraints: const BoxConstraints(minWidth: 24),
                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                border: const OutlineInputBorder(),
              ),
              onChanged: (v) => s.searchQuery = q.copyWith(text: v),
            ),
          ),
          const SizedBox(width: 6),
          Tooltip(
            message: Strings.searchRegex,
            child: InkWell(
              key: const ValueKey('searchRegex'),
              borderRadius: BorderRadius.circular(4),
              onTap: () => s.searchQuery = q.copyWith(regex: !q.regex),
              child: Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: q.regex ? theme.colorScheme.primary.withValues(alpha: 0.2) : null,
                  border: Border.all(color: q.regex ? theme.colorScheme.primary : theme.dividerColor),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text('.*', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
              ),
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            height: 30,
            child: DropdownButton<SearchScope>(
              key: const ValueKey('searchScope'),
              value: q.scope,
              underline: const SizedBox(),
              isDense: true,
              style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurface),
              items: [for (final sc in SearchScope.values) DropdownMenuItem(value: sc, child: Text(sc.label))],
              onChanged: (v) => s.searchQuery = q.copyWith(scope: v),
            ),
          ),
          const SizedBox(width: 8),
          if (!q.isEmpty)
            Text(
              h.invalidRegex ? Strings.searchInvalidRegex : '${h.hitCount}${Strings.searchHitCount}',
              key: const ValueKey('searchStatus'),
              style: TextStyle(fontSize: 12, color: h.invalidRegex ? Colors.red : theme.hintColor),
            ),
        ]),
      ),
    );
  }

  String _keyLabel(SingleActivator a) {
    final parts = <String>[
      if (a.control) 'Ctrl',
      if (a.shift) 'Shift',
      if (a.alt) 'Alt',
      a.trigger == LogicalKeyboardKey.comma
          ? ','
          : a.trigger == LogicalKeyboardKey.delete
              ? 'Delete'
              : a.trigger == LogicalKeyboardKey.f5
                  ? 'F5'
                  : a.trigger.keyLabel,
    ];
    return parts.join('+');
  }

  Widget _body() {
    return LayoutBuilder(builder: (context, c) {
      final rightMin = 240.0;
      var rightW = (c.maxWidth * s.settings.rightPaneRatio).clamp(rightMin, c.maxWidth * 0.6);
      return Row(children: [
        _sideMenu(),
        const VerticalDivider(width: 1),
        Expanded(
          child: Column(children: [
            _tabBar(),
            const Divider(height: 1),
            Expanded(child: DiagramCanvas(key: canvasKey, session: s, host: actions)),
          ]),
        ),
        MouseRegion(
          cursor: SystemMouseCursors.resizeColumn,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragUpdate: (d) {
              rightW = (rightW - d.delta.dx).clamp(rightMin, c.maxWidth * 0.6);
              s.settings.rightPaneRatio = rightW / c.maxWidth;
              setState(() {});
            },
            child: const SizedBox(width: 6, child: VerticalDivider(width: 6)),
          ),
        ),
        SizedBox(width: rightW, child: _rightPane()),
      ]);
    });
  }

  // ---- サイドメニュー(3.3): 機能別のタブ ----

  int _sideTab = 0;

  Widget _sideMenu() {
    final tabs = [
      (Icons.add_box_outlined, Strings.sideTabAdd),
      (Icons.folder_open, Strings.menuFile),
      (Icons.edit_outlined, Strings.menuOperation),
      (Icons.play_arrow_outlined, Strings.menuRun),
    ];
    final theme = Theme.of(context);
    return SizedBox(
      width: 160,
      child: Column(children: [
        Row(children: [
          for (var i = 0; i < tabs.length; i++)
            Expanded(
              child: Tooltip(
                message: tabs[i].$2,
                child: InkWell(
                  key: ValueKey('sideTab$i'),
                  onTap: () => setState(() => _sideTab = i),
                  child: Container(
                    height: 36,
                    decoration: BoxDecoration(
                      color: _sideTab == i ? theme.colorScheme.primary.withValues(alpha: 0.15) : null,
                      border: Border(
                          bottom: BorderSide(
                              color: _sideTab == i ? theme.colorScheme.primary : Colors.transparent, width: 2)),
                    ),
                    child: Icon(tabs[i].$1, size: 20),
                  ),
                ),
              ),
            ),
        ]),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text(tabs[_sideTab].$2, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
        ),
        const Divider(height: 1),
        Expanded(child: ListView(children: _sideTabItems())),
      ]),
    );
  }

  List<Widget> _sideTabItems() {
    Widget mi(String label, VoidCallback? onPressed, {SingleActivator? key}) => ListTile(
          dense: true,
          visualDensity: VisualDensity.compact,
          enabled: onPressed != null,
          title: Text(label, style: const TextStyle(fontSize: 13)),
          subtitle: key == null ? null : Text(_keyLabel(key), style: const TextStyle(fontSize: 10)),
          onTap: onPressed,
        );
    const div = Divider(height: 1);
    switch (_sideTab) {
      case 0:
        Widget item(SideItem it, IconData icon, String label, VoidCallback onTap) => Draggable<SideItem>(
              data: it,
              feedback: Material(
                elevation: 4,
                child: Padding(padding: const EdgeInsets.all(8), child: Text(label)),
              ),
              child: ListTile(
                dense: true,
                leading: Icon(icon, size: 20),
                title: Text(label),
                onTap: onTap,
              ),
            );
        return [
          item(SideItem.table, Icons.table_chart_outlined, Strings.sideTable, actions.addTableAtCenter),
          item(SideItem.joinView, Icons.join_inner, Strings.sideJoinView, () => actions.addViewAtCenter(ViewType.join)),
          item(SideItem.functionView, Icons.functions, Strings.sideFunctionView, () => actions.addViewAtCenter(ViewType.function)),
          item(SideItem.sqlView, Icons.code, Strings.sideSqlView, () => actions.addViewAtCenter(ViewType.sql)),
        ];
      case 1:
        final recent = s.settings.recentFiles.take(s.settings.recentFileCount).toList();
        return [
          mi(Strings.fileNew, actions.newModel, key: const SingleActivator(LogicalKeyboardKey.keyN, control: true)),
          mi(Strings.fileOpen, actions.openFile, key: const SingleActivator(LogicalKeyboardKey.keyO, control: true)),
          mi(Strings.fileSaveAs, actions.saveAs, key: const SingleActivator(LogicalKeyboardKey.keyS, control: true, shift: true)),
          mi(Strings.fileSave, s.filePath == null ? null : actions.saveOverwrite, key: const SingleActivator(LogicalKeyboardKey.keyS, control: true)),
          if (recent.isNotEmpty)
            ExpansionTile(
              key: const ValueKey('recentFiles'),
              dense: true,
              tilePadding: const EdgeInsets.symmetric(horizontal: 16),
              title: const Text(Strings.fileRecent, style: TextStyle(fontSize: 13)),
              children: [
                for (final p in recent)
                  ListTile(
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    title: Text(p.substring(p.lastIndexOf(Platform.pathSeparator) + 1),
                        style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis),
                    subtitle: Text(p, style: const TextStyle(fontSize: 9), overflow: TextOverflow.ellipsis),
                    onTap: () => actions.openPath(p),
                  ),
              ],
            ),
          div,
          mi(Strings.fileSettings, actions.openSettings, key: const SingleActivator(LogicalKeyboardKey.comma, control: true)),
          div,
          mi(Strings.fileExit, actions.exit),
        ];
      case 2:
        return [
          mi(Strings.opUndo, s.history.canUndo ? s.undo : null, key: const SingleActivator(LogicalKeyboardKey.keyZ, control: true)),
          mi(Strings.opRedo, s.history.canRedo ? s.redo : null, key: const SingleActivator(LogicalKeyboardKey.keyY, control: true)),
          div,
          mi(Strings.opAddTable, actions.addTableAtCenter),
          mi(Strings.opAddJoinView, () => actions.addViewAtCenter(ViewType.join)),
          mi(Strings.opAddFunctionView, () => actions.addViewAtCenter(ViewType.function)),
          mi(Strings.opAddSqlView, () => actions.addViewAtCenter(ViewType.sql)),
          div,
          mi(Strings.opRemoveFromDiagram, actions.canRemoveFromDiagram ? actions.removeFromDiagram : null, key: const SingleActivator(LogicalKeyboardKey.delete)),
          mi(Strings.opDeleteFromModel, actions.canRemoveFromDiagram ? actions.deleteFromModel : null, key: const SingleActivator(LogicalKeyboardKey.delete, control: true)),
          div,
          mi(Strings.opAddRelationship, actions.canAddRelationship ? actions.addRelationship : null),
          mi(Strings.opRemoveRelationship, actions.canRemoveRelationship ? actions.removeRelationship : null),
          div,
          mi(Strings.opCopy, s.copySelection, key: const SingleActivator(LogicalKeyboardKey.keyC, control: true)),
          mi(Strings.opPaste, s.clipboard == null ? null : s.paste, key: const SingleActivator(LogicalKeyboardKey.keyV, control: true)),
          mi(Strings.opDuplicate, s.duplicateSelection, key: const SingleActivator(LogicalKeyboardKey.keyD, control: true)),
          mi(Strings.opSelectAll, actions.selectAll, key: const SingleActivator(LogicalKeyboardKey.keyA, control: true)),
          mi(Strings.opAutoLayout, actions.autoLayout),
          div,
          mi(Strings.opManageMethods, actions.manageMethods),
          mi(Strings.opManagePatterns, actions.managePatterns),
          mi(Strings.opManageTypes, actions.manageTypes),
          div,
          mi(Strings.opAddDiagram, actions.addDiagram),
          mi(Strings.opRenameDiagram, () => actions.renameDiagram(s.diagram.id)),
          mi(Strings.opDeleteDiagram, () => actions.deleteDiagram(s.diagram.id)),
        ];
      default:
        return [
          mi(Strings.runGenerate, actions.generate, key: const SingleActivator(LogicalKeyboardKey.f5)),
          mi(Strings.runJson, actions.exportJson),
          mi(Strings.runImage, actions.exportImage),
        ];
    }
  }

  Widget _tabBar() {
    final m = s.model;
    return SizedBox(
      height: 36,
      child: Row(children: [
        Expanded(
          child: ReorderableListView(
            scrollDirection: Axis.horizontal,
            buildDefaultDragHandles: false,
            onReorderItem: (from, to) => s.run(MoveDiagramCommand(m.diagrams[from].id, to)),
            children: [
              for (var i = 0; i < m.diagrams.length; i++)
                ReorderableDragStartListener(
                  key: ValueKey('tab${m.diagrams[i].id}'),
                  index: i,
                  child: _tab(m.diagrams[i]),
                ),
            ],
          ),
        ),
        IconButton(tooltip: Strings.opAddDiagram, icon: const Icon(Icons.add, size: 18), onPressed: actions.addDiagram),
      ]),
    );
  }

  Widget _tab(Diagram d) {
    final selected = d.id == s.diagram.id;
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: () => s.currentDiagramId = d.id,
      onDoubleTap: () => actions.renameDiagram(d.id),
      child: Container(
        padding: const EdgeInsets.only(left: 12, right: 4),
        decoration: BoxDecoration(
          color: selected ? theme.colorScheme.primary.withValues(alpha: 0.15) : null,
          border: Border(bottom: BorderSide(color: selected ? theme.colorScheme.primary : Colors.transparent, width: 2)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(d.name),
          InkWell(
            onTap: () => actions.deleteDiagram(d.id),
            child: const Padding(padding: EdgeInsets.all(4), child: Icon(Icons.close, size: 14)),
          ),
        ]),
      ),
    );
  }

  Widget _rightPane() {
    return LayoutBuilder(builder: (context, c) {
      const minH = 120.0;
      var propsH = (c.maxHeight * s.settings.propsRatio).clamp(minH, c.maxHeight - minH - 6);
      return Column(children: [
        SizedBox(height: propsH, child: PropertyPanel(
            session: s,
            nameFocus: nameFocus,
            onManageMethods: actions.manageMethods,
            onEditView: actions.editView,
          )),
        MouseRegion(
          cursor: SystemMouseCursors.resizeRow,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onVerticalDragUpdate: (d) {
              propsH = (propsH + d.delta.dy).clamp(minH, c.maxHeight - minH - 6);
              s.settings.propsRatio = propsH / c.maxHeight;
              setState(() {});
            },
            child: const SizedBox(height: 6, child: Divider(height: 6)),
          ),
        ),
        Expanded(
          child: TableListPanel(
            session: s,
            onReveal: (id) => canvasKey.currentState?.revealEntity(id),
            onPlace: (id) {
              final c = canvasKey.currentState?.viewCenterModel ?? const Offset(40, 40);
              s.run(AddPlacementsCommand(s.diagram.id, [[id.toDouble(), c.dx, c.dy]]));
            },
          ),
        ),
      ]);
    });
  }

  Widget _statusBar() {
    final z = (s.diagram.view.zoom * 100).round();
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Row(children: [
        Expanded(child: Text(s.statusMessage ?? '', overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12))),
        Text('${s.selection.length}${Strings.selectedCount}', style: const TextStyle(fontSize: 12)),
        const SizedBox(width: 16),
        InkWell(
          onTap: () => canvasKey.currentState?.resetZoom(),
          child: Text('$z%', style: const TextStyle(fontSize: 12)),
        ),
      ]),
    );
  }
}

/// 起動時のファイル指定(コマンドライン引数)から `.pero` のパスを取り出す。
String? peroPathFromArgs(List<String> args) {
  for (final a in args) {
    if (a.toLowerCase().endsWith('.pero') && File(a).existsSync()) return a;
  }
  return null;
}

