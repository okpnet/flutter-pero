// PostgreSQL の DDL(SQLファイル)から `.pero` を生成する一回限りの変換ツール。
//
// 使い方:
//   dart run tool/sql_to_pero.dart <出力.pero> <findings出力.txt> <SQLファイル>...
//
// 取り込むもの: CREATE TABLE、主キー/ユニーク/外部キー(ALTER TABLE)、CREATE [UNIQUE] INDEX、
// CREATE FUNCTION(メソッド)、CREATE TRIGGER、CREATE VIEW(SQLビュー)、CREATE TYPE(複合型・列挙型)、COMMENT ON。
// 取り込めないものは findings に集計し、モデルの終了クエリにコメントとして残す。
import 'dart:io';

import 'package:project_er_operation/model/model.dart';
import 'package:project_er_operation/persistence/persistence.dart';
import 'package:project_er_operation/generation/validator.dart';

// ---------------------------------------------------------------- SQLの分割

class Stmt {
  Stmt(this.raw, this.clean, this.file, this.line);

  /// 元の文(コメントを含む)。末尾は `;`。
  final String raw;

  /// コメントを除いた文。
  final String clean;
  final String file;
  final int line;

  String? _head;

  /// 空白を1つにまとめた文(先頭判定用)。
  String get head => _head ??= clean.replaceAll(RegExp(r'\s+'), ' ').trim();
}

int _count(String s, String ch) {
  var n = 0;
  for (var i = 0; i < s.length; i++) {
    if (s[i] == ch) n++;
  }
  return n;
}

List<Stmt> splitSql(String text, String file) {
  final out = <Stmt>[];
  final raw = StringBuffer();
  final clean = StringBuffer();
  final dollar = RegExp(r'\$([A-Za-z_]\w*)?\$');
  final n = text.length;
  var i = 0;
  var line = 1;
  var startLine = 1;
  var started = false;

  void finish(bool semicolon) {
    final r = raw.toString().trim();
    final c = clean.toString().trim();
    if (r.isNotEmpty) out.add(Stmt(semicolon ? '$r;' : r, c, file, startLine));
    raw.clear();
    clean.clear();
    started = false;
  }

  while (i < n) {
    final c = text[i];
    if (!started) {
      if (c == '\n') {
        line++;
        i++;
        continue;
      }
      if (c.trim().isEmpty) {
        i++;
        continue;
      }
      if (c == r'\') {
        final e = text.indexOf('\n', i);
        i = e < 0 ? n : e;
        continue;
      }
      if (text.startsWith('--', i)) {
        final e = text.indexOf('\n', i);
        i = e < 0 ? n : e;
        continue;
      }
      if (text.startsWith('/*', i)) {
        var e = text.indexOf('*/', i + 2);
        e = e < 0 ? n : e + 2;
        line += _count(text.substring(i, e), '\n');
        i = e;
        continue;
      }
      started = true;
      startLine = line;
    }
    if (text.startsWith('--', i)) {
      var e = text.indexOf('\n', i);
      if (e < 0) e = n;
      raw.write(text.substring(i, e));
      i = e;
      continue;
    }
    if (text.startsWith('/*', i)) {
      var e = text.indexOf('*/', i + 2);
      e = e < 0 ? n : e + 2;
      final seg = text.substring(i, e);
      raw.write(seg);
      clean.write(' ');
      line += _count(seg, '\n');
      i = e;
      continue;
    }
    if (c == "'" || c == '"') {
      var j = i + 1;
      while (j < n) {
        if (text[j] == c) {
          if (j + 1 < n && text[j + 1] == c) {
            j += 2;
            continue;
          }
          break;
        }
        j++;
      }
      final e = j < n ? j + 1 : n;
      final seg = text.substring(i, e);
      raw.write(seg);
      clean.write(seg);
      line += _count(seg, '\n');
      i = e;
      continue;
    }
    if (c == r'$') {
      final m = dollar.matchAsPrefix(text, i);
      if (m != null) {
        final tag = m.group(0)!;
        var end = text.indexOf(tag, i + tag.length);
        end = end < 0 ? n : end + tag.length;
        final seg = text.substring(i, end);
        raw.write(seg);
        clean.write(seg);
        line += _count(seg, '\n');
        i = end;
        continue;
      }
    }
    if (c == ';') {
      finish(true);
      i++;
      continue;
    }
    if (c == '\n') line++;
    raw.write(c);
    clean.write(c);
    i++;
  }
  if (started) finish(false);
  return out;
}

// ---------------------------------------------------------------- 字句の補助

/// 最上位のカンマで分割する(括弧と引用符の内側は分割しない)。
List<String> splitTop(String s) {
  final out = <String>[];
  var depth = 0;
  var start = 0;
  for (var i = 0; i < s.length; i++) {
    final c = s[i];
    if (c == "'" || c == '"') {
      i++;
      while (i < s.length && s[i] != c) {
        i++;
      }
    } else if (c == '(') {
      depth++;
    } else if (c == ')') {
      depth--;
    } else if (c == ',' && depth == 0) {
      out.add(s.substring(start, i));
      start = i + 1;
    }
  }
  out.add(s.substring(start));
  return out.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
}

