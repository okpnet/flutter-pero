import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:project_er_operation/command/command.dart';
import 'package:project_er_operation/generation/generation.dart';
import 'package:project_er_operation/model/model.dart';
import 'package:project_er_operation/persistence/persistence.dart';
import 'package:project_er_operation/runner/runner.dart';

import '../support/sample_models.dart';
import '../support/post_support.dart';

/// CHECK制約の条件(6.4-6): 列・演算子・値から、列の型に合わせたSQLをポストファイルが作る。
CommandHistory historyOf(ErModel m) => CommandHistory(CommandContext(m, () => EntityLayouter(m)));

ErModel _model(DbKind db) {
  final m = ErModel.empty();
  m.properties.targetDb = db;
  final t = table(m, 'item', [
    col(m, 'id', 'auto', pk: true),
    col(m, 'qty', 'integer'),
    col(m, 'remove', 'boolean'),
    col(m, 'state', 'varchar', length: 10),
    col(m, 'memo', 'text'),
  ]);
  CheckCondition cond(int i, CheckOperator op, List<String> v) =>
      CheckCondition(columnId: t.columns[i].id, operator: op, values: v);
  t.checks.addAll([
    CheckDef(id: m.allocateId(), mode: CheckMode.conditions, conditions: [cond(2, CheckOperator.eq, ['false'])]),
    CheckDef(id: m.allocateId(), mode: CheckMode.conditions, conditions: [cond(1, CheckOperator.between, ['1', '10'])]),
    CheckDef(id: m.allocateId(), mode: CheckMode.conditions, conditions: [cond(3, CheckOperator.inList, ['a', "b'c"])]),
    CheckDef(id: m.allocateId(), mode: CheckMode.conditions, conditions: [cond(4, CheckOperator.like, ['x%'])]),
    CheckDef(
        id: m.allocateId(),
        mode: CheckMode.conditions,
        join: CheckJoin.or,
        conditions: [cond(1, CheckOperator.isNull, []), cond(1, CheckOperator.ge, ['5']), cond(2, CheckOperator.ne, ['true'])]),
    CheckDef(id: m.allocateId(), expression: 'qty <> 99'),
  ]);
  return m;
}

Future<String> _generate(String post, ErModel m) async {
  final r = await GenerationService(JsPostRunner()).generate(m, File('post/$post.post').readAsStringSync(),
      timeout: const Duration(seconds: 20));
  if (!r.isOk) throw StateError('検証エラー: ${r.errors.map((e) => e.message).join(' / ')}');
  return r.text!;
}

