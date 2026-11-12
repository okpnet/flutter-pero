import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:project_er_operation/persistence/persistence.dart';

import '../support/sample_models.dart';

void main() {
  test('全種類のオブジェクトを含むモデルが、保存→復元で変化しない', () {
    final m = fullModel();
    final text = PeroEncoder.encode(m);
    final r = PeroDecoder.decode(text);
    expect(r.error, isNull);
    expect(r.repairs.items, isEmpty);
    expect(PeroEncoder.encode(r.model!), text);
  });

  test('保存形式: インデント2、末尾LF、キー順は付録Aのとおり', () {
    final text = PeroEncoder.encode(fullModel());
    expect(text.contains('\r'), isFalse);
    expect(text.startsWith('{\n  "formatVersion": 2,\n  "appVersion"'), isTrue);
    final keys = RegExp(r'^  "(\w+)"', multiLine: true).allMatches(text).map((x) => x.group(1)).toList();
    expect(keys, [
      'formatVersion', 'appVersion', 'id', 'nextId', 'properties', 'types', 'methods',
      'commonColumnPatterns', 'entities', 'relationships', 'diagrams'
    ]);
  });

  test('未知のキーは保持して書き戻す', () {
    final text = PeroEncoder.encode(fullModel()).replaceFirst('{\n', '{\n  "future": {"a": 1},\n');
    final r = PeroDecoder.decode(text);
    expect(r.model!.unknownKeys.containsKey('future'), isTrue);
    expect(PeroEncoder.encode(r.model!).contains('"future"'), isTrue);
  });

  test('ファイルへ保存して読み込める(一時ファイル経由)', () async {
    final dir = Directory.systemTemp.createTempSync('pero_test');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}${Platform.pathSeparator}a.pero';
    final m = fullModel();
    final s = await PeroFile.save(m, path);
    expect(s.isOk, isTrue);
    expect(File('$path.tmp').existsSync(), isFalse);
    final r = await PeroFile.open(path);
    expect(r.model, isNotNull);
    expect(PeroEncoder.encode(r.model!), PeroEncoder.encode(m));
  });
}
