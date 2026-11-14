import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:project_er_operation/command/command.dart';
import 'package:project_er_operation/importer/importer.dart';
import 'package:project_er_operation/model/model.dart';
import 'package:project_er_operation/runner/runner.dart';

import '../support/post_support.dart';

/// 大きなSQL(生産管理システムのDDL。約1.3MB)の取り込み。SQLファイルがこの環境に無いときは何もしない。
/// 元のSQL: ../flutter-pms/tools/docker/postgresql/script
void main() {
  const dir = r'E:\GitRepos\PrivateGit\flutter-pms\tools\docker\postgresql\script';
  const names = ['05_init_test.sql', '06_cteate_test.sql', '09_grant_test.sql', '10_mrp_dummy.sql', '12_cancel_supply_constraints.sql'];
  final present = names.every((n) => File('$dir\\$n').existsSync());

  test('大きなSQLをインポート用ポストで解析し、モデルへ取り込める(タイムアウト内)', () async {
    expect(prepareQuickJs(), isTrue);
    final files = [
      for (final n in names) SqlImportFile(name: n, text: File('$dir\\$n').readAsStringSync()),
    ];
    final sw = Stopwatch()..start();
    final data = await runImportPost(JsPostRunner(),
        script: File('post/postgresql.import.post').readAsStringSync(),
        files: files,
        timeout: const Duration(seconds: 120),
        library: File('post/pero.lib.js').readAsStringSync());
    final parseMs = sw.elapsedMilliseconds;
    final model = ErModel.empty(postPath: '');
    final cmd = ImportSqlCommand(diagramId: model.diagrams.first.id, data: data);
    cmd.apply(CommandContext(model, () => EntityLayouter(model)));
    // ignore: avoid_print
    print('import: parse ${parseMs}ms, total ${sw.elapsedMilliseconds}ms, ${cmd.report!.summary}, unparsed ${cmd.report!.unparsed.length}');
    expect(model.tables.length, 263);
    expect(model.relationships.length, 791);
    expect(model.methods.where((m) => m.kind == MethodKind.trigger).length, greaterThan(0));
    expect(parseMs, lessThan(60000));
  }, skip: present ? false : 'SQLファイルが無い');
}