/// 最初の `(` に対応する `)` までの内側を返す。見つからなければnull。
(String, int)? parenBody(String s, [int from = 0]) {
  final open = s.indexOf('(', from);
  if (open < 0) return null;
  var depth = 0;
  for (var i = open; i < s.length; i++) {
    final c = s[i];
    if (c == "'" || c == '"') {
      i++;
      while (i < s.length && s[i] != c) {
        i++;
      }
    } else if (c == '(') {
      depth++;
    } else if (c == ')') {
      depth--;
      if (depth == 0) return (s.substring(open + 1, i), i + 1);
    }
  }
  return null;
}

/// 識別子(スキーマ修飾は外す)。引用符なしは小文字にする(PostgreSQLの規則)。
String ident(String raw) {
  final parts = <String>[];
  final buf = StringBuffer();
  var quoted = false;
  for (var i = 0; i < raw.length; i++) {
    final c = raw[i];
    if (c == '"') {
      quoted = !quoted;
      buf.write(c);
    } else if (c == '.' && !quoted) {
      parts.add(buf.toString());
      buf.clear();
    } else {
      buf.write(c);
    }
  }
  parts.add(buf.toString());
  return _unq(parts.last.trim());
}

/// 修飾名を各要素に分けて返す(例 tests.t.c → [tests, t, c])。
List<String> identParts(String raw) {
  final parts = <String>[];
  final buf = StringBuffer();
  var quoted = false;
  for (var i = 0; i < raw.length; i++) {
    final c = raw[i];
    if (c == '"') {
      quoted = !quoted;
      buf.write(c);
    } else if (c == '.' && !quoted) {
      parts.add(buf.toString());
      buf.clear();
    } else {
      buf.write(c);
    }
  }
  parts.add(buf.toString());
  return parts.map((p) => _unq(p.trim())).toList();
}

String _unq(String s) =>
    s.startsWith('"') && s.endsWith('"') && s.length >= 2 ? s.substring(1, s.length - 1) : s.toLowerCase();

String? parseSqlString(String s) {
  final m = RegExp(r"^'((?:[^']|'')*)'$", dotAll: true).firstMatch(s.trim());
  return m?.group(1)!.replaceAll("''", "'");
}

// ---------------------------------------------------------------- 変換

/// SQLの文字列リテラル('...' または E'...')を値に直す。
String? parseSqlStringE(String s) {
  final t = s.trim();
  final isE = t.startsWith('e') || t.startsWith('E');
  final v = parseSqlString(isE ? t.substring(1) : t);
  if (v == null || !isE) return v;
  final out = StringBuffer();
  for (var i = 0; i < v.length; i++) {
    final c = v[i];
    if (c == r'\' && i + 1 < v.length) {
      final n = v[++i];
      out.write(switch (n) { 'n' => '\n', 't' => '\t', 'r' => '\r', _ => n });
    } else {
      out.write(c);
    }
  }
  return out.toString();
}

class Findings {
  final Map<String, List<String>> items = {};
  void add(String category, String detail) => (items[category] ??= []).add(detail);
  int count(String category) => items[category]?.length ?? 0;
}

class TypeSpec {
  TypeSpec(this.id, {this.length, this.precision, this.scale});
  final String id;
  final int? length;
  final int? precision;
  final int? scale;
}

class Importer {
  Importer() : model = ErModel.empty(postPath: '');

  final ErModel model;
  final Findings f = Findings();
  final Map<String, TableEntity> tables = {};
  final Map<String, ViewEntity> views = {};
  final Map<String, MethodDef> methods = {};
  final Map<String, String> methodSignatures = {};
  final Map<String, MethodDef> defaultMethods = {};
  final Map<String, DataType> customTypes = {};
  final Map<String, DataType> userTypes = {};
  final Map<String, int> otherKinds = {};

  /// 取り込めなかった要素(生成SQLの最後にコメントとして出力する)。
  final List<String> unimported = [];

  final List<Stmt> alters = [];
  final List<Stmt> indexes = [];
  final List<Stmt> triggers = [];
  final List<Stmt> comments = [];

  // ---------- 取り込みの入口

  void run(List<Stmt> stmts) {
    // 型を参照する列より先に、ユーザー定義型を読む。
    for (final s in stmts) {
      if (RegExp(r'^create type ', caseSensitive: false).hasMatch(s.head)) _createType(s);
    }
    for (final s in stmts) {
      _dispatch(s);
    }
    _applyAlters();
    _applyIndexes();
    _applyTriggers();
    _applyComments();
    _finish();
  }

  void _other(String key) => otherKinds[key] = (otherKinds[key] ?? 0) + 1;

  void _skip(String category, String detail) {
    f.add(category, detail);
    unimported.add('$category: $detail');
  }

  void _dispatch(Stmt s) {
    final h = s.head;
    final l = h.length > 200 ? h.substring(0, 200).toLowerCase() : h.toLowerCase();
    if (RegExp(r'^create (or replace )?function ').hasMatch(l)) {
      _function(s);
    } else if (RegExp(r'^create (temp |temporary )').hasMatch(l)) {
      _other('CREATE TEMP TABLE');
    } else if (RegExp(r'^create (unlogged )?table ').hasMatch(l)) {
      _table(s);
    } else if (RegExp(r'^create (or replace )?(temp |temporary |recursive )?(materialized )?view ').hasMatch(l)) {
      _view(s);
    } else if (l.startsWith('create type ')) {
      // 先に読み込み済み
    } else if (RegExp(r'^create (unique )?index ').hasMatch(l)) {
      indexes.add(s);
    } else if (RegExp(r'^create (or replace )?(constraint )?trigger ').hasMatch(l)) {
      triggers.add(s);
    } else if (l.startsWith('alter table ')) {
      alters.add(s);
    } else if (l.startsWith('comment on ')) {
      comments.add(s);
    } else {
      final words = l.split(' ');
      _other(words.take(words[0] == 'create' || words[0] == 'drop' || words[0] == 'comment' ? 3 : 2).join(' ').toUpperCase());
    }
  }

