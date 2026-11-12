import '../model/model.dart';
import '../persistence/persistence.dart';

/// コマンドが実行できない(ロック、参照などの理由)ときに投げる。
/// 状態は変更しない(履歴にも積まれない)。
class CommandException implements Exception {
  CommandException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// コマンドの実行環境。
class CommandContext {
  CommandContext(this.model, this.layouter);
  final ErModel model;

  /// 用紙ページの再計算(5.2-4)に使う寸法計算。
  EntityLayouter Function() layouter;

  void recalcPages(Diagram d) {
    final l = layouter();
    d.recalcPages((p) => l.placementSize(p));
  }

  void recalcAllPages() {
    for (final d in model.diagrams) {
      recalcPages(d);
    }
  }
}

/// 変更の単位(Command パターン)。種別と引数のJSONにシリアライズできる(9.1-7)。
/// 取り消し用の情報は [CommandHistory] が状態の差分から作る(Memento パターン)。
abstract class ModelCommand {
  String get type;
  Map<String, Object?> argsToJson();
  void apply(CommandContext ctx);

  Map<String, Object?> toJson() => {'type': type, 'args': argsToJson()};
}

// ---- 状態の差分(Memento) ----

class StateSnapshot {
  StateSnapshot(this.sig, this.obj);
  final Map<String, String> sig;
  final Map<String, Object?> obj;
}

String _j(Object? o) => PeroEncoder.encodeCompact(o);

StateSnapshot _take(ErModel m) {
  final sig = <String, String>{};
  final obj = <String, Object?>{};
  for (final e in m.entities) {
    sig['e:${e.id}'] = _j(PeroEncoder.entityToMap(e));
    obj['e:${e.id}'] = e.copy();
  }
  for (final r in m.relationships) {
    sig['r:${r.id}'] = _j(PeroEncoder.relationshipToMap(r));
    obj['r:${r.id}'] = r.copy();
  }
  for (final d in m.diagrams) {
    sig['d:${d.id}'] = _j(PeroEncoder.diagramToMap(d));
    obj['d:${d.id}'] = d.copy();
  }
  void list(String k, List<Object?> l, Object? Function(Object?) enc) {
    sig[k] = _j(l.map(enc).toList());
  }

  sig['props'] = _j(PeroEncoder.toMap(m)['properties']);
  obj['props'] = m.properties.copy();
  list('types', m.types, (x) => PeroEncoder.typeToMap(x as DataType));
  obj['types'] = m.types.map((t) => t.copy()).toList();
  list('methods', m.methods, (x) => PeroEncoder.methodToMap(x as MethodDef));
  obj['methods'] = m.methods.map((t) => t.copy()).toList();
  list('patterns', m.patterns, (x) => PeroEncoder.patternToMap(x as CommonColumnPattern));
  obj['patterns'] = m.patterns.map((t) => t.copy()).toList();
  sig['nextId'] = '${m.nextId}';
  obj['nextId'] = m.nextId;
  final oe = m.entities.map((e) => e.id).toList();
  final or = m.relationships.map((e) => e.id).toList();
  final od = m.diagrams.map((e) => e.id).toList();
  sig['order:e'] = oe.join(',');
  obj['order:e'] = oe;
  sig['order:r'] = or.join(',');
  obj['order:r'] = or;
  sig['order:d'] = od.join(',');
  obj['order:d'] = od;
  return StateSnapshot(sig, obj);
}

/// 変更のあったキーだけを持つ状態。
class StateDelta {
  StateDelta(this.before, this.after);
  final Map<String, Object?> before;
  final Map<String, Object?> after;

  static StateDelta diff(StateSnapshot a, StateSnapshot b) {
    final before = <String, Object?>{};
    final after = <String, Object?>{};
    for (final k in {...a.sig.keys, ...b.sig.keys}) {
      if (a.sig[k] != b.sig[k]) {
        before[k] = a.obj[k];
        after[k] = b.obj[k];
      }
    }
    return StateDelta(before, after);
  }

