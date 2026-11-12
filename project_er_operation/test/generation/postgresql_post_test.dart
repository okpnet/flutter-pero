import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:project_er_operation/generation/generation.dart';
import 'package:project_er_operation/model/model.dart';
import 'package:project_er_operation/runner/runner.dart';

import '../support/post_models.dart';
import '../support/post_support.dart';

/// 生成用JSON(付録B)から postgresql.post が出力するSQLを、期待値(golden)と比較する。
/// 期待値の更新: 環境変数 UPDATE_GOLDEN=1 で実行し、差分を目視で確認する。
void main() {
  setUpAll(() => expect(prepareQuickJs(), isTrue, reason: 'flutter build windows --debug を一度実行してください'));

  final cases = <String, ErModel Function()>{
    'simple': modelSimple,
    'foreign_keys': modelForeignKeys,
    'common_columns': modelCommonColumns,
    'views': modelViews,
    'triggers_cycle': modelTriggersAndCycle,
  };

  for (final e in cases.entries) {
    test('サンプルモデル ${e.key} のSQLが期待値と一致する', () async {
      final sql = await generateSql(e.value());
      final file = File('test/generation/golden/${e.key}.sql');
      if (Platform.environment['UPDATE_GOLDEN'] == '1') {
        file.parent.createSync(recursive: true);
        file.writeAsStringSync(sql);
      }
      expect(sql, file.readAsStringSync().replaceAll('\r\n', '\n'));
      expect(sql.endsWith('\n'), isTrue);
      expect(sql.contains('\r'), isFalse);
    });
  }

  test('循環する外部キーは deferred になり、トポロジカル順に並ぶ', () {
    final json = GenerationJsonBuilder(modelTriggersAndCycle()).build();
    final fks = json['foreignKeys'] as List;
    expect(fks.where((f) => f['deferred'] == true).length, 1);
    final tables = (json['tables'] as List).map((t) => t['physicalName']).toList();
    expect(tables.toSet(), {'a', 'b'});
  });

  test('テーブルは親から子の順', () {
    final json = GenerationJsonBuilder(modelForeignKeys()).build();
    expect((json['tables'] as List).map((t) => t['physicalName']), ['customers', 'orders']);
  });

  test('生成用JSONの構造(付録B): 共通列のorigin、type展開、primaryKey、制約名の解決', () {
    final m = modelCommonColumns();
    final json = GenerationJsonBuilder(m).build();
    expect(json['apiVersion'], 1);
    expect(json['targetDb'], 'postgresql');
    final t = (json['tables'] as List).firstWhere((t) => t['physicalName'] == 'mst_item');
    expect((t['columns'] as List).map((c) => c['origin']), ['common', 'table', 'table', 'common', 'common']);
    expect((t['columns'] as List)[0]['type'], 'integer');
    expect(t['primaryKey'], {'name': 'mst_item_pk', 'columns': ['id']});
    expect((t['indexes'] as List).single['name'], 'mst_item_idx1');
    final created = (t['columns'] as List)[3];
    expect(created['default'], {'kind': 'method', 'value': '', 'call': 'now()'});
    expect(created['typeCategory'], 'datetime');
    final noPk = (json['tables'] as List).firstWhere((t) => t['physicalName'] == 'tmp_item');
    expect(noPk['primaryKey'], isNotNull);
    expect(json['methods'], isNotEmpty);
  });

  test('トリガーの本体はプレースホルダを置換済みで、methodNameは入力の場合null', () {
    final json = GenerationJsonBuilder(modelTriggersAndCycle()).build();
    final b = (json['tables'] as List).firstWhere((t) => t['physicalName'] == 'b');
    final trg = b['triggers'] as List;
    expect(trg[0]['methodName'], 'touch_updated');
    expect(trg[1]['methodName'], isNull);
    expect(trg[1]['name'], 'b_trg02');
    expect(trg[1]['body'], contains('CREATE FUNCTION b_trg02()'));
    expect(trg[1]['order'], 2);
  });

  test('ポストファイルの例外・戻り値・console.log・ES2020構文', () async {
    final runner = JsPostRunner();
    const t = Duration(seconds: 10);
    expect(await runner.run(script: r'function main(j){ return `a${JSON.parse(j).x ?? 0}`; }', jsonText: '{"x":5}', timeout: t), 'a5');
    final logs = <String>[];
    await runner.run(script: 'function main(j){ console.log("hi", 1); return ""; }', jsonText: '{}', timeout: t, onLog: logs.add);
    expect(logs, ['hi 1']);
    // タイマー、ネットワークは使えない(9.6-4)
    expect(
        await runner.run(
            script: "function main(j){ return [typeof setTimeout, typeof setInterval, typeof fetch, typeof XMLHttpRequest].join(','); }",
            jsonText: '{}',
            timeout: t),
        'undefined,undefined,undefined,undefined');
    await expectLater(runner.run(script: 'function main(j){ throw new Error("boom"); }', jsonText: '{}', timeout: t),
        throwsA(isA<PostException>().having((e) => e.message, 'message', 'boom')));
    await expectLater(runner.run(script: 'function main(j){ return 1; }', jsonText: '{}', timeout: t),
        throwsA(isA<PostException>().having((e) => e.message, 'message', contains('文字列'))));
    await expectLater(runner.run(script: 'function main(j){ while(true){} }', jsonText: '{}', timeout: const Duration(seconds: 1)),
        throwsA(isA<PostException>()));
  });

  test('メタ情報 @post の解析とapiVersion検査', () {
    final meta = parsePostMeta(postScript)!;
    expect((meta.name, meta.targetDb, meta.apiVersion), ('PostgreSQL', 'postgresql', 1));
    expect(checkPostApiVersion(meta), isNull);
    expect(parsePostMeta('// no meta\nfunction main(){}'), isNull);
    expect(checkPostApiVersion(parsePostMeta('// @post name=x y targetDb=mysql apiVersion=2')), isNotNull);
    expect(parsePostMeta('// @post name=x y targetDb=mysql apiVersion=2')!.name, 'x y');
    // 先頭10行を超えた位置のメタ情報は無効
    expect(parsePostMeta('${'\n' * 10}// @post name=a targetDb=b apiVersion=1'), isNull);
  });
}