  // ---------- 型

  DataType _custom(String raw) {
    final key = raw.toLowerCase();
    return customTypes.putIfAbsent(key, () {
      final id = 'custom_${customTypes.length + userTypes.length + 1}';
      f.add('カスタム型を自動追加', '$raw(→ $id)');
      return DataType(
        id: id,
        displayName: raw,
        category: TypeCategory.string,
        physical: {
          DbKind.postgresql: raw,
          DbKind.mysql: 'TEXT',
          DbKind.sqlserver: 'varchar(max)',
          DbKind.sqlite: 'TEXT',
        },
      );
    });
  }

  TypeSpec _type(String raw) {
    final t = raw.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
    final user = userTypes[ident(t)];
    if (user != null) return TypeSpec(user.id);
    final m = RegExp(r'^([a-z ]+?)\s*(?:\((\d+)(?:\s*,\s*(\d+))?\))?$').firstMatch(t);
    if (m == null) return TypeSpec(_custom(raw).id);
    final base = m.group(1)!;
    final a = m.group(2) == null ? null : int.parse(m.group(2)!);
    final b = m.group(3) == null ? null : int.parse(m.group(3)!);
    switch (base) {
      case 'uuid':
        return TypeSpec('uuid');
      case 'timestamp':
      case 'timestamp without time zone':
        return TypeSpec('timestamp');
      case 'timestamptz':
      case 'timestamp with time zone':
        return TypeSpec('timestamptz');
      case 'boolean':
      case 'bool':
        return TypeSpec('boolean');
      case 'varchar':
      case 'character varying':
        if (a == null) return TypeSpec('varchar_nolen'); // 長さなし(6.3)
        return TypeSpec('varchar', length: a);
      case 'char':
      case 'character':
        return TypeSpec('char', length: a ?? 1);
      case 'integer':
      case 'int':
      case 'int4':
        return TypeSpec('integer');
      case 'smallint':
      case 'int2':
        return TypeSpec('smallint');
      case 'bigint':
      case 'int8':
        return TypeSpec('bigint');
      case 'decimal':
      case 'numeric':
        if (a == null) {
          f.add('精度なしの numeric', '$raw → numeric(18,2)');
          return TypeSpec('numeric', precision: 18, scale: 2);
        }
        return TypeSpec('numeric', precision: a, scale: b ?? 0);
      case 'real':
      case 'float4':
        return TypeSpec('real');
      case 'double precision':
      case 'float8':
        return TypeSpec('double');
      case 'date':
        return TypeSpec('date');
      case 'time':
      case 'time without time zone':
        return TypeSpec('time');
      case 'interval':
        return TypeSpec('interval');
      case 'text':
        return TypeSpec('text');
      case 'json':
        return TypeSpec('json');
      case 'jsonb':
        return TypeSpec('jsonb');
      case 'bytea':
        return TypeSpec('bytea');
      case 'serial':
      case 'bigserial':
      case 'smallserial':
        f.add('serial 型', '$raw → auto');
        return TypeSpec('auto');
    }
    return TypeSpec(_custom(raw).id);
  }

  /// CREATE TYPE ... AS (...) / AS ENUM (...)(ユーザー定義型。6.3)。
  void _createType(Stmt s) {
    final m = RegExp(r'^\s*create\s+type\s+([\w."]+)\s+as\s+(enum\s*)?\((.*)\)\s*$',
            caseSensitive: false, dotAll: true)
        .firstMatch(s.clean);
    if (m == null) {
      _skip('解析できない CREATE TYPE', '${s.file}:${s.line}');
      return;
    }
    final name = ident(m.group(1)!);
    final isEnum = m.group(2) != null;
    final id = 'custom_${customTypes.length + userTypes.length + 1}';
    final t = DataType(
      id: id,
      displayName: name,
      physical: {DbKind.postgresql: name, DbKind.mysql: '', DbKind.sqlserver: '', DbKind.sqlite: ''},
      kind: isEnum ? TypeKind.enumeration : TypeKind.composite,
    );
    userTypes[name] = t;
    for (final item in splitTop(m.group(3)!)) {
      if (isEnum) {
        final v = parseSqlStringE(item);
        if (v != null) t.enumValues.add(v);
        continue;
      }
      final fm = RegExp(r'^("[^"]+"|\w+)\s+(.*)$', dotAll: true).firstMatch(item);
      if (fm == null) {
        f.add('解析できない複合型の項目', '$name: $item');
        continue;
      }
      final spec = _type(fm.group(2)!);
      t.fields.add(TypeField(
          name: ident(fm.group(1)!),
          typeId: spec.id,
          length: spec.length,
          precision: spec.precision,
          scale: spec.scale));
    }
  }

  // ---------- デフォルト