  bool get isEmpty => before.isEmpty;
}

/// 状態を復元する。値がnullのキーは削除を表す。
void _restore(ErModel m, Map<String, Object?> state) {
  for (final entry in state.entries) {
    final k = entry.key;
    final v = entry.value;
    if (k.startsWith('e:')) {
      final id = int.parse(k.substring(2));
      m.entities.removeWhere((e) => e.id == id);
      if (v != null) m.entities.add((v as Entity).copy());
    } else if (k.startsWith('r:')) {
      final id = int.parse(k.substring(2));
      m.relationships.removeWhere((e) => e.id == id);
      if (v != null) m.relationships.add((v as Relationship).copy());
    } else if (k.startsWith('d:')) {
      final id = int.parse(k.substring(2));
      m.diagrams.removeWhere((e) => e.id == id);
      if (v != null) m.diagrams.add((v as Diagram).copy());
    } else if (k == 'props') {
      m.properties = (v as ModelProperties).copy();
    } else if (k == 'types') {
      m.types = (v as List).map((t) => (t as DataType).copy()).toList();
    } else if (k == 'methods') {
      m.methods = (v as List).map((t) => (t as MethodDef).copy()).toList();
    } else if (k == 'patterns') {
      m.patterns = (v as List).map((t) => (t as CommonColumnPattern).copy()).toList();
    } else if (k == 'nextId') {
      m.nextId = v as int;
    }
  }
  void reorder<T>(String key, List<T> list, int Function(T) idOf) {
    final order = state[key];
    if (order is! List) return;
    final pos = {for (var i = 0; i < order.length; i++) order[i] as int: i};
    list.sort((a, b) => (pos[idOf(a)] ?? 1 << 30).compareTo(pos[idOf(b)] ?? 1 << 30));
  }

  reorder<Entity>('order:e', m.entities, (e) => e.id);
  reorder<Relationship>('order:r', m.relationships, (e) => e.id);
  reorder<Diagram>('order:d', m.diagrams, (e) => e.id);
}

/// 履歴の1件。
class HistoryEntry {
  HistoryEntry(this.command, this.delta);
  final ModelCommand command;
  final StateDelta delta;
}

/// 履歴(9.1)。実行・取り消し・やり直しの記録を [onJournal] へ通知する(9.2)。
class CommandHistory {
  CommandHistory(this.context, {this.limit = 100});

  CommandContext context;
  int limit;
  final List<HistoryEntry> _entries = [];
  int _pos = 0;
  int? _savedPos = 0;

  /// キャッシュ(9.2)への記録。`exec` / `undo` / `redo`。
  void Function(Map<String, Object?> event)? onJournal;

  ErModel get model => context.model;
  bool get canUndo => _pos > 0;
  bool get canRedo => _pos < _entries.length;
  bool get isDirty => _savedPos != _pos;

  /// 変更の都度増える番号(バックアップの要否判定に使う)。
  int get revision => _revision;
  int _revision = 0;

  /// 保存または読込の時点を記録する(9.1-5)。
  void markSaved() => _savedPos = _pos;

  /// 保存済みの位置を失効させ、未保存の状態にする(キャッシュからの復元後)。
  void markUnsaved() => _savedPos = null;

  /// 履歴をクリアする(新規作成、ファイルを開く)。
  void clear() {
    _entries.clear();
    _pos = 0;
    _savedPos = 0;
  }

  /// コマンドを実行して履歴へ積む。失敗時は状態を戻して [CommandException] を再送出する。
  void execute(ModelCommand cmd, {bool journal = true}) {
    final before = _take(model);
    try {
      cmd.apply(context);
    } catch (e) {
      // 失敗時は元に戻す。
      final after = _take(model);
      final d = StateDelta.diff(after, before);
      _restore(model, d.after);
      rethrow;
    }
    final after = _take(model);
    final delta = StateDelta.diff(before, after);
    if (delta.isEmpty) return;
    if (_savedPos != null && _savedPos! > _pos) _savedPos = null;
    _entries.removeRange(_pos, _entries.length);
    _entries.add(HistoryEntry(cmd, delta));
    _pos++;
    if (_entries.length > limit) {
      final drop = _entries.length - limit;
      _entries.removeRange(0, drop);
      _pos -= drop;
      if (_savedPos != null) {
        _savedPos = _savedPos! - drop;
        if (_savedPos! < 0) _savedPos = null;
      }
    }
    _revision++;
    if (journal) onJournal?.call({'op': 'exec', 'cmd': cmd.toJson()});
  }

  void undo({bool journal = true}) {
    if (!canUndo) return;
    _restore(model, _entries[--_pos].delta.before);
    _revision++;
    if (journal) onJournal?.call({'op': 'undo'});
  }

  void redo({bool journal = true}) {
    if (!canRedo) return;
    _restore(model, _entries[_pos++].delta.after);
    _revision++;
    if (journal) onJournal?.call({'op': 'redo'});
  }
}

/// ダイアログで採番したIDとの衝突を避けるため、`nextId` を引き上げる。
/// キャッシュの再生では、コマンドの引数に含まれるIDより小さい `nextId` から再開しないようにする。
void bumpNextId(ErModel m, Iterable<int> ids) {
  for (final id in ids) {
    if (id >= m.nextId) m.nextId = id + 1;
  }
}
