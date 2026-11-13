import 'dart:io';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:project_er_operation/persistence/persistence.dart';

import '../support/sample_models.dart';

void main() {
  late Directory dir;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('pero_open');
    addTearDown(() => dir.deleteSync(recursive: true));
  });
  String p(String name) => '${dir.path}${Platform.pathSeparator}$name';

  test('ファイルを開く(別Isolateで読み込み、復元して返す)。全種類のオブジェクトが復元される', () async {
    final m = fullModel();
    File(p('a.pero')).writeAsStringSync(PeroEncoder.encode(m));
    final r = await PeroFile.open(p('a.pero'));
    expect(r.model, isNotNull);
    expect(r.repairs.isEmpty, isTrue);
    expect(PeroEncoder.encode(r.model!), PeroEncoder.encode(m));
  });

  test('存在しない、UTF-8でない、JSONでないファイルは、エラーの文言を返す', () async {
    final none = await PeroFile.open(p('none.pero'));
    expect(none.model, isNull);
    expect(none.error, contains('読込に失敗しました'));
    File(p('bin.pero')).writeAsBytesSync([0xff, 0xfe, 0x00, 0x80]);
    final bin = await PeroFile.open(p('bin.pero'));
    expect(bin.model, isNull);
    expect(bin.error, isNotNull);
    File(p('bad.pero')).writeAsStringSync('{ not json');
    final bad = await PeroFile.open(p('bad.pero'));
    expect(bad.model, isNull);
    expect(bad.error, contains('JSONの構文エラー'));
  });

  test('修復があったときは、元のファイルを .bak に退避する', () async {
    final text = PeroEncoder.encode(fullModel()).replaceFirst('"targetDb": "postgresql"', '"targetDb": "oracle"');
    File(p('r.pero')).writeAsStringSync(text);
    final r = await PeroFile.open(p('r.pero'));
    expect(r.model, isNotNull);
    expect(r.repairs.isEmpty, isFalse);
    expect(File(p('r.pero.bak')).readAsStringSync(), text);
  });

  test('BOM付きでも開ける', () async {
    File(p('bom.pero')).writeAsStringSync('\u{feff}${PeroEncoder.encode(fullModel())}');
    expect((await PeroFile.open(p('bom.pero'))).model, isNotNull);
  });

  test('復元の結果(モデル全体)は、別Isolateから受け取れる(受け取れずに同じIsolateへ戻る動作に頼っていない)', () async {
    final text = PeroEncoder.encode(fullModel());
    final r = await Isolate.run(() => PeroDecoder.decode(text));
    expect(r.model, isNotNull);
    expect(PeroEncoder.encode(r.model!), text);
  });
}