  MethodDef _defaultMethod(String name, String call) {
    return defaultMethods.putIfAbsent(call, () {
      var unique = name;
      var n = 2;
      while (methods.containsKey(unique) || model.methods.any((m) => m.name == unique)) {
        unique = '${name}_$n';
        n++;
      }
      final m = MethodDef(
        id: model.allocateId(),
        kind: MethodKind.function,
        name: unique,
        external: true,
        call: {for (final d in DbKind.values) d: d == DbKind.postgresql ? call : ''},
      );
      model.methods.add(m);
      return m;
    });
  }

  void _setDefault(ColumnDef c, String expr, String where) {
    final e = expr.trim();
    final cat = (model.typeById(c.typeId) ?? userTypes.values.followedBy(customTypes.values).firstWhere((t) => t.id == c.typeId))
        .category;
    if (e.isEmpty || e.toLowerCase() == 'null') return;
    final str = RegExp(r"^('(?:[^']|'')*')(?:::[\w ]+)?$").firstMatch(e);
    if (str != null) {
      final v = parseSqlString(str.group(1)!)!;
      if (v.isEmpty) {
        // 空文字は標準メソッド empty_string で表す(6.2-4)。
        c.defaultKind = DefaultKind.method;
        c.defaultMethodId = model.methods.firstWhere((m) => m.name == emptyStringMethodName).id;
        return;
      }
      c.defaultKind = DefaultKind.value;
      if (cat == TypeCategory.boolean) {
        final lv = v.toLowerCase();
        c.defaultValue = (lv == 't' || lv == 'true' || lv == '1') ? 'true' : 'false';
      } else {
        c.defaultValue = v;
      }
      return;
    }
    if (RegExp(r'^-?\d+(\.\d+)?$').hasMatch(e) || RegExp(r'^(true|false)$', caseSensitive: false).hasMatch(e)) {
      c.defaultKind = DefaultKind.value;
      c.defaultValue = e.toLowerCase();
      return;
    }
    final fn = RegExp(r'^(\w+)\(\)$').firstMatch(e);
    if (fn != null) {
      c.defaultKind = DefaultKind.method;
      c.defaultMethodId = _defaultMethod(fn.group(1)!.toLowerCase(), e).id;
      return;
    }
    c.defaultKind = DefaultKind.expression;
    c.defaultExpression = e;
  }

  // ---------- CREATE TABLE

  void _table(Stmt s) {
    final m = RegExp(r'^\s*create\s+(?:unlogged\s+)?table\s+(?:if\s+not\s+exists\s+)?([\w."]+)', caseSensitive: false)
        .firstMatch(s.clean);
    if (m == null) {
      _skip('解析できない文', 'CREATE TABLE ${s.file}:${s.line}');
      return;
    }
    final name = ident(m.group(1)!);
    final body = parenBody(s.clean, m.end);
    if (body == null) {
      _skip('解析できない文', 'CREATE TABLE $name ${s.file}:${s.line}');
      return;
    }
    if (tables.containsKey(name)) {
      _skip('テーブルの重複定義(後者を無視)', '$name ${s.file}:${s.line}');
      return;
    }
    final t = TableEntity(id: model.allocateId(), physicalName: name);
    final tail = s.clean.substring(body.$2).trim();
    if (tail.isNotEmpty) _skip('テーブル定義の末尾句', '$name: $tail');
    for (final item in splitTop(body.$1)) {
      final lower = item.toLowerCase();
      if (RegExp(r'^(constraint|primary|unique|foreign|check|exclude|like)\b').hasMatch(lower)) {
        _skip('テーブル内の制約句', '$name: $item');
        continue;
      }
      _column(t, item);
    }
    tables[name] = t;
    model.entities.add(t);
  }

  ColumnDef? _column(TableEntity t, String item) {
    final m = RegExp(r'^("[^"]+"|\w+)\s+(.*)$', dotAll: true).firstMatch(item);
    if (m == null) {
      _skip('解析できない列', '${t.physicalName}: $item');
      return null;
    }
    final cname = ident(m.group(1)!);
    final rest = m.group(2)!;
    final kw = RegExp(
            r'\b(default|not\s+null|null|primary\s+key|references|check|unique|constraint|generated|collate)\b',
            caseSensitive: false)
        .firstMatch(rest);
    final typeText = (kw == null ? rest : rest.substring(0, kw.start)).trim();
    final after = kw == null ? '' : rest.substring(kw.start);
    final spec = _type(typeText);
    final c = ColumnDef(
      id: model.allocateId(),
      physicalName: cname,
      typeId: spec.id,
      length: spec.length,
      precision: spec.precision,
      scale: spec.scale,
      notNull: RegExp(r'\bnot\s+null\b', caseSensitive: false).hasMatch(after),
    );
    final d = RegExp(r'\bdefault\s+(.*?)(?=\s+(?:not\s+null|null|primary\s+key|references|check|unique|constraint)\b|$)',
            caseSensitive: false, dotAll: true)
        .firstMatch(after);
    if (RegExp(r'\b(primary\s+key|references|check|unique|generated)\b', caseSensitive: false).hasMatch(after)) {
      _skip('列内の制約句', '${t.physicalName}.$cname: $after');
    }
    if (spec.id == 'auto') {
      // 自動採番型はデフォルトを持てない(6.2-4)。
    } else if (d != null) {
      _setDefault(c, d.group(1)!, '${t.physicalName}.$cname');
    }
    t.columns.add(c);
    return c;
  }

