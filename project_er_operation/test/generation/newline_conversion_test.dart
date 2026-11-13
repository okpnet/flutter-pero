import 'package:flutter_test/flutter_test.dart';
import 'package:project_er_operation/generation/generation.dart';
import 'package:project_er_operation/model/model.dart';

String crlf(String s, {DbKind db = DbKind.postgresql}) => convertNewlines(s, crlf: true, db: db);
String lf(String s, {DbKind db = DbKind.postgresql}) => convertNewlines(s, crlf: false, db: db);

void main() {
  test('引用符(シングルクォート)の中の改行は変換せず、ほかは設定の改行コードにする(9.6-5)', () {
    const sql = "CREATE TABLE t (a int);\nCOMMENT ON TABLE t IS 'a\nb';\nSELECT 1;\n";
    expect(crlf(sql), "CREATE TABLE t (a int);\r\nCOMMENT ON TABLE t IS 'a\nb';\r\nSELECT 1;\r\n");
    expect(lf("x\r\ny 'p\r\nq' z\r\n"), "x\ny 'p\r\nq' z\n"); // 引用符の中のCRLFもそのまま
  });

  test('ファンクションの本体(ドル引用符)は変換し、その中の文字列リテラルだけ変換しない', () {
    const sql = "CREATE FUNCTION f() RETURNS text AS \$\$\nBEGIN\n  RETURN 'x\ny';\nEND\n\$\$ LANGUAGE plpgsql;\n";
    expect(crlf(sql),
        "CREATE FUNCTION f() RETURNS text AS \$\$\r\nBEGIN\r\n  RETURN 'x\ny';\r\nEND\r\n\$\$ LANGUAGE plpgsql;\r\n");
  });

  test('コメントの中の引用符は無視する。行コメント、ブロックコメントの改行は変換する', () {
    const sql = "-- it's a comment\nSELECT 'a\nb'; /* don't\n*/\nSELECT 2;\n";
    expect(crlf(sql), "-- it's a comment\r\nSELECT 'a\nb'; /* don't\r\n*/\r\nSELECT 2;\r\n");
  });

  test(r"引用符の2連('')はリテラルの中。PostgreSQL の E'...' は \' をエスケープとして扱う", () {
    expect(crlf("SELECT 'it''s\nok';\nX\n"), "SELECT 'it''s\nok';\r\nX\r\n");
    expect(crlf("SELECT E'a\\'b\nc';\nX\n"), "SELECT E'a\\'b\nc';\r\nX\r\n");
    // E以外では、バックスラッシュはエスケープではない
    expect(crlf("SELECT 'a\\'\nX\n"), "SELECT 'a\\'\r\nX\r\n");
  });

  test('MySQL はバックスラッシュのエスケープ、バッククォートの識別子を扱う', () {
    expect(crlf("SELECT 'a\\'b\nc';\nX\n", db: DbKind.mysql), "SELECT 'a\\'b\nc';\r\nX\r\n");
    expect(crlf("SELECT `a'b`;\nX\n", db: DbKind.mysql), "SELECT `a'b`;\r\nX\r\n");
  });

  test('二重引用符の識別子の中は変換しない', () {
    expect(crlf('SELECT "a\nb";\nX\n'), 'SELECT "a\nb";\r\nX\r\n');
  });

  test('閉じていない引用符など解析できないときは、全体を変換する', () {
    expect(crlf("SELECT 'abc;\nX\n"), "SELECT 'abc;\r\nX\r\n");
    expect(crlf('SELECT 1; /* x\nY\n'), 'SELECT 1; /* x\r\nY\r\n');
  });

  test('引用符のない文は、全体を変換する。LFのときは、CRLFをLFにそろえる', () {
    expect(crlf('a\nb\r\nc\n'), 'a\r\nb\r\nc\r\n');
    expect(lf('a\nb\r\nc\n'), 'a\nb\nc\n');
  });
}
