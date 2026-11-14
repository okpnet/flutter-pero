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
    this.destroyWindow,
  });
  final EditorSession session;
  final SettingsStore settingsStore;
  final void Function(AppSettings) onSettingsApplied;
  final String? initialFile;

  /// 単一インスタンス(2つ目の起動から渡された引数を受け取る)。nullなら多重起動を許す。
  final SingleInstance? singleInstance;

  /// ウィンドウを破棄する処理(終了時)。テストで差し替える。nullなら window_manager で破棄する。
  final Future<void> Function()? destroyWindow;

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      canvasKey.currentState?.columnDragPointer.addListener(_onColumnDragPointer);
      _startup();
    });
  }

  // ---- 列ドラッグ中のタブ切替(3.4-9) ----

  final Map<int, GlobalKey> _tabKeys = {};

  // ---- タブが画面に収まらないとき(3.2-5) ----

  final ScrollController _tabScroll = ScrollController();
  bool _tabOverflow = false;
  bool _tabCanLeft = false;
  bool _tabCanRight = false;
  int? _lastTabId;

  /// タブの表示範囲の状態を更新する。変化があったときだけ、描画の後に再構築する。
  void _updateTabScroll(ScrollMetrics m) {
    final over = m.maxScrollExtent > 0.5;
    final left = m.pixels > 0.5;
    final right = m.pixels < m.maxScrollExtent - 0.5;
    if (over == _tabOverflow && left == _tabCanLeft && right == _tabCanRight) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _tabOverflow = over;
        _tabCanLeft = left;
        _tabCanRight = right;
      });
    });
  }

  /// タブの表示範囲を左右へ移動する([dir] は -1 か 1)。
  void _scrollTabs(int dir) {
    if (!_tabScroll.hasClients) return;
    final p = _tabScroll.position;
    final to = (p.pixels + dir * 240.0).clamp(0.0, p.maxScrollExtent);
    _tabScroll.animateTo(to, duration: const Duration(milliseconds: 180), curve: Curves.easeOut);
  }

  /// 表示するダイアグラムが変わったとき、そのタブが見える位置までスクロールする。
  void _revealCurrentTab() {
    final id = s.diagram.id;
    if (_lastTabId == id) return;
    _lastTabId = id;
    WidgetsBinding.instance.addPostFrameCallback((_) => _revealTab(id, 0));
  }

  void _revealTab(int id, int attempt) {
    if (!mounted || id != s.diagram.id) return;
    final ctx = _tabKeys[id]?.currentContext;
    if (ctx != null && ctx.mounted) {
      Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 150));
      return;
    }
    // 画面の外のタブはまだ作られていない(遅延構築)ので、位置を見積もって近づけ、次の描画でやり直す。
    // 見積もりは、作られたタブが増えるほど正確になる。
    if (attempt >= 8 || !_tabScroll.hasClients) return;
    final n = s.model.diagrams.length;
    final i = s.model.diagrams.indexWhere((d) => d.id == id);
    if (n < 2 || i < 0) return;
    _tabScroll.jumpTo(_tabScroll.position.maxScrollExtent * i / (n - 1));
    WidgetsBinding.instance.addPostFrameCallback((_) => _revealTab(id, attempt + 1));
  }

  Timer? _tabHoverTimer;
  int? _hoverTabId;

  /// ポインタ(画面座標)の下にあるダイアグラムのタブのID。
  int? _tabAt(Offset p) {
    for (final e in _tabKeys.entries) {
      final box = e.value.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.attached) continue;
      final r = box.localToGlobal(Offset.zero) & box.size;
      if (r.contains(p)) return e.key;
    }
    return null;
  }

  void _onColumnDragPointer() {
    final p = canvasKey.currentState?.columnDragPointer.value;
    final id = p == null ? null : _tabAt(p);
    final target = id == s.diagram.id ? null : id; // 表示中のタブは対象外
    if (target == _hoverTabId) return;
    _tabHoverTimer?.cancel();
    setState(() => _hoverTabId = target);
    if (target == null) return;
    _tabHoverTimer = Timer(const Duration(milliseconds: 600), () {
      if (!mounted) return;
      s.currentDiagramId = target;
      setState(() => _hoverTabId = null);
    });
  }

  @override
  void dispose() {
    _tabHoverTimer?.cancel();
    canvasKey.currentState?.columnDragPointer.removeListener(_onColumnDragPointer);
    _externalSub?.cancel();
    windowManager.removeListener(this);
    nameFocus.dispose();
    _searchController.dispose();
    _tabScroll.dispose();
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

  Future<void> _destroyWindow() async {
    final custom = widget.destroyWindow;
    if (custom != null) return custom();
    await windowManager.setPreventClose(false);
    await windowManager.destroy();
  }

  /// ポストファイルが1つも無いときは、警告して終了する。復元用のキャッシュは消さない(次の起動で復元できる)。
  Future<bool> _checkPostFiles() async {
    if (s.postCatalog.hasValid) return true;
    final invalid = s.postCatalog.files;
    final detail = invalid.isEmpty
        ? ''
        : '\n\n使えないポストファイル:\n${invalid.map((f) => '・${f.fileName}: ${f.problem ?? 'メタ情報がありません'}').join('\n')}';
    s.logger.error('使えるポストファイルがありません: ${s.postFolderPath()}');
    if (mounted) {
      await showMessageDialog(context,
          title: Strings.warning,
          message: '使えるポストファイル(*.post)が見つかりません。\nフォルダ: ${s.postFolderPath()}$detail\n\n'
              'ポストファイルを配置してから起動し直してください。アプリケーションを終了します。');
    }
    await widget.singleInstance?.close();
    await _destroyWindow();
    return false;
  }

  /// 起動処理(9.2-4)。復元の可否が確定した後にキャッシュを削除し、セッションロックを作る。
  Future<void> _startup() async {
    if (!await _checkPostFiles()) return;
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
        // テキスト入力中は、コピー・貼り付け・全選択・元に戻すなど、テキスト側の操作を優先する。
        // 無効な Action は、キーイベントを消費せずに上位(標準のテキスト編集)へ渡す。
        KeyboardShortcutHandler k(VoidCallback run, {bool text = false}) => KeyboardShortcutHandler(run, handlesText: text);
        return Shortcuts(
          shortcuts: <ShortcutActivator, Intent>{
            const SingleActivator(LogicalKeyboardKey.keyN, control: true): k(actions.newModel, text: true),
            const SingleActivator(LogicalKeyboardKey.keyO, control: true): k(actions.openFile, text: true),
            const SingleActivator(LogicalKeyboardKey.keyS, control: true): k(actions.saveOverwrite, text: true),
            const SingleActivator(LogicalKeyboardKey.keyS, control: true, shift: true): k(actions.saveAs, text: true),
            const SingleActivator(LogicalKeyboardKey.keyZ, control: true): k(_undo),
            const SingleActivator(LogicalKeyboardKey.keyY, control: true): k(_redo),
            const SingleActivator(LogicalKeyboardKey.keyZ, control: true, shift: true): k(_redo),
            const SingleActivator(LogicalKeyboardKey.keyC, control: true): k(s.copySelection),
            const SingleActivator(LogicalKeyboardKey.keyV, control: true): k(s.paste),
            const SingleActivator(LogicalKeyboardKey.keyD, control: true): k(s.duplicateSelection),
            const SingleActivator(LogicalKeyboardKey.keyA, control: true): k(actions.selectAll),
            const SingleActivator(LogicalKeyboardKey.delete): k(actions.removeFromDiagram),
            const SingleActivator(LogicalKeyboardKey.delete, control: true): k(actions.deleteFromModel),
            const SingleActivator(LogicalKeyboardKey.escape): k(() => s.setSelection([]), text: true),
            const SingleActivator(LogicalKeyboardKey.f5): k(actions.generate, text: true),
            const SingleActivator(LogicalKeyboardKey.comma, control: true): k(actions.openSettings, text: true),
            const SingleActivator(LogicalKeyboardKey.digit0, control: true):
                k(() => canvasKey.currentState?.resetZoom(), text: true),
            const SingleActivator(LogicalKeyboardKey.tab, control: true): k(() => s.cycleDiagram(1), text: true),
            const SingleActivator(LogicalKeyboardKey.tab, control: true, shift: true):
                k(() => s.cycleDiagram(-1), text: true),
            for (var n = 1; n <= 9; n++)
              SingleActivator(LogicalKeyboardKey(LogicalKeyboardKey.digit1.keyId + n - 1), control: true):
                  k(() => s.selectDiagramAt(n - 1), text: true),
          },
          child: Actions(
            actions: <Type, Action<Intent>>{
              KeyboardShortcutHandler: KeyboardShortcutAction(() => _editingText),
            },
          child: Focus(
            autofocus: true,
            child: Scaffold(
              body: Stack(children: [
                Column(children: [
                  _topBar(),
                  const Divider(height: 1),
                  Expanded(child: _body()),
                  const Divider(height: 1),
                  _statusBar(),
                ]),
                _busyOverlay(),
              ]),
            ),
          ),
          ),
        );
      },
    );
  }

  /// 読込などの間、画面全体を覆い、操作を受け付けず、ローディング(くるくる)とメッセージを表示する。
  Widget _busyOverlay() => ValueListenableBuilder<String?>(
        valueListenable: s.busyMessage,
        builder: (context, message, _) {
          if (message == null) return const SizedBox.shrink();
          return Positioned.fill(
            key: const ValueKey('busyOverlay'),
            child: Stack(children: [
              const ModalBarrier(dismissible: false, color: Colors.black54),
              Center(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 22),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3)),
                      const SizedBox(width: 16),
                      Text(message),
                    ]),
                  ),
                ),
              ),
            ]),
          );
        },
      );

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

  /// ヒットしたオブジェクトへ移動する(3.9-16)。ダイアグラムの切替後に、画面の中央へスクロールする。
  void _moveSearch(int delta) {
    final id = s.moveSearch(delta);
    if (id == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => canvasKey.currentState?.revealEntity(id));
  }

  /// 検索の3部品(入力欄、正規表現のトグル、範囲のプルダウン)で共通の高さ。
  static const double _searchHeight = 32;

  Widget _topBar() {
    final q = s.searchQuery;
    final h = s.highlights;
    final theme = Theme.of(context);
    final borderColor = theme.colorScheme.outline;
    final radius = BorderRadius.circular(4);
    OutlineInputBorder border(Color c, [double w = 1]) =>
        OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: c, width: w));
    return SizedBox(
      height: 44,
      child: Center(
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(
            width: 240,
            height: _searchHeight,
            child: TextField(
              key: const ValueKey('searchField'),
              controller: _searchController,
              // テーマの入力欄の余白に左右されないよう、高さいっぱいに広げて縦中央に置く。
              expands: true,
              maxLines: null,
              minLines: null,
              textAlignVertical: TextAlignVertical.center,
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                isDense: true,
                filled: false,
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
                border: border(borderColor),
                enabledBorder: border(borderColor),
                focusedBorder: border(theme.colorScheme.primary, 1.5),
              ),
              onChanged: (v) => s.searchQuery = q.copyWith(text: v),
              onSubmitted: (_) => _moveSearch(HardwareKeyboard.instance.isShiftPressed ? -1 : 1),
            ),
          ),
          const SizedBox(width: 6),
          Tooltip(
            message: Strings.searchRegex,
            child: InkWell(
              key: const ValueKey('searchRegex'),
              borderRadius: radius,
              onTap: () => s.searchQuery = q.copyWith(regex: !q.regex),
              child: Container(
                width: _searchHeight,
                height: _searchHeight,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: q.regex ? theme.colorScheme.primary.withValues(alpha: 0.2) : null,
                  border: Border.all(color: q.regex ? theme.colorScheme.primary : borderColor),
                  borderRadius: radius,
                ),
                child: const Text('.*', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Container(
            height: _searchHeight,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(border: Border.all(color: borderColor), borderRadius: radius),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<SearchScope>(
                key: const ValueKey('searchScope'),
                value: q.scope,
                isDense: true,
                style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurface),
                items: [for (final sc in SearchScope.values) DropdownMenuItem(value: sc, child: Text(sc.label))],
                onChanged: (v) => s.searchQuery = q.copyWith(scope: v),
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (!q.isEmpty)
            Text(
              h.invalidRegex ? Strings.searchInvalidRegex : '${h.hitCount}${Strings.searchHitCount}',
              key: const ValueKey('searchStatus'),
              style: TextStyle(fontSize: 12, color: h.invalidRegex ? Colors.red : theme.hintColor),
            ),
          IconButton(
            key: const ValueKey('searchPrev'),
            tooltip: Strings.searchPrev,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.keyboard_arrow_up, size: 20),
            onPressed: h.targets.isEmpty ? null : () => _moveSearch(-1),
          ),
          IconButton(
            key: const ValueKey('searchNext'),
            tooltip: Strings.searchNext,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.keyboard_arrow_down, size: 20),
            onPressed: h.targets.isEmpty ? null : () => _moveSearch(1),
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

  /// サイドメニューの幅(3.3-3)。メニュー項目が折り返さずに1行で収まる幅。
  static const double sideMenuWidth = 200;

  /// ペインを開閉する(スライドイン/アウト)。開いた幅のまま描画し、はみ出す分を切り取る。
  Widget _slidePane({required bool open, required double width, required AlignmentGeometry alignment, required Widget child}) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeInOut,
      width: open ? width : 0,
      child: ClipRect(
        child: ExcludeFocus(
          excluding: !open,
          child: IgnorePointer(
            ignoring: !open,
            child: OverflowBox(
              alignment: alignment,
              minWidth: width,
              maxWidth: width,
              child: child,
            ),
          ),
        ),
      ),
    );
  }

  Widget _body() {
    return LayoutBuilder(builder: (context, c) {
      const rightMin = 240.0;
      var rightW = (c.maxWidth * s.settings.rightPaneRatio).clamp(rightMin, c.maxWidth * 0.6);
      return Row(children: [
        _slidePane(
          open: s.settings.sideMenuOpen,
          width: sideMenuWidth + 1,
          alignment: Alignment.centerLeft,
          child: Row(children: [_sideMenu(), const VerticalDivider(width: 1)]),
        ),
        Expanded(
          child: Column(children: [
            _tabBar(),
            const Divider(height: 1),
            Expanded(child: DiagramCanvas(key: canvasKey, session: s, host: actions)),
          ]),
        ),
        _slidePane(
          open: s.settings.rightPaneOpen,
          width: rightW + 6,
          alignment: Alignment.centerRight,
          child: Row(children: [
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
          ]),
        ),
      ]);
    });
  }

  void _togglePane({required bool side}) {
    if (side) {
      s.settings.sideMenuOpen = !s.settings.sideMenuOpen;
    } else {
      s.settings.rightPaneOpen = !s.settings.rightPaneOpen;
    }
    s.notify(null);
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
      key: const ValueKey('sideMenu'),
      width: sideMenuWidth,
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

  /// 折り返さずに1行で表示する。収まらないときは文字を縮小する。
  Widget _oneLine(String text, TextStyle? style) => FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(text, style: style, maxLines: 1, softWrap: false),
      );

  List<Widget> _sideTabItems() {
    Widget mi(String label, VoidCallback? onPressed, {SingleActivator? key}) => ListTile(
          dense: true,
          visualDensity: VisualDensity.compact,
          enabled: onPressed != null,
          title: _oneLine(label, const TextStyle(fontSize: 13)),
          subtitle: key == null ? null : _oneLine(_keyLabel(key), const TextStyle(fontSize: 10)),
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
                title: _oneLine(label, null),
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
              title: _oneLine(Strings.fileRecent, const TextStyle(fontSize: 13)),
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
          mi(Strings.fileImportSql, actions.importSql),
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
    _revealCurrentTab();
    return SizedBox(
      height: 36,
      child: Row(children: [
        IconButton(
          key: const ValueKey('toggleSideMenu'),
          tooltip: s.settings.sideMenuOpen ? Strings.hideSideMenu : Strings.showSideMenu,
          icon: Icon(s.settings.sideMenuOpen ? Icons.menu_open : Icons.menu, size: 18),
          onPressed: () => _togglePane(side: true),
        ),
        if (_tabOverflow)
          IconButton(
            key: const ValueKey('tabScrollLeft'),
            tooltip: Strings.tabScrollLeft,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.arrow_left, size: 22),
            onPressed: _tabCanLeft ? () => _scrollTabs(-1) : null,
          ),
        Expanded(
          child: NotificationListener<ScrollMetricsNotification>(
            onNotification: (n) {
              _updateTabScroll(n.metrics);
              return false;
            },
            child: NotificationListener<ScrollNotification>(
              onNotification: (n) {
                _updateTabScroll(n.metrics);
                return false;
              },
              child: ReorderableListView(
                scrollController: _tabScroll,
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
          ),
        ),
        if (_tabOverflow)
          IconButton(
            key: const ValueKey('tabScrollRight'),
            tooltip: Strings.tabScrollRight,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.arrow_right, size: 22),
            onPressed: _tabCanRight ? () => _scrollTabs(1) : null,
          ),
        IconButton(tooltip: Strings.opAddDiagram, icon: const Icon(Icons.add, size: 18), onPressed: actions.addDiagram),
        IconButton(
          key: const ValueKey('toggleRightPane'),
          tooltip: s.settings.rightPaneOpen ? Strings.hideRightPane : Strings.showRightPane,
          icon: Icon(s.settings.rightPaneOpen ? Icons.vertical_split : Icons.vertical_split_outlined, size: 18),
          onPressed: () => _togglePane(side: false),
        ),
      ]),
    );
  }

  Widget _tab(Diagram d) {
    final selected = d.id == s.diagram.id;
    final theme = Theme.of(context);
    final hover = d.id == _hoverTabId; // 列ドラッグ中に、ここへ切り替わる
    return GestureDetector(
      key: _tabKeys.putIfAbsent(d.id, GlobalKey.new),
      onTap: () => s.currentDiagramId = d.id,
      onDoubleTap: () => actions.renameDiagram(d.id),
      child: Container(
        padding: const EdgeInsets.only(left: 12, right: 4),
        decoration: BoxDecoration(
          color: hover
              ? theme.colorScheme.tertiary.withValues(alpha: 0.35)
              : selected
                  ? theme.colorScheme.primary.withValues(alpha: 0.15)
                  : null,
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


/// キーボードショートカットの処理(Command パターン)。[handlesText] が偽のものは、
/// テキスト入力中は無効になり、キーイベントを消費しない(貼り付けなど、テキスト側の操作を優先する)。
class KeyboardShortcutHandler extends Intent {
  const KeyboardShortcutHandler(this.run, {this.handlesText = false});
  final VoidCallback run;
  final bool handlesText;
}

class KeyboardShortcutAction extends Action<KeyboardShortcutHandler> {
  KeyboardShortcutAction(this.editingText);
  final bool Function() editingText;

  @override
  bool isEnabled(KeyboardShortcutHandler intent) =>
      intent.handlesText || !editingText();

  @override
  Object? invoke(KeyboardShortcutHandler intent) {
    intent.run();
    return null;
  }
}
