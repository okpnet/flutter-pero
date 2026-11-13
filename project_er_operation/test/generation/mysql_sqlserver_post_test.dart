import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:project_er_operation/generation/generation.dart';
import 'package:project_er_operation/model/model.dart';
import 'package:project_er_operation/runner/runner.dart';

import '../support/post_models.dart';
import '../support/post_support.dart';

/// 同梱の mysql.post / sqlserver.post が出力するSQLを、期待値(golden)と比較する。
/// 期待値の更新: 環境変数 UPDATE_GOLDEN=1 で実行し、差分を目視で確認する。
/// 実際のMySQL / SQL Serverへ流して確認したものではない(サーバーがない環境で作った)。

/// サンプルモデルを、対象DBで生成できる形にする。メソッド・トリガーの本体はPostgreSQLのものを写し(中身の意味は確認しない)、
/// MySQL・SQL Serverにないユーザー定義型の列は text にする。
ErModel adapt(ErModel m, DbKind db) {
  m.properties.targetDb = db;
  for (final f in m.methods) {
    if ((f.bodies[db] ?? '').isEmpty) f.bodies[db] = f.bodies[DbKind.postgresql] ?? '';
  }
  for (final t in m.tables) {
    for (final g in t.triggers) {
      if ((g.inlineBodies[db] ?? '').isEmpty) g.inlineBodies[db] = g.inlineBodies[DbKind.postgresql] ?? '';
    }
    for (final c in t.columns) {
      if (c.typeId.startsWith('custom_')) c.typeId = 'text';
    }
  }
  m.types.removeWhere((t) => t.id.startsWith('custom_'));
  return m;
}

