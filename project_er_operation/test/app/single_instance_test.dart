import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:project_er_operation/app/single_instance.dart';

void main() {
  late Directory dir;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('pero_single');
    addTearDown(() {
      try {
        dir.deleteSync(recursive: true);
      } on FileSystemException {
        // 開いたままのファイルがあれば無視する。
      }
    });
  });

  test('最初の起動は単一インスタンスになる。2つ目は引数を渡して null(終了)になる', () async {
    final first = await SingleInstance.acquire(dir: dir.path, args: []);
    expect(first, isNotNull);
    final received = Completer<List<String>>();
    first!.messages.listen(received.complete);
    final second = await SingleInstance.acquire(dir: dir.path, args: [r'C:\work\a.pero']);
    expect(second, isNull);
    expect(await received.future.timeout(const Duration(seconds: 5)), [r'C:\work\a.pero']);
    await first.close();
  });

  test('2つ目の起動を何度繰り返しても、すべて最初のインスタンスへ渡される', () async {
    final first = (await SingleInstance.acquire(dir: dir.path, args: []))!;
    final got = <List<String>>[];
    first.messages.listen(got.add);
    for (var i = 0; i < 3; i++) {
      expect(await SingleInstance.acquire(dir: dir.path, args: ['f$i.pero']), isNull);
    }
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(got, [['f0.pero'], ['f1.pero'], ['f2.pero']]);
    await first.close();
  });

  test('引数なしの2つ目の起動も受理される(ウィンドウを前面に出すだけ)', () async {
    final first = (await SingleInstance.acquire(dir: dir.path, args: []))!;
    final got = <List<String>>[];
    first.messages.listen(got.add);
    expect(await SingleInstance.acquire(dir: dir.path, args: []), isNull);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(got, [<String>[]]);
    await first.close();
  });

  test('終了(close)した後の起動は、新しい単一インスタンスになる。ポート情報は削除される', () async {
    final first = (await SingleInstance.acquire(dir: dir.path, args: []))!;
    await first.close();
    expect(File('${dir.path}/instance.port').existsSync(), isFalse);
    final again = await SingleInstance.acquire(dir: dir.path, args: ['x.pero']);
    expect(again, isNotNull);
    await again!.close();
  });

  test('古いポート情報(異常終了の残り)があっても、ロックが取れれば単一インスタンスになる', () async {
    File('${dir.path}/instance.port').writeAsStringSync('1\nstale\n'); // 誰も待ち受けていない
    final first = await SingleInstance.acquire(dir: dir.path, args: []);
    expect(first, isNotNull);
    // ポート情報は新しいものに置き換わり、2つ目はそれを使える
    final got = Completer<List<String>>();
    first!.messages.listen(got.complete);
    expect(await SingleInstance.acquire(dir: dir.path, args: ['a.pero']), isNull);
    expect(await got.future.timeout(const Duration(seconds: 5)), ['a.pero']);
    await first.close();
  });

  test('合言葉が違う接続は受理しない(同じPCの他のプロセスからの不正な入力を無視する)', () async {
    final first = (await SingleInstance.acquire(dir: dir.path, args: []))!;
    var count = 0;
    first.messages.listen((_) => count++);
    final port = int.parse(File('${dir.path}/instance.port').readAsLinesSync().first);
    final s = await Socket.connect(InternetAddress.loopbackIPv4, port);
    s.writeln('{"token":"wrong","args":["evil.pero"]}');
    await s.flush();
    final reply = await s.cast<List<int>>().fold<List<int>>([], (a, b) => a..addAll(b));
    s.destroy();
    expect(String.fromCharCodes(reply).contains('OK'), isFalse);
    s.destroy();
    s.close();
    final s2 = await Socket.connect(InternetAddress.loopbackIPv4, port);
    s2.writeln('これはJSONではない');
    await s2.flush();
    s2.destroy();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(count, 0);
    await first.close();
  });
}