void main() {
  setUpAll(() => expect(prepareQuickJs(), isTrue, reason: 'flutter build windows --debug を一度実行してください'));

  group('ポストファイルが列の型に合わせて条件を変換する', () {
    test('postgresql: 真偽値は false、文字列は引用符(\' は二重化)', () async {
      final sql = await _generate('postgresql', _model(DbKind.postgresql));
      expect(sql, contains('CHECK (remove = false)'));
      expect(sql, contains('CHECK (qty BETWEEN 1 AND 10)'));
      expect(sql, contains("CHECK (state IN ('a', 'b''c'))"));
      expect(sql, contains("CHECK (memo LIKE 'x%')"));
      expect(sql, contains('CHECK (qty IS NULL OR qty >= 5 OR remove <> true)'));
      expect(sql, contains('CHECK (qty <> 99)')); // 式はそのまま
    });

    test('sqlserver: 真偽値(bit)は 0 / 1', () async {
      final sql = await _generate('sqlserver', _model(DbKind.sqlserver));
      expect(sql, contains('CHECK ([remove] = 0)'));
      expect(sql, contains("CHECK ([state] IN (N'a', N'b''c'))"));
      expect(sql, contains('CHECK ([qty] IS NULL OR [qty] >= 5 OR [remove] <> 1)'));
      expect(sql, contains('CHECK (qty <> 99)'));
    });

    test('mysql: 真偽値(TINYINT(1))は 0 / 1', () async {
      final sql = await _generate('mysql', _model(DbKind.mysql));
      expect(sql, contains('CHECK (`remove` = 0)'));
      expect(sql, contains('CHECK (`qty` BETWEEN 1 AND 10)'));
      expect(sql, contains('CHECK (`qty` IS NULL OR `qty` >= 5 OR `remove` <> 1)'));
    });
  });

  group('生成用JSON', () {
    test('条件は列の型とカテゴリ付きで渡し、式のときは条件を空にする', () {
      final json = GenerationJsonBuilder(_model(DbKind.postgresql)).build();
      expect(json['apiVersion'], 4);
      final checks = ((json['tables'] as List).single as Map)['checks'] as List;
      final first = checks.first as Map;
      expect(first['mode'], 'conditions');
      expect(first['expression'], '');
      final c = (first['conditions'] as List).single as Map;
      expect(c['column'], 'remove');
      expect(c['typeCategory'], 'boolean');
      expect(c['operator'], 'eq');
      expect(c['values'], ['false']);
      final last = checks.last as Map;
      expect(last['mode'], 'expression');
      expect(last['expression'], 'qty <> 99');
      expect(last['conditions'], isEmpty);
    });
  });

  group('生成前検証', () {
    List<String> errors(ErModel m) => ModelValidator(m).validate().errors.map((e) => e.message).toList();

    test('条件が0、値の数、真偽値・数値の値、型に使えない演算子はエラー', () {
      final m = _model(DbKind.postgresql);
      final t = m.tables.single;
      t.checks[0].conditions.single.values = ['yes'];
      t.checks[1].conditions.single.values = ['1'];
      t.checks[2].conditions.single.values = [''];
      t.checks[3].conditions.single.operator = CheckOperator.like;
      t.checks[3].conditions.single.columnId = t.columns[1].id; // integer への LIKE
      t.checks[4].conditions.clear();
      final e = errors(m);
      expect(e.any((x) => x.contains('真偽値')), isTrue);
      expect(e.any((x) => x.contains('値の数')), isTrue);
      expect(e.any((x) => x.contains('値が空')), isTrue);
      expect(e.any((x) => x.contains('は使えません')), isTrue);
      expect(e.any((x) => x.contains('条件がありません')), isTrue);
    });

    test('数値の列に数値でない値はエラー', () {
      final m = _model(DbKind.postgresql);
      m.tables.single.checks[1].conditions.single.values = ['1', 'abc'];
      expect(errors(m).any((x) => x.contains('数値ではありません')), isTrue);
    });

    test('正しい条件はエラーにならない', () {
      expect(errors(_model(DbKind.postgresql)), isEmpty);
    });

    test('演算子は列の型のカテゴリで絞られる', () {
      expect(CheckOperator.allowedFor(TypeCategory.boolean),
          [CheckOperator.eq, CheckOperator.ne, CheckOperator.isNull, CheckOperator.isNotNull]);
      expect(CheckOperator.allowedFor(TypeCategory.number), isNot(contains(CheckOperator.like)));
      expect(CheckOperator.allowedFor(TypeCategory.string), contains(CheckOperator.like));
    });
  });

  group('保存・列の削除・複製', () {
    test('条件は保存と復元の往復で保たれる', () {
      final m = _model(DbKind.postgresql);
      final r = PeroDecoder.decode(PeroEncoder.encode(m));
      expect(r.repairs.items, isEmpty);
      final k = r.model!.tables.single.checks;
      expect(k.length, 6);
      expect(k[4].join, CheckJoin.or);
      expect(k[4].conditions.map((c) => c.operator), [CheckOperator.isNull, CheckOperator.ge, CheckOperator.ne]);
      expect(k[2].conditions.single.values, ['a', "b'c"]);
      expect(k[5].mode, CheckMode.expression);
    });

    test('古い形式(formatVersion 3)の式だけのCHECKは、修復を記録せず式のまま開く', () {
      final m = ErModel.empty();
      table(m, 't', [col(m, 'id', 'auto', pk: true)]).checks.add(CheckDef(id: m.allocateId(), expression: 'id > 0'));
      final map = PeroEncoder.toMap(m);
      map['formatVersion'] = 3;
      final ck = (((map['entities'] as List).single as Map)['checks'] as List).single as Map;
      ck
        ..remove('mode')
        ..remove('join')
        ..remove('conditions');
      final r = PeroDecoder.decode(PeroEncoder.encodeCompact(map));
      expect(r.repairs.items, isEmpty);
      expect(r.model!.tables.single.checks.single.mode, CheckMode.expression);
      expect(r.model!.tables.single.checks.single.expression, 'id > 0');
    });

    test('存在しない列の条件は、整合性確認で削除する', () {
      final m = _model(DbKind.postgresql);
      m.tables.single.checks[0].conditions.single.columnId = 99999;
      final r = PeroDecoder.decode(PeroEncoder.encode(m));
      expect(r.repairs.items.any((s) => s.contains('CHECK制約')), isTrue);
      expect(r.model!.tables.single.checks[0].conditions, isEmpty);
    });

    test('列の削除: 条件から外し、条件が0になる制約は削除する。影響の一覧にも出る', () {
      final m = _model(DbKind.postgresql);
      final t = m.tables.single;
      final qty = t.columns[1];
      final impacts = RemoveColumnCommand.impacts(m, t.id, qty.id);
      expect(impacts.where((s) => s.contains('CHECK制約')).length, 2);
      final h = historyOf(m);
      h.execute(RemoveColumnCommand(t.id, qty.id));
      final cur = m.tables.single;
      expect(cur.checks.length, 5); // between のみの制約が削除される
      expect(cur.checks.firstWhere((k) => k.join == CheckJoin.or).conditions.map((c) => c.operator), [CheckOperator.ne]);
      h.undo();
      expect(m.tables.single.checks.length, 6);
    });

    test('複製: 条件の列を新しい列のIDに付け替える', () {
      final m = _model(DbKind.postgresql);
      final d = m.diagrams.first;
      final src = m.tables.single;
      final paste = PasteEntitiesCommand(diagramId: d.id, data: ClipboardData.fromSelection(m, d, [src.id]));
      historyOf(m).execute(paste);
      final n = m.tableById(paste.createdIds.single)!;
      final newIds = n.columns.map((c) => c.id).toSet();
      for (final k in n.checks.where((k) => k.mode == CheckMode.conditions)) {
        expect(k.conditions.every((c) => newIds.contains(c.columnId)), isTrue);
      }
    });
  });
}