void main() {
  setUpAll(() => expect(prepareQuickJs(), isTrue, reason: 'flutter build windows --debug を一度実行してください'));

  final models = <String, ErModel Function()>{
    'simple': modelSimple,
    'foreign_keys': modelForeignKeys,
    'common_columns': modelCommonColumns,
    'views': modelViews,
    'triggers_cycle': modelTriggersAndCycle,
    'new_features': modelNewFeatures,
  };

  Future<String> generate(String post, ErModel m, {bool drop = false}) async {
    final r = await GenerationService(JsPostRunner()).generate(m, File('post/$post.post').readAsStringSync(),
        timeout: const Duration(seconds: 20), dropBeforeCreate: drop);
    if (!r.isOk) throw StateError('検証エラー: ${r.errors.map((e) => e.message).join(' / ')}');
    return r.text!;
  }

  for (final db in [DbKind.mysql, DbKind.sqlserver]) {
    group('${db.wire}.post', () {
      for (final e in models.entries) {
        test('サンプルモデル ${e.key} のSQLが期待値と一致する', () async {
          final sql = await generate(db.wire, adapt(e.value(), db));
          final file = File('test/generation/golden/${db.wire}_${e.key}.sql');
          if (Platform.environment['UPDATE_GOLDEN'] == '1') {
            file.parent.createSync(recursive: true);
            file.writeAsStringSync(sql);
          }
          expect(sql, file.readAsStringSync().replaceAll('\r\n', '\n'));
          expect(sql.endsWith('\n'), isTrue);
          expect(sql.contains('\r'), isFalse);
        });
      }
    });
  }

  test('ポストファイルのメタ情報(名前、対象DB、apiVersion)が正しい', () {
    for (final db in ['mysql', 'sqlserver']) {
      final meta = parsePostMeta(File('post/$db.post').readAsStringSync())!;
      expect(meta.targetDb, db);
      expect(meta.apiVersion, postApiVersion);
      expect(checkPostApiVersion(meta), isNull);
    }
    final c = PostCatalog.scan('post');
    expect(c.kinds({}), {DbKind.postgresql, DbKind.mysql, DbKind.sqlserver});
  });

  group('mysql.post の構文', () {
    test('識別子はバッククォート、コメントは COMMENT、自動採番は AUTO_INCREMENT、論理値は 1/0', () async {
      final sql = await generate('mysql', adapt(modelSimple(), DbKind.mysql));
      expect(sql, contains('CREATE TABLE `users` ('));
      expect(sql, contains('`id` INT AUTO_INCREMENT NOT NULL'));
      expect(sql, contains("`name` VARCHAR(100) NOT NULL COMMENT 'O''Brien''s name'"));
      expect(sql, contains('`active` TINYINT(1) DEFAULT 1'));
      expect(sql, contains("COMMENT='ユーザー表'"));
      expect(sql, contains('CONSTRAINT `users_pk` PRIMARY KEY (`id`)'));
      expect(sql, isNot(contains('COMMENT ON')));
    });

    test('外部キー: ON DELETE / ON UPDATE。循環でも、すべてのテーブルの後にALTERで出力する', () async {
      final sql = await generate('mysql', adapt(modelTriggersAndCycle(), DbKind.mysql));
      final lastCreate = sql.lastIndexOf('CREATE TABLE');
      expect(sql.indexOf('ADD CONSTRAINT `a_fk1`'), greaterThan(lastCreate));
      expect(sql, contains('ON DELETE SET NULL'));
    });

    test('MySQLにないもの(WHEN、STATEMENT単位、NULLS NOT DISTINCT、DEFERRABLE)はコメントで残す', () async {
      final trg = await generate('mysql', adapt(modelTriggersAndCycle(), DbKind.mysql));
      expect(trg, contains('-- [PERO] a_trg01: WHEN('));
      expect(trg, contains('-- [PERO] b_trg01: STATEMENT単位のトリガーは MySQL にないため出力しません'));
      expect(trg, contains('CREATE TRIGGER `a_trg01_insert` BEFORE INSERT ON `a` FOR EACH ROW'));
      expect(trg, contains('CREATE TRIGGER `a_trg01_update` BEFORE UPDATE ON `a` FOR EACH ROW'));
      final nf = await generate('mysql', adapt(modelNewFeatures(), DbKind.mysql));
      expect(nf, contains('NULLS NOT DISTINCT は MySQL にない'));
      expect(nf, contains('DEFERRABLE INITIALLY DEFERRED は MySQL にない'));
      expect(nf, contains('CREATE DATABASE IF NOT EXISTS `app`'));
      expect(nf, contains('`app`.`node`'));
    });

    test('再実行用のDROP', () async {
      final sql = await generate('mysql', adapt(modelNewFeatures(), DbKind.mysql), drop: true);
      expect(sql, contains('DROP TABLE IF EXISTS `app`.`node`;'));
      expect(sql, contains('DROP VIEW IF EXISTS'));
      expect(sql, contains('DROP TRIGGER IF EXISTS'));
    });
  });

  group('sqlserver.post の構文', () {
    test('識別子は角括弧、自動採番は IDENTITY、コメントは拡張プロパティ、リテラルは N 付き', () async {
      final sql = await generate('sqlserver', adapt(modelSimple(), DbKind.sqlserver));
      expect(sql, contains('CREATE TABLE [users] ('));
      expect(sql, contains('[id] int IDENTITY(1,1) NOT NULL'));
      expect(sql, contains("[status] varchar(10) NULL DEFAULT N'it''s'"));
      expect(sql, contains('[active] bit NULL DEFAULT 1'));
      expect(sql, contains("sp_addextendedproperty @name = N'MS_Description', @value = N'ユーザー表'"));
      expect(sql, contains("@level2type = N'COLUMN', @level2name = N'name'"));
      expect(sql, isNot(contains('COMMENT ON')));
    });

    test('ビューとトリガーは GO で区切り、CREATE OR ALTER を使う', () async {
      final v = await generate('sqlserver', adapt(modelViews(), DbKind.sqlserver));
      expect(v, contains('GO\n\nCREATE OR ALTER VIEW [v_orders] AS'));
      expect(v, contains('LEFT JOIN [customers] [c] ON [o].[customer_id] = [c].[id]'));
      expect(v, contains('SELECT * FROM recent_orders(10)'));
      final t = await generate('sqlserver', adapt(modelTriggersAndCycle(), DbKind.sqlserver));
      expect(t, contains('CREATE OR ALTER TRIGGER [a_trg01] ON [a]\nAFTER INSERT, UPDATE\nAS\n'));
      expect(t, contains('-- [PERO] a_trg01: BEFORE は SQL Server にないため、AFTER トリガーにしました'));
    });

    test('再実行用のDROP: 先に外部キー制約を削除し、テーブル・ビュー・トリガーを DROP ... IF EXISTS', () async {
      final sql = await generate('sqlserver', adapt(modelNewFeatures(), DbKind.sqlserver), drop: true);
      expect(sql.indexOf('DROP CONSTRAINT IF EXISTS'), lessThan(sql.indexOf('DROP TABLE IF EXISTS')));
      expect(sql, contains('DROP VIEW IF EXISTS'));
      expect(sql, contains('DROP TRIGGER IF EXISTS'));
      expect(sql, contains("IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = N'app') EXEC(N'CREATE SCHEMA [app]');"));
    });
  });
}
