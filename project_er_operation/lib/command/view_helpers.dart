import '../model/model.dart';

/// 結合ビューの定義の補助(6.6-3)。純Dartで、ダイアログとテストから使う。

/// ソースのエイリアス(既定は物理名。重複する場合は連番)。大文字小文字を区別せず重複を避ける。
String uniqueAlias(String base, Iterable<String> used) {
  final u = used.map((e) => e.toLowerCase()).toSet();
  final b = base.isEmpty ? 't' : base;
  if (!u.contains(b.toLowerCase())) return b;
  var n = 2;
  while (u.contains('${b}_$n'.toLowerCase())) {
    n++;
  }
  return '${b}_$n';
}

/// 新しいソースを追加するときの結合条件の初期値を、既存のリレーションシップから提案する(6.6-3-5)。
/// 前のソースのうち、リレーションシップで結ばれている最初のものについて、
/// 親の列と子の列の対応を (前のソースの列, 新しいソースの列) として返す。提案は編集できる。
List<JoinOn> suggestJoinConditions(
  ErModel model,
  List<ViewSource> previous,
  ViewSource added,
) {
  for (final prev in previous) {
    for (final r in model.relationships) {
      final prevIsParent = r.parentId == prev.entityId && r.childId == added.entityId;
      final prevIsChild = r.childId == prev.entityId && r.parentId == added.entityId;
      if (!prevIsParent && !prevIsChild) continue;
      return [
        for (final p in r.columnPairs)
          JoinOn(
            leftAlias: prev.alias,
            leftColumnId: prevIsParent ? p.parentColumnId : p.childColumnId,
            rightColumnId: prevIsParent ? p.childColumnId : p.parentColumnId,
          ),
      ];
    }
  }
  return [];
}

/// 出力列名の重複を避けた名前(既定は元の列の物理名。重複するときはエイリアスを前に付ける)。
String uniqueOutputName(String physical, String alias, Iterable<String> used) {
  final u = used.map((e) => e.toLowerCase()).toSet();
  if (!u.contains(physical.toLowerCase())) return physical;
  final withAlias = '${alias}_$physical';
  if (!u.contains(withAlias.toLowerCase())) return withAlias;
  var n = 2;
  while (u.contains('${withAlias}_$n'.toLowerCase())) {
    n++;
  }
  return '${withAlias}_$n';
}

/// エイリアスの変更を、結合条件と出力列へ反映する。
void renameAlias(ViewJoinDef j, String from, String to) {
  for (final s in j.sources) {
    for (final o in s.on) {
      if (o.leftAlias == from) o.leftAlias = to;
    }
  }
  for (final c in j.columns) {
    if (c.alias == from) c.alias = to;
  }
}

/// ソースを削除する。そのソースを使う結合条件(左の列)と出力列も削除する。
void removeSource(ViewJoinDef j, String alias) {
  j.sources.removeWhere((s) => s.alias == alias);
  for (final s in j.sources) {
    s.on.removeWhere((o) => o.leftAlias == alias);
  }
  j.columns.removeWhere((c) => c.alias == alias);
}

/// ソースのテーブルを変更する。そのソース自身の結合条件、それを左に使う結合条件、出力列を取り除く。
void changeSourceEntity(ViewJoinDef j, ViewSource s, int entityId) {
  s.entityId = entityId;
  s.on.clear();
  for (final o in j.sources) {
    o.on.removeWhere((x) => x.leftAlias == s.alias);
  }
  j.columns.removeWhere((c) => c.alias == s.alias);
}

/// 結合ビューの定義の不備(生成前検証 9.5 と同じ観点)。空なら問題なし。
List<String> joinViewProblems(ErModel m, ViewEntity v, {required RegExp nameFormat, int? selfId}) {
  final out = <String>[];
  if (v.physicalName.isEmpty) {
    out.add('物理名は必須です');
  } else if (!nameFormat.hasMatch(v.physicalName)) {
    out.add('物理名の形式に一致しません');
  } else if (m.entities.any((e) => e.id != selfId && e.physicalName.toLowerCase() == v.physicalName.toLowerCase())) {
    out.add('同じ物理名のエンティティが存在します');
  }
  final j = v.join;
  if (j.sources.isEmpty) out.add('ソースを1つ以上選択してください');
  final aliases = <String>{};
  for (var i = 0; i < j.sources.length; i++) {
    final s = j.sources[i];
    if (s.alias.isEmpty || !aliases.add(s.alias.toLowerCase())) {
      out.add('エイリアス「${s.alias}」が空または重複しています');
    }
    final t = m.tableById(s.entityId);
    if (t == null) {
      out.add('ソース「${s.alias}」のテーブルが存在しません');
      continue;
    }
    if (i > 0 && s.on.isEmpty) out.add('「${s.alias}」の結合条件がありません');
    for (final o in s.on) {
      final left = j.sources.where((x) => x.alias == o.leftAlias).firstOrNull;
      final lt = left == null ? null : m.tableById(left.entityId);
      if (lt == null || m.findExpandedColumn(lt, o.leftColumnId) == null || m.findExpandedColumn(t, o.rightColumnId) == null) {
        out.add('「${s.alias}」の結合条件の列が不正です');
      }
    }
  }
  if (j.columns.isEmpty) out.add('出力列を1つ以上選択してください');
  final names = <String>{};
  for (final c in j.columns) {
    final src = j.sources.where((x) => x.alias == c.alias).firstOrNull;
    final t = src == null ? null : m.tableById(src.entityId);
    final col = t == null ? null : m.findExpandedColumn(t, c.columnId);
    if (col == null) {
      out.add('出力列「${c.name}」の列が存在しません');
      continue;
    }
    final name = c.name.isNotEmpty ? c.name : col.column.physicalName;
    if (!nameFormat.hasMatch(name)) out.add('出力列名「$name」の形式が不正です');
    if (!names.add(name.toLowerCase())) out.add('出力列名「$name」が重複しています');
  }
  return out;
}
