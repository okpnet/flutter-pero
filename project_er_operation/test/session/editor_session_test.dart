import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:project_er_operation/command/command.dart';
import 'package:project_er_operation/model/model.dart';
import 'package:project_er_operation/persistence/persistence.dart';

import '../support/sample_models.dart';
import '../support/session_support.dart';

void main() {
  late Directory dir;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('pero_sess');
    addTearDown(() => dir.deleteSync(recursive: true));
  });
  String p(String n) => '${dir.path}${Platform.pathSeparator}$n';

  test('新規モデルの初期状態(4.1-1): ダイアグラム1、1×1、型は設定の複製、対象DBはpostgresql', () {
    final s = newSession();
    final m = s.model;
    expect(m.diagrams.single.name, 'ダイアグラム1');
    expect((m.diagrams.single.pageRows, m.diagrams.single.pageCols), (1, 1));
    expect(m.types.length, standardTypes().length);
    expect(identical(m.types.first, s.settings.typeTable.first), isFalse);
    expect(m.properties.targetDb, DbKind.postgresql);
    expect(m.methods, isEmpty);
    expect(m.patterns, isEmpty);
    expect(s.isDirty, isFalse);
    expect(s.filePath, isNull);
  });

  test('保存で未保存状態が解除され、最近使ったファイルとキャッシュの基点が更新される', () async {
    final s = newSession();
    s.run(AddTableCommand(diagramId: s.diagram.id, x: 10, y: 10));
    expect(s.isDirty, isTrue);
    final r = await s.save(p('a.pero'));
    expect(r.isOk, isTrue);
    expect(s.isDirty, isFalse);
    expect(s.filePath, p('a.pero'));
    expect(s.settings.recentFiles.first, p('a.pero'));
    expect(s.settings.lastFolder, dir.path);
    expect(s.cache.read()!.journal, isEmpty);
    // 保存後の操作はキャッシュに差分が記録される
    s.run(AddTableCommand(diagramId: s.diagram.id, x: 10, y: 10));
    expect(s.cache.read()!.journal.length, 1);
    s.undo();
    expect(s.cache.read()!.journal.length, 2);
  });

  test('一度も保存していないモデルの操作はキャッシュに記録しない', () {
    final s = newSession();
    s.run(AddTableCommand(diagramId: s.diagram.id, x: 10, y: 10));
    expect(s.cache.read(), isNull);
  });

  test('ファイルを開く: 履歴をクリアし、未保存でなく、最近使ったファイルに記録する', () async {
    final m = fullModel();
    await PeroFile.save(m, p('b.pero'));
    final s = newSession();
    s.run(AddTableCommand(diagramId: s.diagram.id, x: 0, y: 0));
    final r = await s.open(p('b.pero'));
    expect(r.model, isNotNull);
    expect(s.isDirty, isFalse);
    expect(s.history.canUndo, isFalse);
    expect(s.model.tables.length, 2);
    expect(s.settings.recentFiles, [p('b.pero')]);
  });

  test('壊れたファイルを開いたときは現在のモデルを維持する', () async {
    File(p('bad.pero')).writeAsStringSync('{ not json');
    final s = newSession();
    s.run(AddTableCommand(diagramId: s.diagram.id, x: 0, y: 0));
    final r = await s.open(p('bad.pero'));
    expect(r.model, isNull);
    expect(s.model.tables.length, 1);
    expect(s.isDirty, isTrue);
  });

  test('コピー・貼り付け・複製とクリップボードのクリア', () {
    final s = newSession(model: fullModel());
    final cust = s.model.tables.firstWhere((t) => t.physicalName == 'customers');
    s.setSelection([cust.id]);
    s.copySelection();
    expect(s.paste(), isTrue);
    expect(s.model.tables.any((t) => t.physicalName == 'customers_copy'), isTrue);
    expect(s.selection.length, 1);
    s.setSelection([cust.id]);
    s.duplicateSelection();
    expect(s.model.tables.where((t) => t.physicalName.startsWith('customers_copy')).length, 2);
    s.newModel();
    expect(s.clipboard, isNull);
  });

  test('バックアップ: 変更があれば保存済みファイルをバックアップし、保存期間を超えたものを削除する', () async {
    final s = newSession();
    s.settings.backupFolder = p('bk');
    s.backupNow(); // 一度も保存していないので何もしない
    expect(Directory(p('bk')).existsSync(), isFalse);
    await s.save(p('c.pero'));
    s.run(AddTableCommand(diagramId: s.diagram.id, x: 0, y: 0));
    s.backupNow();
    final files = Directory(p('bk')).listSync().whereType<File>().toList();
    expect(files.length, 1);
    expect(files.single.path, matches(r'c_\d{8}_\d{6}\.pero$'));
    s.backupNow(); // 変更がなければ作らない
    expect(Directory(p('bk')).listSync().length, 1);
    // 保存期間を超えたものは削除
    final old = File(p('bk/old_20200101_000000.pero'))..writeAsStringSync('x');
    old.setLastModifiedSync(DateTime.now().subtract(const Duration(days: 10)));
    s.purgeOldBackups(p('bk'));
    expect(old.existsSync(), isFalse);
    expect(Directory(p('bk')).listSync().length, 1);
  });

  test('復元したモデルは未保存の状態で開く', () {
    final s = newSession();
    s.openRecovered(fullModel(), r'C:\x\y.pero');
    expect(s.isDirty, isTrue);
    expect(s.filePath, r'C:\x\y.pero');
  });

  test('ダイアログが書き込む保存(saveVia): 整合性確認済みのバイト列を渡し、成功で未保存を解除する', () async {
    final s = newSession(model: fullModel());
    s.run(AddTableCommand(diagramId: s.diagram.id, x: 0, y: 0));
    expect(s.isDirty, isTrue);
    Uint8List? got;
    final r = await s.saveVia((bytes) async {
      got = bytes;
      final path = p('via.pero');
      return (await PeroFile.writeAtomically(path, bytes, Repairs())).isOk ? path : null;
    });
    expect(r!.isOk, isTrue);
    expect(s.isDirty, isFalse);
    expect(s.filePath, p('via.pero'));
    expect(String.fromCharCodes(got!).startsWith('{\n  "formatVersion": 1'), isTrue);
    expect((await PeroFile.open(p('via.pero'))).model, isNotNull);
    expect(File(p('via.pero.tmp')).existsSync(), isFalse);
  });

  test('保存先の選択をキャンセルしたとき(saveVia)は null を返し、状態を変えない', () async {
    final s = newSession();
    s.run(AddTableCommand(diagramId: s.diagram.id, x: 0, y: 0));
    final r = await s.saveVia((_) async => null);
    expect(r, isNull);
    expect(s.isDirty, isTrue);
    expect(s.filePath, isNull);
  });
}