  // ---------- CREATE VIEW

  void _view(Stmt s) {
    final m = RegExp(r'^\s*create\s+(?:or\s+replace\s+)?view\s+([\w."]+)\s+as\b', caseSensitive: false)
        .firstMatch(s.raw);
    if (m == null) {
      _skip('解析できない CREATE VIEW', '${s.file}:${s.line}');
      return;
    }
    final name = ident(m.group(1)!);
    final sql = s.raw.substring(m.end).replaceAll(RegExp(r'[\s;]+$'), '').trim();
    final old = views[name];
    if (old != null) {
      old.sql.sql = sql; // CREATE OR REPLACE VIEW
      return;
    }
    final v = ViewEntity(
      id: model.allocateId(),
      physicalName: name,
      viewType: ViewType.sql,
      sql: ViewSqlDef(sql: sql),
    );
    views[name] = v;
    model.entities.add(v);
  }

  // ---------- CREATE FUNCTION

  void _function(Stmt s) {
    final h = s.head;
    final m = RegExp(
            r'^create (?:or replace )?function ([\w."]+)\s*\((.*?)\)\s*(?:returns\s+([\w."]+))?\s*(?:as|language|stable|volatile|immutable|security|cost|strict|called|returns)\b',
            caseSensitive: false)
        .firstMatch(h);
    if (m == null) {
      _skip('解析できない文', 'CREATE FUNCTION ${s.file}:${s.line}');
      return;
    }
    final name = ident(m.group(1)!);
    final sig = m.group(2)!.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    final isTrigger = (m.group(3) ?? '').toLowerCase() == 'trigger';
    final old = methods[name];
    if (old != null) {
      if (methodSignatures[name] != sig) {
        _skip('同名の関数(引数違い)', '$name($sig) ${s.file}:${s.line}(先に定義された $name(${methodSignatures[name]}) を残した)');
        return;
      }
      old.bodies[DbKind.postgresql] = s.raw;
      return;
    }
    final mt = MethodDef(
      id: model.allocateId(),
      kind: isTrigger ? MethodKind.trigger : MethodKind.function,
      name: name,
      bodies: {for (final d in DbKind.values) d: d == DbKind.postgresql ? s.raw : ''},
    );
    methods[name] = mt;
    methodSignatures[name] = sig;
    model.methods.add(mt);
  }

  // ---------- ALTER TABLE

  List<ColumnDef>? _cols(TableEntity t, String list, String where) {
    final out = <ColumnDef>[];
    for (final part in splitTop(list)) {
      final name = ident(part.split(RegExp(r'\s+')).first);
      final c = t.columns.where((x) => x.physicalName == name).firstOrNull;
      if (c == null) {
        f.add('列が見つからない', '$where: ${t.physicalName}.$name');
        return null;
      }
      out.add(c);
    }
    return out;
  }

  void _applyAlters() {
    final pk = <Stmt>[];
    final rest = <Stmt>[];
    for (final s in alters) {
      (RegExp(r'primary key', caseSensitive: false).hasMatch(s.head) ? pk : rest).add(s);
    }
    for (final s in [...pk, ...rest]) {
      _alter(s);
    }
  }

  void _alter(Stmt s) {
    final h = s.head;
    final where = '${s.file}:${s.line}';
    final m = RegExp(r'^alter table (?:only )?(?:if exists )?([\w."]+) (.*)$', caseSensitive: false).firstMatch(h);
    if (m == null) {
      _skip('解析できない文', 'ALTER TABLE $where');
      return;
    }
    final tname = ident(m.group(1)!);
    final t = tables[tname];
    final rest = m.group(2)!;
    if (t == null) {
      _skip('対象テーブルが無い ALTER TABLE', '$tname $where');
      return;
    }
    final pkM = RegExp(r'^add (?:constraint [\w"]+ )?primary key ?\((.*?)\)', caseSensitive: false).firstMatch(rest);
    if (pkM != null) {
      final cols = _cols(t, pkM.group(1)!, where);
      if (cols == null) return;
      final ordered = t.columns.where(cols.contains).toList();
      if (ordered.map((c) => c.id).join(',') != cols.map((c) => c.id).join(',')) {
        f.add('主キーの列順がテーブルの列順と違う(列順に統一)', '$tname ${pkM.group(1)}');
      }
      for (final c in cols) {
        c.pk = true;
        c.notNull = true;
      }
      final cname = RegExp(r'^add constraint ([\w"]+)', caseSensitive: false).firstMatch(rest)?.group(1);
      if (cname != null) {
        pkNames.add((tname, ident(cname)));
      }
      return;
    }
    final uqM = RegExp(r'^add constraint ([\w"]+) unique\s*(nulls not distinct)?\s*\((.*?)\)\s*$', caseSensitive: false)
        .firstMatch(rest);
    if (uqM != null) {
      final cols = _cols(t, uqM.group(3)!, where);
      if (cols == null) return;
      t.uniques.add(ConstraintDef(
          id: model.allocateId(),
          nameMode: NameMode.manual,
          name: ident(uqM.group(1)!),
          columnIds: cols.map((c) => c.id).toList(),
          nullsNotDistinct: uqM.group(2) != null));
      return;
    }
    final fkM = RegExp(r'^add constraint ([\w"]+) foreign key ?\((.*?)\) references ([\w."]+) ?\((.*?)\)(.*)$',
            caseSensitive: false)
        .firstMatch(rest);
    if (fkM != null) {
      _foreignKey(t, fkM, where);
      return;
    }
    final ckM = RegExp(r'^add constraint ([\w"]+) check\s*(\(.*)$', caseSensitive: false, dotAll: true).firstMatch(rest);
    if (ckM != null) {
      final body = parenBody(ckM.group(2)!);
      if (body != null) {
        t.checks.add(CheckDef(
            id: model.allocateId(),
            nameMode: NameMode.manual,
            name: ident(ckM.group(1)!),
            expression: body.$1.trim()));
        return;
      }
    }
    _skip('未対応の ALTER TABLE', '$where $h');
  }

