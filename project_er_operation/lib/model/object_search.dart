import 'entity.dart';
import 'enums.dart';
import 'er_model.dart';
import 'shared_resources.dart';

/// 検索の範囲(3.9)。
enum SearchScope {
  all('全て'),
  table('テーブル'),
  view('ビュー'),
  column('列'),
  function('関数'),
  trigger('トリガー'),
  comment('コメント');

  const SearchScope(this.label);
  final String label;
}

/// 検索条件(3.9)。大文字小文字は区別しない。
class SearchQuery {
  const SearchQuery({this.text = '', this.regex = false, this.scope = SearchScope.all});
  final String text;
  final bool regex;
  final SearchScope scope;

  SearchQuery copyWith({String? text, bool? regex, SearchScope? scope}) =>
      SearchQuery(text: text ?? this.text, regex: regex ?? this.regex, scope: scope ?? this.scope);

  bool get isEmpty => text.isEmpty;

  @override
  bool operator ==(Object other) =>
      other is SearchQuery && other.text == text && other.regex == regex && other.scope == scope;
  @override
  int get hashCode => Object.hash(text, regex, scope);
}

/// 検索のヒット(3.9)。親(テーブル、ビューなどの入れ子の外側)は薄く、子(列、関数の定義、トリガーの中のメソッドなど)は濃く表示する。
class SearchHighlights {
  const SearchHighlights({
    this.light = const {},
    this.strongHeaders = const {},
    this.strongRows = const {},
    this.invalidRegex = false,
    this.hitCount = 0,
  });

  static const none = SearchHighlights();

  /// 薄く表示するエンティティ(親)。
  final Set<int> light;

  /// ヘッダを濃く表示するエンティティ(エンティティ自身、またはトリガーがヒット)。
  final Set<int> strongHeaders;

  /// 濃く表示する列行(エンティティID → 列行の位置)。
  final Map<int, Set<int>> strongRows;

  /// 正規表現が不正で検索できない。
  final bool invalidRegex;

  /// ヒットしたオブジェクトの数(テーブル、ビュー、列、関数、トリガー、メソッド)。
  final int hitCount;

  bool get isEmpty => light.isEmpty && strongHeaders.isEmpty && strongRows.isEmpty;

  /// ヒットしたエンティティのID(ID昇順)。ヒットへの移動(3.9-16)に使う。
  List<int> get targets => ({...light, ...strongHeaders, ...strongRows.keys}.toList()..sort());
}

/// モデルの検索(純Dart)。
///
/// - テーブル/ビューの名前(論理名・物理名)がヒット: ヘッダを濃く、本体を薄く。
/// - 列がヒット: その列行を濃く、テーブル(親)を薄く。
/// - 関数がヒット: 使っている列行(デフォルトのメソッド)と関数ビューが表示先。名前のヒットは親を薄く、
///   定義(本体、呼出し式)のヒットは列行・ヘッダを濃くする。
/// - トリガーがヒット: トリガー自身(名前、条件、引数、入力の本体)はテーブルを薄く、
///   トリガーの中のメソッド(名前、本体)はテーブルのヘッダを濃くする。
/// - コメント: テーブル、ビュー、列のコメント。
SearchHighlights searchModel(ErModel m, SearchQuery q) {
  if (q.isEmpty) return SearchHighlights.none;
  RegExp? re;
  if (q.regex) {
    try {
      re = RegExp(q.text, caseSensitive: false);
    } on FormatException {
      return const SearchHighlights(invalidRegex: true);
    }
  }
  final needle = q.text.toLowerCase();
  bool hit(String s) => s.isNotEmpty && (re != null ? re.hasMatch(s) : s.toLowerCase().contains(needle));

  final light = <int>{};
  final strongHeaders = <int>{};
  final strongRows = <int, Set<int>>{};
  var count = 0;
  bool on(SearchScope s) => q.scope == SearchScope.all || q.scope == s;

  void row(int entityId, int index) => (strongRows[entityId] ??= {}).add(index);

  // テーブルとビュー
  for (final e in m.entities) {
    if (e is TableEntity) {
      if (on(SearchScope.table) && (hit(e.physicalName) || hit(e.logicalName))) {
        strongHeaders.add(e.id);
        light.add(e.id);
        count++;
      }
      if (on(SearchScope.comment) && hit(e.comment)) {
        strongHeaders.add(e.id);
        light.add(e.id);
        count++;
      }
      final cols = m.expand(e).columns;
      for (var i = 0; i < cols.length; i++) {
        final c = cols[i].column;
        var h = false;
        if (on(SearchScope.column) && (hit(c.physicalName) || hit(c.logicalName))) h = true;
        if (on(SearchScope.comment) && hit(c.comment)) h = true;
        if (h) {
          row(e.id, i);
          light.add(e.id);
          count++;
        }
      }
      if (on(SearchScope.trigger)) {
        for (final g in e.triggers) {
          final own = hit(m.triggerName(e, g)) || hit(g.when) || hit(g.args);
          final inner = g.source == TriggerSource.public
              ? _methodHit(m.methodById(g.methodId ?? -1), hit)
              : g.inlineBodies.values.any(hit);
          if (own) {
            light.add(e.id);
            count++;
          }
          if (inner) {
            light.add(e.id);
            strongHeaders.add(e.id);
            count++;
          }
        }
      }
    } else if (e is ViewEntity) {
      if (on(SearchScope.view) && (hit(e.physicalName) || hit(e.logicalName))) {
        strongHeaders.add(e.id);
        light.add(e.id);
        count++;
      }
      if (on(SearchScope.comment) && hit(e.comment)) {
        strongHeaders.add(e.id);
        light.add(e.id);
        count++;
      }
      if (on(SearchScope.column)) {
        final names = switch (e.viewType) {
          ViewType.function => [for (final c in e.function.columns) (c.name, c.logicalName)],
          ViewType.sql => [for (final c in e.sql.columns) (c.name, c.logicalName)],
          ViewType.join => [
              for (final c in e.join.columns)
                (c.name.isNotEmpty ? c.name : (m.anyColumnById(c.columnId)?.physicalName ?? ''), c.logicalName)
            ],
        };
        for (var i = 0; i < names.length; i++) {
          if (hit(names[i].$1) || hit(names[i].$2)) {
            row(e.id, i);
            light.add(e.id);
            count++;
          }
        }
      }
    }
  }

  // 関数(列のデフォルトのメソッド、関数ビューが使う)
  if (on(SearchScope.function)) {
    for (final f in m.methods.where((x) => x.kind == MethodKind.function)) {
      final nameHit = hit(f.name);
      final defHit = f.bodies.values.any(hit) || f.call.values.any(hit);
      if (!nameHit && !defHit) continue;
      count++;
      for (final t in m.tables) {
        final cols = m.expand(t).columns;
        for (var i = 0; i < cols.length; i++) {
          final c = cols[i].column;
          if (c.defaultKind == DefaultKind.method && c.defaultMethodId == f.id) {
            light.add(t.id);
            if (defHit) row(t.id, i);
          }
        }
      }
      for (final v in m.views) {
        if (v.viewType == ViewType.function && v.function.methodId == f.id) {
          light.add(v.id);
          if (defHit) strongHeaders.add(v.id);
        }
      }
    }
  }

  return SearchHighlights(light: light, strongHeaders: strongHeaders, strongRows: strongRows, hitCount: count);
}

bool _methodHit(MethodDef? m, bool Function(String) hit) {
  if (m == null) return false;
  return hit(m.name) || m.bodies.values.any(hit);
}
