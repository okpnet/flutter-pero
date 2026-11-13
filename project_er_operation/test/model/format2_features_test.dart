import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:project_er_operation/command/command.dart';
import 'package:project_er_operation/generation/generation.dart';
import 'package:project_er_operation/model/model.dart';
import 'package:project_er_operation/persistence/persistence.dart';

import '../support/post_models.dart';
import '../support/sample_models.dart';

CommandHistory historyOf(ErModel m) => CommandHistory(CommandContext(m, () => EntityLayouter(m)));

bool hasMsg(List<ValidationIssue> l, String part) => l.any((e) => e.message.contains(part));

void main() {
  group('形式2の保存と読込', () {
    test('形式1のファイルは、後から加わったキーの欠落を修復として記録せず開け、標準型 interval を補う', () {
      final j = jsonEncode({
        'formatVersion': 1,
        'appVersion': '0.1.0',
        'id': 1,
        'nextId': 100,
        'properties': {
          'outputFileName': '',
          'outputFolder': '',
          'targetDb': 'postgresql',
          'postPath': '',
          'startQuery': '',
          'endQuery': '',
        },
        'types': [
          for (final t in standardTypes().where((t) => t.id != 'interval')) PeroEncoder.typeToMap(t)..remove('kind')..remove('fields')..remove('enumValues'),
        ],
        'methods': [],
        'commonColumnPatterns': [],
        'entities': [
          {
            'id': 30,
            'kind': 'table',
            'logicalName': '',
            'physicalName': 't',
            'comment': '',
            'locked': false,
            'columns': [
              {
                'id': 31,
                'logicalName': '',
                'physicalName': 'id',
                'typeId': 'integer',
                'length': null,
                'precision': null,
                'scale': null,
                'pk': true,
                'notNull': true,
                'defaultKind': 'none',
                'defaultValue': '',
                'defaultMethodId': null,
                'comment': '',
              }
            ],
            'indexes': [],
            'uniques': [],
            'preQuery': '',
            'postQuery': '',
            'triggers': [],
          }
        ],
        'relationships': [],
        'diagrams': [
          {
            'id': 80,
            'name': 'ダイアグラム1',
            'pageSize': 'A3',
            'orientation': 'landscape',
            'pageRows': 1,
            'pageCols': 1,
            'placements': [],
            'view': {'zoom': 1.0, 'scrollX': 0, 'scrollY': 0},
          }
        ],
      });
      final r = PeroDecoder.decode(j);
      expect(r.error, isNull);
      expect(r.repairs.items, isEmpty);
      expect(r.model!.typeById('interval'), isNotNull);
      expect(r.model!.typeById('varchar_nolen'), isNotNull);
      expect(r.model!.properties.includeSchema, isFalse);
      expect(r.model!.diagrams.single.schema, '');
      expect(r.model!.tables.single.checks, isEmpty);
    });

    test('形式2で、新しいキーが欠落していれば修復として記録する', () {
      final j = jsonDecode(PeroEncoder.encode(fullModel())) as Map<String, dynamic>;
      (j['properties'] as Map).remove('schema');
      final r = PeroDecoder.decode(jsonEncode(j));
      expect(r.repairs.items.any((s) => s.contains('properties.schema')), isTrue);
    });

    test('存在しない依存テーブルとUPDATE列は、整合性確認で削除される', () {
      final m = fullModel();
      m.methods.firstWhere((x) => x.name == 'now_utc').dependsOnTableIds.add(999999);
      final trg = m.tables.firstWhere((t) => t.physicalName == 'orders').triggers.first;
      trg.updateColumnIds.add(999998);
      final (ok, rep) = IntegrityRepairer.repairAll(m);
      expect(ok, isTrue);
      expect(rep.items.length, 2);
      expect(m.methods.firstWhere((x) => x.name == 'now_utc').dependsOnTableIds, hasLength(1));
      expect(trg.updateColumnIds, hasLength(1));
    });
  });

  group('生成前検証(形式2)', () {
    test('サンプルのモデルにエラーはない', () {
      expect(ModelValidator(modelNewFeatures()).validate().errors, isEmpty);
    });

    test('式・CHECKの式・SQLビューのSQLが空ならエラー', () {
      final m = modelNewFeatures();
      m.tables.first.columns.firstWhere((c) => c.defaultKind == DefaultKind.expression).defaultExpression = ' ';
      m.tables.first.checks.first.expression = '';
      (m.views.single).sql.sql = '';
      final e = ModelValidator(m).validate().errors;
      expect(hasMsg(e, 'デフォルトの式が空'), isTrue);
      expect(hasMsg(e, 'CHECK制約'), isTrue);
      expect(hasMsg(e, 'SQLが空'), isTrue);
    });

    test('ユーザー定義型の不備と、スキーマ名の形式', () {
      final m = modelNewFeatures();
      m.types.firstWhere((t) => t.kind == TypeKind.enumeration).enumValues = [];
      m.types.firstWhere((t) => t.kind == TypeKind.composite).fields = [];
      m.diagrams.last.schema = '1bad';
      final e = ModelValidator(m).validate().errors;
      expect(hasMsg(e, '列挙型'), isTrue);
      expect(hasMsg(e, '複合型'), isTrue);
      expect(hasMsg(e, 'スキーマ名「1bad」'), isTrue);
    });

    test('トリガーのUPDATE列: 展開されない列はエラー、UPDATEイベントがなければ警告', () {
      final m = modelNewFeatures();
      final g = m.tables.first.triggers.single;
      g.updateColumnIds.add(424242);
      expect(hasMsg(ModelValidator(m).validate().errors, 'UPDATE列'), isTrue);
      g.updateColumnIds.remove(424242);
      g.events = [TriggerEvent.insert];
      expect(hasMsg(ModelValidator(m).validate().warnings, 'UPDATE列の指定は使われません'), isTrue);
    });

    test('CHECK制約名の重複はエラー。主キー制約名は規則(プリフィクス・サフィックス)で決まる', () {
      final m = modelNewFeatures();
      m.tables.first.checks.last.name = 'node_ck1';
      expect(hasMsg(ModelValidator(m).validate().errors, '制約名「node_ck1」'), isTrue);
      expect(m.primaryKeyName(m.tables.first, const PkNaming(prefix: 'a_', suffix: '_b')), 'a_node_b');
    });
  });

  group('コマンド(形式2)', () {
    test('列の削除で、トリガーのUPDATE列から外れる', () {
      final m = modelNewFeatures();
      final node = m.tables.firstWhere((t) => t.physicalName == 'node');
      final col = node.columns[2].id;
      final h = historyOf(m);
      expect(RemoveColumnCommand.impacts(m, node.id, col).any((s) => s.contains('UPDATE列')), isTrue);
      h.execute(RemoveColumnCommand(node.id, col));
      expect(m.tableById(node.id)!.triggers.single.updateColumnIds, isNot(contains(col)));
      h.undo();
      expect(m.tableById(node.id)!.triggers.single.updateColumnIds, contains(col));
    });

    test('テーブルの削除で、ファンクションの依存テーブルから外れる(Undoで戻る)', () {
      final m = modelNewFeatures();
      final fn = m.methods.firstWhere((x) => x.name == 'count_nodes');
      final node = m.tables.firstWhere((t) => t.physicalName == 'node');
      final h = historyOf(m);
      h.execute(DeleteEntitiesCommand([node.id]));
      expect(m.methods.firstWhere((x) => x.name == 'count_nodes').dependsOnTableIds, isEmpty);
      h.undo();
      expect(m.methods.firstWhere((x) => x.name == 'count_nodes').dependsOnTableIds, [node.id]);
      expect(fn.id, m.methods.firstWhere((x) => x.name == 'count_nodes').id);
    });

    test('型の削除で、複合型の項目とSQLビューの列も置換先に付け替える', () {
      final m = modelNewFeatures();
      m.types.add(DataType(id: 'custom_9', displayName: 'money', physical: {DbKind.postgresql: 'money'}));
      m.types.firstWhere((t) => t.kind == TypeKind.composite).fields.add(TypeField(name: 'm', typeId: 'custom_9'));
      m.views.single.sql.columns.add(FunctionReturnColumn(name: 'm', typeId: 'custom_9'));
      expect(DeleteTypeCommand.usageCount(m, 'custom_9'), 2);
      historyOf(m).execute(DeleteTypeCommand('custom_9', 'integer'));
      expect(m.types.firstWhere((t) => t.kind == TypeKind.composite).fields.last.typeId, 'integer');
      expect(m.views.single.sql.columns.single.typeId, 'integer');
    });

    test('スキーマの変更(モデル、ダイアグラム)はUndoでき、JSONの往復で復元できる', () {
      final m = ErModel.empty();
      final h = historyOf(m);
      final d = m.diagrams.first;
      final c1 = SetDiagramSchemaCommand(d.id, 'sales');
      h.execute(c1);
      h.execute(UpdateModelPropertiesCommand({'schema': 'core', 'includeSchema': true}));
      expect((m.diagrams.first.schema, m.properties.schema, m.properties.includeSchema), ('sales', 'core', true));
      final back = commandFromJson(jsonDecode(jsonEncode(c1.toJson())) as Map<String, Object?>);
      expect(back.type, 'setDiagramSchema');
      h.undo();
      h.undo();
      expect((m.diagrams.first.schema, m.properties.schema, m.properties.includeSchema), ('', '', false));
    });

    test('遅延可否の変更はUndoでき、自己参照のリレーションシップは親の鍵の列を使わない', () {
      final m = modelNewFeatures();
      final self = m.relationships.firstWhere((r) => r.parentId == r.childId);
      expect(self.deferrable, Deferrable.deferred);
      final h = historyOf(m);
      h.execute(UpdateRelationshipCommand(self.id, {'deferrable': 'none'}));
      expect(m.relationshipById(self.id)!.deferrable, Deferrable.none);
      h.undo();
      expect(m.relationshipById(self.id)!.deferrable, Deferrable.deferred);
      final node = m.tableById(self.parentId)!;
      expect(self.columnPairs.single.parentColumnId, node.columns.first.id);
      expect(self.columnPairs.single.childColumnId, isNot(node.columns.first.id));
    });
  });

  group('コピー・貼り付け', () {
    test('CHECK・UPDATE列・自己参照・遅延可否を、新しいIDに付け替えて複製する', () {
      final m = modelNewFeatures();
      final node = m.tables.firstWhere((t) => t.physicalName == 'node');
      final d = m.diagrams.first;
      final paste = PasteEntitiesCommand(diagramId: d.id, data: ClipboardData.fromSelection(m, d, [node.id]));
      historyOf(m).execute(paste);
      final n = m.tableById(paste.createdIds.single)!;
      expect(n.physicalName, 'node_copy');
      final oldIds = node.checks.map((c) => c.id).toSet();
      expect(n.checks.every((c) => !oldIds.contains(c.id)), isTrue);
      expect(n.checks.last.name, 'node_state_ck_copy');
      final g = n.triggers.single;
      expect(g.args, "'80', 1");
      expect(g.updateColumnIds.every((id) => n.columnById(id) != null), isTrue);
      final self = m.relationships.where((r) => r.parentId == n.id && r.childId == n.id).single;
      expect(self.deferrable, Deferrable.deferred);
      expect(n.columnById(self.columnPairs.single.childColumnId), isNotNull);
      expect(ModelValidator(m).validate().errors, isEmpty);
    });
  });

  group('型のコメントとスキーマ、メソッドのスキーマ(生成)', () {
    test('ユーザー定義型は、型名・COMMENT ON TYPE・列の型にスキーマが付く(型のスキーマが空ならモデルのスキーマ)', () {
      final m = modelNewFeatures();
      final json = GenerationJsonBuilder(m).build();
      final ut = (json['userTypes'] as List);
      final status = ut.firstWhere((t) => t['name'] == 'status_t');
      final point = ut.firstWhere((t) => t['name'] == 'point_t');
      expect((status['schema'], status['comment']), ('app', "状態's"));
      expect(point['schema'], 'types'); // 型のスキーマ
      final node = (json['tables'] as List).firstWhere((t) => t['physicalName'] == 'node');
      final state = (node['columns'] as List).firstWhere((c) => c['physicalName'] == 'state');
      expect(state['type'], 'app.status_t');
      expect((json['schemas'] as List), containsAll(['app', 'types', 'fn']));
    });

    test('メソッドのスキーマ: トリガーの呼出し先に付く。外部定義、含めない設定では付かない', () {
      final m = modelNewFeatures();
      final json = GenerationJsonBuilder(m).build();
      final g = ((json['tables'] as List).firstWhere((t) => t['physicalName'] == 'node')['triggers'] as List).single;
      expect(g['methodSchema'], 'fn');
      final empty = (json['methods'] as List).firstWhere((x) => x['name'] == 'empty_string');
      expect(empty['schema'], ''); // 外部定義
      m.properties.includeSchema = false;
      final off = GenerationJsonBuilder(m).build();
      expect(((off['userTypes'] as List).first)['schema'], '');
    });
  });

  group('空文字のデフォルト', () {
    test('新規モデルは標準メソッド empty_string(外部定義、呼出し式 \'\')を持つ', () {
      final m = ErModel.empty();
      final x = m.methods.single;
      expect((x.name, x.external, x.callExpr(DbKind.postgresql)), (emptyStringMethodName, true, "''"));
    });
  });
}