  /// (テーブル, 主キー制約名)。設定のプリフィクス/サフィックスの案内に使う。
  final List<(String, String)> pkNames = [];

  void _foreignKey(TableEntity child, RegExpMatch m, String where) {
    final name = ident(m.group(1)!);
    final parent = tables[ident(m.group(3)!)];
    if (parent == null) {
      _skip('親テーブルが無い外部キー', '$name → ${m.group(3)} $where');
      return;
    }
    final cc = _cols(child, m.group(2)!, where);
    final pc = _cols(parent, m.group(4)!, where);
    if (cc == null || pc == null) return;
    if (cc.length != pc.length) {
      _skip('外部キーの列数が合わない', '$name $where');
      return;
    }
    final tail = (m.group(5) ?? '').toLowerCase();
    RefAction action(String kind) {
      final a = RegExp('on $kind (no action|restrict|cascade|set null|set default)').firstMatch(tail)?.group(1);
      return switch (a) {
        'no action' => RefAction.noAction,
        'restrict' => RefAction.restrict,
        'cascade' => RefAction.cascade,
        'set null' => RefAction.setNull,
        'set default' => RefAction.setDefault,
        _ => RefAction.none,
      };
    }

    final childPk = child.columns.where((c) => c.pk).map((c) => c.id).toSet();
    final dependency = parent != child && childPk.isNotEmpty && cc.every((c) => childPk.contains(c.id));
    final deferrable = RegExp(r'(?<!not )deferrable').hasMatch(tail)
        ? (tail.contains('initially deferred') ? Deferrable.deferred : Deferrable.immediate)
        : Deferrable.none;
    model.relationships.add(Relationship(
      id: model.allocateId(),
      parentId: parent.id,
      childId: child.id,
      columnPairs: [
        for (var i = 0; i < cc.length; i++) ColumnPair(parentColumnId: pc[i].id, childColumnId: cc[i].id)
      ],
      dependency: dependency,
      nameMode: NameMode.manual,
      name: name,
      onDelete: action('delete'),
      onUpdate: action('update'),
      deferrable: deferrable,
    ));
  }

  // ---------- CREATE INDEX

  void _applyIndexes() {
    final re = RegExp(
        r'^create (unique )?index (?:concurrently )?(?:if not exists )?([\w."]+) on (?:only )?([\w."]+)\s*(?:using (\w+))?\s*\((.*)\)(.*)$',
        caseSensitive: false);
    for (final s in indexes) {
      final where = '${s.file}:${s.line}';
      final m = re.firstMatch(s.head);
      if (m == null) {
        _skip('解析できない CREATE INDEX', '$where ${s.head}');
        continue;
      }
      final unique = m.group(1) != null;
      final name = ident(m.group(2)!);
      final t = tables[ident(m.group(3)!)];
      if (t == null) {
        _skip('対象テーブルが無い CREATE INDEX', '$name $where');
        continue;
      }
      final simple = (m.group(4) == null || m.group(4)!.toLowerCase() == 'btree') &&
          (m.group(6) ?? '').trim().isEmpty &&
          splitTop(m.group(5)!).every((p) => RegExp(r'^("[^"]+"|\w+)(\s+(asc|desc))?$', caseSensitive: false).hasMatch(p));
      final cols = simple ? _cols(t, m.group(5)!, where) : null;
      if (cols == null) {
        _skip('式・部分・特殊なインデックス', '$name: ${s.head}');
        continue;
      }
      final ids = cols.map((c) => c.id).toList();
      final pkIds = t.columns.where((c) => c.pk).map((c) => c.id).toList();
      if (unique && pkIds.length == ids.length && pkIds.toSet().containsAll(ids)) {
        _other('主キーと重複するユニークインデックス(取り込まない)');
        continue;
      }
      (unique ? t.uniques : t.indexes).add(ConstraintDef(
          id: model.allocateId(), nameMode: NameMode.manual, name: name, columnIds: ids));
    }
  }

  // ---------- CREATE TRIGGER

