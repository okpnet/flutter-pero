import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:project_er_operation/model/model.dart';
import 'package:project_er_operation/persistence/persistence.dart';

import '../support/sample_models.dart';

Map<String, dynamic> baseJson() => jsonDecode(PeroEncoder.encode(fullModel())) as Map<String, dynamic>;
LoadResult load(Map<String, dynamic> j) => PeroDecoder.decode(jsonEncode(j));
Map<String, dynamic> entity(Map<String, dynamic> j, String phys) =>
    (j['entities'] as List).firstWhere((e) => e['physicalName'] == phys) as Map<String, dynamic>;

void main() {
  test('JSONの構文エラーは修復できない', () {
    final r = PeroDecoder.decode('{ "a": ');
    expect(r.model, isNull);
    expect(r.error, contains('構文'));
  });

  test('formatVersion: 欠落は1とみなし、新しい場合は開かない', () {
    final j = baseJson()..remove('formatVersion');
    final r = load(j);
    expect(r.model, isNotNull);
    expect(r.repairs.items.any((s) => s.contains('formatVersion')), isTrue);
    final n = load(baseJson()..['formatVersion'] = 99);
    expect(n.model, isNull);
    expect(n.tooNew, isTrue);
  });

  test('必須キーの欠落は既定値に置換する', () {
    final j = baseJson();
    entity(j, 'customers').remove('comment');
    (j['properties'] as Map).remove('targetDb');
    final r = load(j);
    expect(r.model!.tableById(r.model!.entities.first.id)!.comment, '');
    expect(r.model!.properties.targetDb, DbKind.postgresql);
    expect(r.repairs.count, 2);
  });

  test('型の不一致と値域外は既定値に置換する', () {
    final j = baseJson();
    entity(j, 'customers')['locked'] = 'yes';
    (j['diagrams'] as List)[0]['pageSize'] = 'B5';
    (j['diagrams'] as List)[0]['view']['zoom'] = 99.0;
    (j['diagrams'] as List)[0]['pageRows'] = 0;
    final r = load(j);
    expect(r.model!.entityById(r.model!.entities.first.id)!.locked, isFalse);
    final d = r.model!.diagrams.first;
    expect(d.pageSize, PageSize.a3);
    expect(d.view.zoom, 1.0);
    expect(d.pageRows, 1);
    expect(r.repairs.count, 4);
  });

  test('標準に置き換えられないID・参照先の不正は項目を削除する', () {
    final j = baseJson();
    (entity(j, 'customers')['columns'] as List)[1]['id'] = 'x';
    final r = load(j);
    expect(r.model!.tables.firstWhere((t) => t.physicalName == 'customers').columns.length, 1);
    // 列が消えたので、その列を参照するビューの出力列も消える(参照切れの連鎖修復)
    expect(r.model!.views.first.join.columns.length, 1);
  });

  test('参照切れ: リレーションシップの端点、制約の列、配置、メソッドを削除/解除する', () {
    final j = baseJson();
    (j['relationships'] as List)[0]['parentId'] = 99999;
    (entity(j, 'orders')['indexes'] as List)[0]['columnIds'] = [99999];
    (j['diagrams'] as List)[0]['placements'].add({'entityId': 88888, 'x': 0, 'y': 0, 'collapsed': false});
    (entity(j, 'orders')['columns'] as List)[2]['defaultKind'] = 'method';
    (entity(j, 'orders')['columns'] as List)[2]['defaultMethodId'] = 77777;
    (entity(j, 'orders')['triggers'] as List)[0]['methodId'] = 66666;
    final r = load(j);
    final m = r.model!;
    expect(m.relationships, isEmpty);
    final orders = m.tables.firstWhere((t) => t.physicalName == 'orders');
    expect(orders.indexes, isEmpty);
    expect(orders.columns[2].defaultKind, DefaultKind.none);
    expect(orders.triggers.length, 1);
    expect(m.diagrams.first.placements.any((p) => p.entityId == 88888), isFalse);
  });

  test('共通列への参照は、パターンの列のIDが存在する限り削除しない', () {
    final m = fullModel();
    final orders = m.tables.firstWhere((t) => t.physicalName == 'orders');
    final commonId = m.patterns.first.columns.first.id;
    orders.uniques.add(ConstraintDef(id: m.allocateId(), columnIds: [commonId]));
    final r = PeroDecoder.decode(PeroEncoder.encode(m));
    final o2 = r.model!.tables.firstWhere((t) => t.physicalName == 'orders');
    expect(o2.uniques.last.columnIds, [commonId]);
    expect(r.repairs.items, isEmpty);
  });

  test('IDの重複は後の要素を削除し、nextIdを修正する', () {
    final j = baseJson();
    final cust = entity(j, 'customers');
    final dup = Map<String, dynamic>.from(jsonDecode(jsonEncode(cust)) as Map);
    dup['physicalName'] = 'dup';
    (j['entities'] as List).add(dup);
    j['nextId'] = 2;
    final r = load(j);
    expect(r.model!.tables.any((t) => t.physicalName == 'dup'), isFalse);
    expect(r.model!.nextId, greaterThan(r.model!.entities.map((e) => e.id).reduce((a, b) => a > b ? a : b)));
  });

  test('標準型が不足していれば補う', () {
    final j = baseJson();
    (j['types'] as List).removeWhere((t) => t['id'] == 'uuid');
    final r = load(j);
    expect(r.model!.typeById('uuid'), isNotNull);
    expect(r.repairs.items.any((s) => s.contains('uuid')), isTrue);
  });

  test('列の型が存在しない場合は列を削除する', () {
    final j = baseJson();
    (entity(j, 'orders')['columns'] as List)[2]['typeId'] = 'nothing';
    final r = load(j);
    expect(r.model!.tables.firstWhere((t) => t.physicalName == 'orders').columns.length, 3);
  });

  test('ダイアグラムが無ければ追加する', () {
    final j = baseJson()..['diagrams'] = [];
    final r = load(j);
    expect(r.model!.diagrams.length, 1);
  });

  test('修復したファイルを開くと .bak に退避する', () async {
    final dir = Directory.systemTemp.createTempSync('pero_bak');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}${Platform.pathSeparator}b.pero';
    final j = baseJson()..remove('formatVersion');
    File(path).writeAsStringSync(jsonEncode(j));
    final r = await PeroFile.open(path);
    expect(r.model, isNotNull);
    expect(File('$path.bak').existsSync(), isTrue);
  });

  test('修復を含まないファイルでは .bak を作らない', () async {
    final dir = Directory.systemTemp.createTempSync('pero_nobak');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}${Platform.pathSeparator}c.pero';
    File(path).writeAsStringSync(PeroEncoder.encode(fullModel()));
    final r = await PeroFile.open(path);
    expect(r.repairs.isEmpty, isTrue);
    expect(File('$path.bak').existsSync(), isFalse);
  });

  test('保存時の整合性確認で参照切れを修復してから保存する', () async {
    final dir = Directory.systemTemp.createTempSync('pero_savefix');
    addTearDown(() => dir.deleteSync(recursive: true));
    final m = fullModel();
    m.relationships.first.parentId = 424242;
    final s = await PeroFile.save(m, '${dir.path}${Platform.pathSeparator}d.pero');
    expect(s.isOk, isTrue);
    expect(s.repairs.isEmpty, isFalse);
    expect(m.relationships, isEmpty);
  });
}
