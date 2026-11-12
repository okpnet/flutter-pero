import 'dart:convert';

import 'package:flutter_qjs/flutter_qjs.dart';

import '../generation/generation.dart';

/// QuickJS(flutter_qjs)でポストファイルを実行する。別Isolateで実行し、UIをブロックしない(2-13)。
/// ポストファイルのファイル、ネットワーク、タイマーは使えない。
/// ホスト関数を持たないため、`console.log` はJS側で集めて戻り値に載せて通知する(Adapter パターン)。
class QjsPostRunner implements PostRunner {
  @override
  Future<String> run({
    required String script,
    required String jsonText,
    required Duration timeout,
    void Function(String message)? onLog,
  }) async {
    // timeout はJS実行の割込み(ms)。Dart側でも待ち時間に上限を設ける。
    final engine = IsolateQjs(timeout: timeout.inMilliseconds, stackSize: 1024 * 1024);
    try {
      final wrapped = '''
(function () {
  var __logs = [];
  var console = { log: function () {
    __logs.push(Array.prototype.slice.call(arguments).map(String).join(' '));
  } };
  try {
$script
    ;
    var __r = main(${jsonEncode(jsonText)});
    if (typeof __r !== 'string') {
      return JSON.stringify({ ok: false, message: 'main の戻り値が文字列ではありません', logs: __logs });
    }
    return JSON.stringify({ ok: true, result: __r, logs: __logs });
  } catch (e) {
    return JSON.stringify({
      ok: false,
      message: String(e && e.message !== undefined ? e.message : e),
      stack: String(e && e.stack ? e.stack : ''),
      logs: __logs
    });
  }
})()
''';
      final Object? raw;
      try {
        raw = await engine.evaluate(wrapped, name: 'post.js').timeout(timeout + const Duration(seconds: 2));
      } on JSError catch (e) {
        throw PostException(e.message, stack: e.stack);
      } on Exception catch (e) {
        throw PostException('ポストファイルの実行に失敗しました(タイムアウトの可能性があります): $e');
      }
      if (raw is! String) throw PostException('ポストファイルの実行結果が不正です');
      final r = jsonDecode(raw) as Map<String, dynamic>;
      for (final l in (r['logs'] as List? ?? const [])) {
        onLog?.call('$l');
      }
      if (r['ok'] != true) {
        throw PostException('${r['message']}', stack: r['stack'] as String?);
      }
      return r['result'] as String;
    } finally {
      engine.close();
    }
  }
}
