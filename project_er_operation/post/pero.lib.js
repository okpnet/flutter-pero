// PERO ポストファイル用の共通ヘルパ(名前空間 `pero`)。
//
// アプリは、ポストファイルと同じフォルダに `pero.lib.js` があれば、ポストファイルの前に読み込む。
// ポストファイルからは `pero.xxx` として使える(エクスポート、インポートの両方)。
// 使い方は doc/contents/ポストファイルの書き方.md を参照。
//
// 構成
//   共通            pero.endSemi / pero.stripTrailing / pero.words
//   エクスポート    pero.dialect / pero.Output / pero.defaultSql
//   インポート      pero.splitSql / pero.splitTop / pero.parenBody / pero.ident / pero.identParts / pero.sqlString /
//                   pero.ImportResult
var pero = (function () {
  var P = { version: 1 };

  // ======================================================================== 共通

  /** 末尾の空白を除く。 */
  P.stripTrailing = function (s) { return String(s).replace(/\s+$/, ''); };

  /** 文の末尾に `;` が無ければ付ける。 */
  P.endSemi = function (s) {
    var t = P.stripTrailing(s);
    return /;$/.test(t) ? t : t + ';';
  };

  // ================================================================ エクスポート

  /**
   * 方言(識別子の引用、文字列リテラル、予約語)の部品を作る。
   * opts: { reserved: ['order', ...](小文字), quote: function(name)(識別子の引用), literal: function(s)(文字列リテラル) }
   * 戻り値: { q(name), qt(schema, name), list(names), lit(s) }
   *   q    識別子。小文字の英数字と _ だけで予約語でなければそのまま、それ以外は引用する。
   *   qt   スキーマ付きの名前(スキーマが空なら q と同じ)。
   *   list 名前の配列を `a, b` の形にする。
   *   lit  文字列リテラル。
   */
  P.dialect = function (opts) {
    opts = opts || {};
    var reserved = {};
    (opts.reserved || []).forEach(function (w) { reserved[String(w).toLowerCase()] = true; });
    var quote = opts.quote || function (n) { return '"' + String(n).replace(/"/g, '""') + '"'; };
    var literal = opts.literal || function (s) { return "'" + String(s).replace(/'/g, "''") + "'"; };
    var d = {};
    d.q = function (name) {
      if (/^[a-z_][a-z0-9_]*$/.test(name) && !reserved[name]) return name;
      return quote(name);
    };
    d.qt = function (schema, name) { return schema ? d.q(schema) + '.' + d.q(name) : d.q(name); };
    d.list = function (names) { return names.map(d.q).join(', '); };
    d.lit = literal;
    return d;
  };

  /**
   * 出力の組立。push した文を、空行で区切って1つの文字列にする。
   * 空の文(空白だけを含む)は無視する。末尾に改行を付ける。
   */
  P.Output = function () {
    var out = [];
    var o = {};
    o.push = function (s) {
      if (s === null || s === undefined) return o;
      var t = P.stripTrailing(String(s));
      if (t.replace(/\s+/g, '') !== '') out.push(t);
      return o;
    };
    o.pushAll = function (list) { list.forEach(o.push); return o; };
    o.toString = function () { return out.join('\n\n') + '\n'; };
    return o;
  };

  /**
   * 列のデフォルトを SQL の式にする。デフォルトなしのときは null。
   * c: 生成用JSONの列(c.default.kind / value / call / expression、c.typeCategory)。
   * d: P.dialect の戻り値。
   * 値は、typeCategory が number / boolean / auto のときそのまま、ほかは文字列リテラルにする。
   */
  P.defaultSql = function (c, d) {
    var x = c['default'];
    if (!x) return null;
    if (x.kind === 'method') return x.call;
    if (x.kind === 'expression') return x.expression;
    if (x.kind !== 'value') return null;
    switch (c.typeCategory) {
      case 'number':
      case 'boolean':
      case 'auto':
        return x.value;
      default:
        return d.lit(x.value);
    }
  };

  // ================================================================== インポート

  /**
   * SQLを文に分ける。`;` で区切り、引用符('...' "...")、ドル引用符($$...$$)、コメント(-- /* *\/)の中の `;` は区切りにしない。
   * 行頭の `\` で始まる行(psql のメタコマンド)は読み飛ばす。
   * 戻り値: [{ raw: コメントを含む文(末尾の `;` を含む), clean: コメントを除いた文(`;` を含まない), line: 開始行(1始まり) }]
   * opts.backslashEscapes: 文字列の中の `\` をエスケープとして扱う(MySQL など)。
   */
  P.splitSql = function (text, opts) {
    opts = opts || {};
    var n = text.length;
    // 行番号の表(各行の開始位置)
    var starts = [0];
    for (var p = text.indexOf('\n'); p >= 0; p = text.indexOf('\n', p + 1)) starts.push(p + 1);
    function lineAt(pos) {
      var lo = 0, hi = starts.length - 1;
      while (lo < hi) {
        var mid = (lo + hi + 1) >> 1;
        if (starts[mid] <= pos) lo = mid; else hi = mid - 1;
      }
      return lo + 1;
    }
    var R = /--|\/\*|'|"|\$(?:[A-Za-z_][A-Za-z_0-9]*)?\$|;/g;
    var out = [];
    var i = 0;
    var started = false, startPos = 0, cleanStart = 0, parts = [];

    function skipLine(from) { var e = text.indexOf('\n', from); return e < 0 ? n : e; }
    function skipBlock(from) { var e = text.indexOf('*/', from + 2); return e < 0 ? n : e + 2; }
    function skipQuoted(from, q, escapes) {
      var j = from + 1;
      while (j < n) {
        var c = text.charAt(j);
        if (escapes && c === '\\') { j += 2; continue; }
        if (c === q) {
          if (text.charAt(j + 1) === q) { j += 2; continue; }
          return j + 1;
        }
        j++;
      }
      return n;
    }

    while (i < n) {
      if (!started) {
        var c0 = text.charAt(i);
        if (c0 === ' ' || c0 === '\t' || c0 === '\r' || c0 === '\n') { i++; continue; }
        if (c0 === '\\') { i = skipLine(i); continue; }
        if (c0 === '-' && text.charAt(i + 1) === '-') { i = skipLine(i); continue; }
        if (c0 === '/' && text.charAt(i + 1) === '*') { i = skipBlock(i); continue; }
        started = true; startPos = i; cleanStart = i; parts = [];
        continue;
      }
      R.lastIndex = i;
      var m = R.exec(text);
      if (!m) { i = n; break; }
      var tok = m[0], at = m.index;
      if (tok === '--') {
        var e1 = skipLine(at);
        parts.push(text.substring(cleanStart, at)); cleanStart = e1;
        i = e1;
      } else if (tok === '/*') {
        var e2 = skipBlock(at);
        parts.push(text.substring(cleanStart, at)); parts.push(' '); cleanStart = e2;
        i = e2;
      } else if (tok === "'") {
        // E'...' は、バックスラッシュがエスケープ
        var prev = at > 0 ? text.charAt(at - 1) : '';
        var prev2 = at > 1 ? text.charAt(at - 2) : ' ';
        var isE = (prev === 'e' || prev === 'E') && !/[A-Za-z0-9_]/.test(prev2);
        i = skipQuoted(at, "'", !!opts.backslashEscapes || isE);
      } else if (tok === '"') {
        i = skipQuoted(at, '"', !!opts.backslashEscapes);
      } else if (tok === ';') {
        parts.push(text.substring(cleanStart, at));
        out.push({
          raw: P.stripTrailing(text.substring(startPos, at)) + ';',
          clean: parts.join('').replace(/^\s+|\s+$/g, ''),
          line: lineAt(startPos)
        });
        started = false; i = at + 1;
      } else {
        // ドル引用符
        var e3 = text.indexOf(tok, at + tok.length);
        i = e3 < 0 ? n : e3 + tok.length;
      }
    }
    if (started) {
      parts.push(text.substring(cleanStart, n));
      var raw = P.stripTrailing(text.substring(startPos, n));
      if (raw !== '') out.push({ raw: raw, clean: parts.join('').replace(/^\s+|\s+$/g, ''), line: lineAt(startPos) });
    }
    return out;
  };

  /** 最上位のカンマで分ける(括弧と引用符の中は分けない)。空の要素は除く。 */
  P.splitTop = function (s) {
    var out = [], depth = 0, start = 0;
    for (var i = 0; i < s.length; i++) {
      var c = s.charAt(i);
      if (c === "'" || c === '"') {
        i++;
        while (i < s.length && s.charAt(i) !== c) i++;
      } else if (c === '(') depth++;
      else if (c === ')') depth--;
      else if (c === ',' && depth === 0) { out.push(s.substring(start, i)); start = i + 1; }
    }
    out.push(s.substring(start));
    return out.map(function (x) { return x.replace(/^\s+|\s+$/g, ''); }).filter(function (x) { return x !== ''; });
  };

  /** `from` 以降の最初の `(` に対応する `)` までの内側と、`)` の次の位置。なければ null。 */
  P.parenBody = function (s, from) {
    var open = s.indexOf('(', from || 0);
    if (open < 0) return null;
    var depth = 0;
    for (var i = open; i < s.length; i++) {
      var c = s.charAt(i);
      if (c === "'" || c === '"') {
        i++;
        while (i < s.length && s.charAt(i) !== c) i++;
      } else if (c === '(') depth++;
      else if (c === ')') { depth--; if (depth === 0) return { body: s.substring(open + 1, i), end: i + 1 }; }
    }
    return null;
  };

  /** 修飾名を要素に分ける(`s.t.c` → ['s','t','c'])。引用符なしは小文字にし、引用符付きはそのまま(引用符は外す)。 */
  P.identParts = function (raw) {
    var parts = [], buf = '', quoted = false;
    for (var i = 0; i < raw.length; i++) {
      var c = raw.charAt(i);
      if (c === '"') { quoted = !quoted; buf += c; }
      else if (c === '.' && !quoted) { parts.push(buf); buf = ''; }
      else buf += c;
    }
    parts.push(buf);
    return parts.map(function (p) {
      p = p.replace(/^\s+|\s+$/g, '');
      return p.length >= 2 && p.charAt(0) === '"' && p.charAt(p.length - 1) === '"' ? p.substring(1, p.length - 1) : p.toLowerCase();
    });
  };

  /** 修飾名の最後の要素(スキーマを外した名前)。 */
  P.ident = function (raw) { var p = P.identParts(raw); return p[p.length - 1]; };

  /**
   * SQL の文字列リテラル('...' または E'...')を値にする。リテラルでなければ null。
   * E'...' はバックスラッシュのエスケープ(\n \t \r \\ \')を解く。
   */
  P.sqlString = function (s) {
    var t = String(s).replace(/^\s+|\s+$/g, '');
    var isE = /^[eE]'/.test(t);
    var body = isE ? t.substring(1) : t;
    var m = /^'((?:[^']|'')*)'$/.exec(body);
    if (!m) return null;
    var v = m[1].replace(/''/g, "'");
    if (!isE) return v;
    return v.replace(/\\(.)/g, function (_, c) {
      return c === 'n' ? '\n' : c === 't' ? '\t' : c === 'r' ? '\r' : c;
    });
  };

  /**
   * インポート結果(付録E)の組立。
   *   r.add(kind, obj)   kind: 'tables' | 'constraints' | 'triggers' | 'functions' | 'views' | 'types' | 'comments'
   *   r.unparsed(kind, reason, stmt, file)   解析できない文(stmt は P.splitSql の要素)
   *   r.nextViewName()   `import_01` のような、SELECT をビューにするときの名前
   *   r.toJson()         JSON文字列(main の戻り値にする)
   */
  P.ImportResult = function (dialect) {
    var data = {
      apiVersion: 3,
      dialect: dialect || '',
      tables: [], constraints: [], triggers: [], functions: [], views: [], types: [], comments: [],
      unparsed: []
    };
    var viewNo = 0;
    var r = {};
    r.data = data;
    r.add = function (kind, obj) { data[kind].push(obj); return r; };
    r.unparsed = function (kind, reason, stmt, file) {
      data.unparsed.push({ kind: kind, reason: reason, text: stmt.raw, line: stmt.line, file: file || '' });
      return r;
    };
    r.nextViewName = function () {
      viewNo++;
      return 'import_' + (viewNo < 10 ? '0' : '') + viewNo;
    };
    r.toJson = function () { return JSON.stringify(data); };
    return r;
  };

  return P;
})();