  void _applyTriggers() {
    final re = RegExp(
        r'^create (?:or replace )?trigger ([\w"]+) (before|after|instead of) (.+?) on ([\w."]+)(.*?) execute (?:procedure|function) ([\w."]+)\s*\((.*)\)\s*$',
        caseSensitive: false);
    for (final s in triggers) {
      final where = '${s.file}:${s.line}';
      final m = re.firstMatch(s.head);
      if (m == null) {
        _skip('解析できないトリガー', '$where ${s.head}');
        continue;
      }
      final name = ident(m.group(1)!);
      final t = tables[ident(m.group(4)!)];
      final fn = methods[ident(m.group(6)!)];
      if (t == null || fn == null) {
        _skip('テーブルまたは関数が無いトリガー', '$name $where');
        continue;
      }
      if (m.group(2)!.toLowerCase() == 'instead of') {
        _skip('INSTEAD OF トリガー', name);
        continue;
      }
      final events = <TriggerEvent>[];
      var updateCols = <int>[];
      var bad = false;
      for (final e in m.group(3)!.toLowerCase().split(' or ')) {
        final et = e.trim();
        final w = et.split(' ').first;
        final ev = {'insert': TriggerEvent.insert, 'update': TriggerEvent.update, 'delete': TriggerEvent.delete}[w];
        if (ev == null) {
          _skip('未対応のトリガーイベント', '$name: $e');
          bad = true;
          break;
        }
        if (ev == TriggerEvent.update && et.startsWith('update of ')) {
          final cols = _cols(t, et.substring('update of '.length), where);
          if (cols == null) {
            bad = true;
            break;
          }
          updateCols = cols.map((c) => c.id).toList();
        }
        if (!events.contains(ev)) events.add(ev);
      }
      if (bad || events.isEmpty) continue;
      final tail = m.group(5)!.trim();
      final whenM = RegExp(r'when ?\((.*)\)\s*$', caseSensitive: false).firstMatch(tail);
      final statement = RegExp(r'for each statement', caseSensitive: false).hasMatch(tail);
      final def = TriggerDef(
        id: model.allocateId(),
        source: TriggerSource.public,
        methodId: fn.id,
        nameMode: NameMode.manual,
        name: name,
        timing: m.group(2)!.toLowerCase() == 'after' ? TriggerTiming.after : TriggerTiming.before,
        events: events,
        forEach: statement ? TriggerForEach.statement : TriggerForEach.row,
        when: whenM?.group(1) ?? '',
        args: m.group(7)!.trim(),
        updateColumnIds: updateCols,
      );
      final at = t.triggers.indexWhere((x) => x.name == name);
      if (at >= 0) {
        t.triggers[at] = def;
      } else {
        t.triggers.add(def);
      }
    }
  }

  // ---------- COMMENT ON

  void _applyComments() {
    final re = RegExp(r"^\s*comment\s+on\s+(\w+)\s+(.+?)\s+is\s+(e?'(?:[^']|'')*'|null)\s*;?\s*$",
        caseSensitive: false, dotAll: true);
    for (final s in comments) {
      final m = re.firstMatch(s.clean);
      if (m == null) {
        _skip('解析できない COMMENT ON', '${s.file}:${s.line}');
        continue;
      }
      final kind = m.group(1)!.toLowerCase();
      final text = parseSqlStringE(m.group(3)!) ?? '';
      final target = m.group(2)!;
      switch (kind) {
        case 'table':
          final t = tables[identParts(target).last];
          if (t == null) continue;
          t.comment = text;
          t.logicalName = text;
        case 'column':
          final parts = identParts(target);
          if (parts.length < 2) continue;
          final t = tables[parts[parts.length - 2]];
          final c = t?.columns.where((x) => x.physicalName == parts.last).firstOrNull;
          if (c == null) {
            _skip('COMMENT ON COLUMN の対象が無い', target);
            continue;
          }
          c.comment = text;
          c.logicalName = text;
        case 'view':
          final v = views[identParts(target).last];
          if (v == null) continue;
          v.comment = text;
        case 'function':
          final open = target.indexOf('(');
          final name = ident(open < 0 ? target : target.substring(0, open));
          final fn = methods[name];
          if (fn == null) continue;
          fn.comment = text;
          fn.args = open < 0 ? '' : target.substring(open + 1, target.lastIndexOf(')'));
        case 'type':
          final t = userTypes[identParts(target).last];
          if (t == null) continue;
          t.comment = text;
        default:
          _skip('COMMENT ON ${kind.toUpperCase()}(置き場がない)', target);
      }
    }
  }

  // ---------- 仕上げ

  void _finish() {
    model.types.addAll(customTypes.values);
    model.types.addAll(userTypes.values);
    // ファンクションの依存テーブル(本体に現れるテーブル名)。ビューへの依存は表せないので記録する。
    for (final fn in methods.values.where((m) => m.kind == MethodKind.function)) {
      final words = RegExp(r'[a-z_][a-z0-9_]*')
          .allMatches((fn.bodies[DbKind.postgresql] ?? '').toLowerCase())
          .map((x) => x.group(0)!)
          .toSet();
      fn.dependsOnTableIds = [
        for (final t in tables.values) if (words.contains(t.physicalName)) t.id,
        for (final v in views.values) if (words.contains(v.physicalName)) v.id,
      ];
    }
    model.properties.outputFileName = 'pms_test';
    model.properties.schema = 'tests';
    model.properties.includeSchema = true;
    model.properties.startQuery = 'SET search_path TO tests, public;';
    final log = <String>[
      ...unimported,
      for (final e in otherKinds.entries) '取り込まない文: ${e.key} × ${e.value}',
    ];
    if (log.isNotEmpty) {
      model.properties.endQuery =
          ['-- [PERO 取り込みログ] 取り込めなかった要素', for (final l in log) '-- ${l.replaceAll('\n', ' ')}'].join('\n');
    }
    final d = model.diagrams.first;
    d.name = 'ダイアグラム1';
    for (final e in model.entities) {
      d.placements.add(Placement(entityId: e.id, x: 40, y: 40));
    }
    // 親のキー確認(外部キーの親列が主キーまたはユニークか)
    for (final r in model.relationships) {
      final p = model.tableById(r.parentId)!;
      final ids = r.columnPairs.map((x) => x.parentColumnId).toSet();
      bool same(Iterable<int> a) => a.length == ids.length && ids.containsAll(a);
      final ok = same(p.columns.where((c) => c.pk).map((c) => c.id)) || p.uniques.any((u) => same(u.columnIds));
      if (!ok) f.add('外部キーの親列が主キー/ユニークでない', '${model.foreignKeyName(r)}(親 ${p.physicalName})');
    }
    // 主キー制約名の案内
    final suffixes = {for (final (t, n) in pkNames) if (n.startsWith(t)) n.substring(t.length)};
    if (suffixes.isNotEmpty) {
      f.add('主キー制約名(設定の「主キー制約名のサフィックス」で合わせる)', suffixes.map((s) => '"$s"').join(', '));
    }
  }
}

