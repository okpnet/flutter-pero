import 'package:flutter_test/flutter_test.dart';
import 'package:project_er_operation/command/command.dart';
import 'package:project_er_operation/importer/importer.dart';
import 'package:project_er_operation/model/model.dart';

import '../support/post_support.dart';
import 'sql_import_test.dart' show runPost;

const _sql = r'''
CREATE TABLE item (
  id serial PRIMARY KEY,
  qty integer CHECK (qty >= 0),
  remove boolean NOT NULL DEFAULT false,
  state text,
  CONSTRAINT item_state_ck CHECK (state IN ('a', 'b')),
  CHECK (remove = false OR qty = 0)
);
ALTER TABLE ONLY item ADD CONSTRAINT item_alive_ck CHECK (remove = false);
''';

void main() {
  setUpAll(() => expect(prepareQuickJs(), isTrue, reason: 'flutter build windows --debug を一度実行してください'));

  test('CHECK制約(列・テーブル・ALTER TABLE)を取り込み、名前の有無で自動/手動になる', () async {
    final data = await runPost([const SqlImportFile(name: 'a.sql', text: _sql)]);
    final model = ErModel.empty(postPath: '');
    final cmd = ImportSqlCommand(diagramId: model.diagrams.first.id, data: data);
    cmd.apply(CommandContext(model, () => EntityLayouter(model)));
    final t = model.tables.single;
    final byExpr = {for (final c in t.checks) c.expression: c};
    expect(byExpr.keys, containsAll(['qty >= 0', "state IN ('a', 'b')", 'remove = false OR qty = 0', 'remove = false']));
    expect(byExpr['remove = false']!.name, 'item_alive_ck');
    expect(byExpr['remove = false']!.nameMode, NameMode.manual);
    expect(byExpr["state IN ('a', 'b')"]!.name, 'item_state_ck');
    expect(byExpr['qty >= 0']!.nameMode, NameMode.auto);
    expect(cmd.report!.unparsed, isEmpty);
  });
}
