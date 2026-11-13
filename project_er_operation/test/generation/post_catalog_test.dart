import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:project_er_operation/generation/generation.dart';
import 'package:project_er_operation/model/model.dart';

void main() {
  late Directory dir;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('pero_post');
    addTearDown(() {
      try {
        dir.deleteSync(recursive: true);
      } on FileSystemException {
        // ロック中のファイルが残っていれば無視する。
      }
    });
  });

  File write(String name, String text) => File('${dir.path}${Platform.pathSeparator}$name')..writeAsStringSync(text);
  String meta(String db, {int api = postApiVersion, String name = 'Sample'}) =>
      '// @post name=$name targetDb=$db apiVersion=$api\nfunction main(j) { return ""; }\n';

  group('走査とメタ情報', () {
    test('フォルダが無いときは空', () {
      final c = PostCatalog.scan('${dir.path}${Platform.pathSeparator}none');
      expect(c.files, isEmpty);
      expect(c.hasValid, isFalse);
    });

    test('*.post だけを対象にし、メタ情報から名前と対象DBを読む。ファイル名順', () {
      write('mysql.post', meta('mysql', name: 'MySQL用'));
      write('postgresql.post', meta('postgresql', name: 'PostgreSQL用'));
      write('readme.txt', 'x');
      final c = PostCatalog.scan(dir.path);
      expect(c.files.map((f) => f.fileName), ['mysql.post', 'postgresql.post']);
      expect(c.files.first.meta!.name, 'MySQL用');
      expect(c.valid.length, 2);
      expect(c.kinds({}), {DbKind.mysql, DbKind.postgresql});
    });

    test('メタ情報が無い/apiVersionが違うポストファイルは使えない(有効に数えない)', () {
      write('nometa.post', 'function main() {}');
      write('old.post', meta('postgresql', api: postApiVersion + 1));
      final c = PostCatalog.scan(dir.path);
      expect(c.files.length, 2);
      expect(c.valid, isEmpty);
      expect(c.hasValid, isFalse);
      expect(c.files.firstWhere((f) => f.fileName == 'nometa.post').problem, isNotNull);
      expect(c.files.firstWhere((f) => f.fileName == 'old.post').problem, contains('apiVersion'));
    });

    test('同梱の postgresql.post は postgresql として読める', () {
      final c = PostCatalog.scan('post');
      expect(c.valid.map((f) => f.fileName), contains('postgresql.post'));
      expect(c.kinds({}), contains(DbKind.postgresql));
    });
  });

  group('種類(kind)の関連付け', () {
    test('設定の文字列を読み書きする。不正な項目は無視する', () {
      final m = parseKindAssociations('MariaDB.post=mysql, oracle.post = postgresql;bad, x=unknown\nfoo=sqlite');
      expect(m, {'mariadb.post': DbKind.mysql, 'oracle.post': DbKind.postgresql, 'foo': DbKind.sqlite});
      expect(parseKindAssociations(formatKindAssociations(m)), m);
      expect(parseKindAssociations(''), isEmpty);
    });

    test('targetDb が既存のkindでないポストファイルは、関連付けた種類として扱う。無ければ対象外', () {
      write('mariadb.post', meta('mariadb'));
      final c = PostCatalog.scan(dir.path);
      expect(c.valid.length, 1);
      expect(c.kinds({}), isEmpty);
      expect(c.kinds({'mariadb.post': DbKind.mysql}), {DbKind.mysql});
      // メタ情報の targetDb の名前でも関連付けられる
      expect(c.kinds({'mariadb': DbKind.mysql}), {DbKind.mysql});
      expect(c.forKind(DbKind.mysql, {'mariadb.post': DbKind.mysql}).single.fileName, 'mariadb.post');
      expect(c.forKind(DbKind.postgresql, {'mariadb.post': DbKind.mysql}), isEmpty);
    });

    test('関連付けは、メタ情報のkindより優先する', () {
      write('pg_like.post', meta('postgresql'));
      final c = PostCatalog.scan(dir.path);
      expect(c.valid.single.kindOf({'pg_like.post': DbKind.sqlite}), DbKind.sqlite);
      expect(c.valid.single.kindOf({}), DbKind.postgresql);
    });
  });

  group('ポストファイルのロック(9.6-1-2)', () {
    test('存在しないポストファイルは、PostFileExceptionで処理を止める', () async {
      await expectLater(LockedPostFile.acquire('${dir.path}${Platform.pathSeparator}missing.post'),
          throwsA(isA<PostFileException>()));
    });

    test('ロックして全文(UTF-8)を読める', () async {
      final f = write('a.post', '${meta('postgresql')}// 日本語のコメント\n');
      final locked = await LockedPostFile.acquire(f.path);
      expect(locked.text, contains('日本語のコメント'));
      expect(parsePostMeta(locked.text)!.targetDb, 'postgresql');
      await locked.release();
    });

    test('ロック中は、書込み・削除・名前の変更ができず、解除すると操作できる', () async {
      final f = write('b.post', meta('postgresql'));
      final locked = await LockedPostFile.acquire(f.path);
      // 他の操作(書込み、名前の変更、削除)は失敗する。
      expect(() => f.writeAsStringSync('changed'), throwsA(isA<FileSystemException>()));
      expect(() => f.renameSync('${f.path}.renamed'), throwsA(isA<FileSystemException>()));
      expect(() => f.deleteSync(), throwsA(isA<FileSystemException>()));
      // 2重のロックもできない
      await expectLater(LockedPostFile.acquire(f.path), throwsA(isA<PostFileException>()));
      await locked.release();
      f.writeAsStringSync(meta('postgresql', name: 'changed'));
      expect(f.readAsStringSync(), contains('changed'));
      f.deleteSync();
      expect(f.existsSync(), isFalse);
    }, skip: Platform.isWindows ? false : 'Windowsのファイルロックの動作を確認するテスト');
  });
}