Future<void> main(List<String> args) async {
  if (args.length < 3) {
    stderr.writeln('usage: dart run tool/sql_to_pero.dart <out.pero> <findings.txt> <sql>...');
    exit(2);
  }
  final stmts = <Stmt>[];
  for (final path in args.skip(2)) {
    stmts.addAll(splitSql(File(path).readAsStringSync(), path.split(RegExp(r'[\\/]')).last));
  }
  stderr.writeln('split: ${stmts.length} statements');
  final imp = Importer()..run(stmts);
  final model = imp.model;
  stderr.writeln('imported: ${model.entities.length} entities');

  final prep = PeroFile.prepare(model);
  stderr.writeln('prepared');
  final buf = StringBuffer();
  buf.writeln('statements: ${stmts.length}');
  buf.writeln('tables: ${model.tables.length}, columns: ${model.tables.fold<int>(0, (a, t) => a + t.columns.length)}');
  buf.writeln('views: ${model.views.length}');
  buf.writeln('relationships: ${model.relationships.length} (self-reference ${model.relationships.where((r) => r.parentId == r.childId).length}, deferrable ${model.relationships.where((r) => r.deferrable != Deferrable.none).length})');
  buf.writeln('methods: ${model.methods.length} (trigger ${model.methods.where((m) => m.kind == MethodKind.trigger).length}, external ${model.methods.where((m) => m.external).length}, with comment ${model.methods.where((m) => m.comment.isNotEmpty).length}, with dependsOn ${model.methods.where((m) => m.dependsOnTableIds.isNotEmpty).length})');
  buf.writeln('user types: ${model.types.where((t) => t.isUserDefined).length}');
  buf.writeln('table triggers: ${model.tables.fold<int>(0, (a, t) => a + t.triggers.length)} (with args ${model.tables.fold<int>(0, (a, t) => a + t.triggers.where((g) => g.args.isNotEmpty).length)}, update-of ${model.tables.fold<int>(0, (a, t) => a + t.triggers.where((g) => g.updateColumnIds.isNotEmpty).length)})');
  buf.writeln('indexes: ${model.tables.fold<int>(0, (a, t) => a + t.indexes.length)}, uniques: ${model.tables.fold<int>(0, (a, t) => a + t.uniques.length)} (nulls not distinct ${model.tables.fold<int>(0, (a, t) => a + t.uniques.where((u) => u.nullsNotDistinct).length)}), checks: ${model.tables.fold<int>(0, (a, t) => a + t.checks.length)}');
  buf.writeln('views with comment: ${model.views.where((v) => v.comment.isNotEmpty).length}');
  buf.writeln('integrity: ${prep.isOk ? 'ok' : prep.error}, repairs: ${prep.repairs.count}');
  for (final r in prep.repairs.items.take(30)) {
    buf.writeln('  repair: $r');
  }
  final v = ModelValidator(model, pkNaming: const PkNaming(suffix: '_pkc')).validate();
  buf.writeln('validation errors: ${v.errors.length}, warnings: ${v.warnings.length}');
  for (final e in v.errors.take(60)) {
    buf.writeln('  ERROR: ${e.message}');
  }
  for (final w in v.warnings.take(40)) {
    buf.writeln('  WARN: ${w.message}');
  }
  buf.writeln('\n--- other statements (not imported) ---');
  for (final e in imp.otherKinds.entries.toList()..sort((a, b) => b.value.compareTo(a.value))) {
    buf.writeln('${e.value}\t${e.key}');
  }
  buf.writeln('\n--- findings ---');
  for (final e in imp.f.items.entries) {
    buf.writeln('\n## ${e.key} (${e.value.length})');
    for (final d in e.value.take(15)) {
      buf.writeln('- $d');
    }
    if (e.value.length > 15) buf.writeln('- …ほか${e.value.length - 15}件');
  }
  File(args[1]).writeAsStringSync(buf.toString());

  if (!prep.isOk) {
    stderr.writeln('integrity failed');
    exit(1);
  }
  File(args[0]).writeAsBytesSync(prep.bytes!);
  stdout.writeln('written ${args[0]} (${prep.bytes!.length} bytes)');
}
