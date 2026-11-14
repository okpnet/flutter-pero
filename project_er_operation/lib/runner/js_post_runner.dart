import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:flutter_js/flutter_js.dart';

import '../generation/generation.dart';

/// flutter_js(QuickJS)でポストファイルを実行する。別Isolateで実行し、UIをブロックしない(2-13)。
/// ポストファイルのファイル、ネットワーク、タイマーは使えない(JS側で無効化する)。
/// ホスト関数を持たないため、`console.log` はJS側で集めて戻り値に載せて通知する(Adapter パターン)。
class JsPostRunner implements PostRunner {
  @override
  Future<String> run({
    required String script,
    required String jsonText,
    required Duration timeout,
    void Function(String message)? onLog,
    String? library,
  }) async {
    final result = ReceivePort();
    final errors = ReceivePort();
    final done = Completer<Object?>();
    result.listen((m) {
      if (!done.isCompleted) done.complete(m);
    });
    errors.listen((e) {
      if (!done.isCompleted) done.complete({'fatal': '$e'});
    });
    final isolate = await Isolate.spawn<List<Object?>>(
      _entry,
      [result.sendPort, _wrap(script, jsonText, library), timeout.inMilliseconds],
      onError: errors.sendPort,
      errorsAreFatal: true,
    );
    final Object? raw;
    try {
      // JS側の中断(timeout)が効かない場合に備え、Dart側でも待ち時間に上限を設ける。
      raw = await done.future.timeout(timeout + const Duration(seconds: 2));
    } on TimeoutException {
      throw PostException('ポストファイルの実行がタイムアウトしました(${timeout.inSeconds}秒)');
    } finally {
      isolate.kill(priority: Isolate.immediate);
      result.close();
      errors.close();
    }
    if (raw is! Map) throw PostException('ポストファイルの実行結果が不正です');
    if (raw['fatal'] != null) {
      throw PostException('ポストファイルの実行に失敗しました: ${raw['fatal']}');
    }
    if (raw['error'] != null) {
      final msg = '${raw['error']}';
      if (msg.contains('interrupted')) {
        throw PostException('ポストファイルの実行がタイムアウトしました(${timeout.inSeconds}秒)');
      }
      throw PostException(msg);
    }
    final r = jsonDecode(raw['value'] as String) as Map<String, dynamic>;
    for (final l in (r['logs'] as List? ?? const [])) {
      onLog?.call('$l');
    }
    if (r['ok'] != true) {
      throw PostException('${r['message']}', stack: r['stack'] as String?);
    }
    return r['result'] as String;
  }

  /// 実行するJS。`main(jsonText)` を呼び、結果をJSON文字列で返す。
  static String _wrap(String script, String jsonText, String? library) => '''
(function () {
  var __logs = [];
  var console = { log: function () {
    __logs.push(Array.prototype.slice.call(arguments).map(String).join(' '));
  } };
  // ファイル、ネットワーク、タイマーは使えない(9.6-4)
  var setTimeout, setInterval, setImmediate, clearTimeout, clearInterval, fetch, XMLHttpRequest, sendMessage;
  try {
${library ?? ''}
    ;
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
}

/// Isolateの入口。QuickJSのランタイムは、このIsolate内で生成して破棄する。
void _entry(List<Object?> args) {
  final port = args[0] as SendPort;
  final code = args[1] as String;
  final timeoutMs = args[2] as int;
  QuickJsRuntime2? rt;
  try {
    rt = QuickJsRuntime2(timeout: timeoutMs, stackSize: 1024 * 1024);
    final r = rt.evaluate(code);
    port.send(r.isError ? {'error': r.stringResult} : {'value': r.stringResult});
  } on Object catch (e) {
    port.send({'fatal': '$e'});
  } finally {
    try {
      rt?.dispose();
    } on Object {
      // 破棄の失敗は結果に影響しない。
    }
  }
}
