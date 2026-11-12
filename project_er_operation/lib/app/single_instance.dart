import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

/// 単一インスタンス(2-14)。2つ目の起動は、既存のウィンドウへ引数(ファイルパス)を渡して終了する。
///
/// - 先に起動した側が、ディレクトリ内の `instance.lock` に排他ロックを取る。ロックはOSが管理するため、
///   異常終了しても残らない(古いロックの判定が不要)。
/// - 先に起動した側は、ループバックのみで待ち受け(`ServerSocket`)、ポート番号と合言葉を `instance.port` に書く。
/// - 2つ目は、`instance.port` を読んで接続し、合言葉と引数をJSON1行で送る。受理の応答を受け取ったら終了する。
class SingleInstance {
  SingleInstance._(this._lock, this._server, this._token, this._dir);

  final RandomAccessFile _lock;
  final ServerSocket _server;
  final String _token;
  final String _dir;
  final StreamController<List<String>> _messages = StreamController.broadcast();
  StreamSubscription<Socket>? _sub;

  static String _path(String dir, String name) => '$dir${Platform.pathSeparator}$name';

  /// 引数(ファイルパスなど)を既存のインスタンスへ渡せたときは null を返す(呼び出し側は終了する)。
  /// 既存のインスタンスが無い(または応答しない)ときは、自分が最初のインスタンスとして [SingleInstance] を返す。
  static Future<SingleInstance?> acquire({
    required String dir,
    required List<String> args,
    Duration handoverTimeout = const Duration(seconds: 3),
  }) async {
    Directory(dir).createSync(recursive: true);
    final lockFile = File(_path(dir, 'instance.lock'));
    RandomAccessFile? lock;
    try {
      lock = await lockFile.open(mode: FileMode.write);
      await lock.lock(FileLock.exclusive); // 取れなければ例外(既に他のインスタンスが持っている)
    } on FileSystemException {
      await lock?.close();
      lock = null;
    }

    if (lock == null) {
      // 2つ目以降: 既存のインスタンスへ引数を渡す。
      if (await _handover(dir, args, handoverTimeout)) return null;
      // 既存のインスタンスが応答しない(固まっている等)。起動できなくなることを避けるため、単独で起動する。
      return _standalone(dir);
    }

    final token = _newToken();
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final inst = SingleInstance._(lock, server, token, dir);
    inst._publish();
    inst._sub = server.listen(inst._onClient, onError: (_) {});
    return inst;
  }

  /// ロックを共有できないときの起動(渡せなかった場合)。待受けは行わない。
  static Future<SingleInstance> _standalone(String dir) async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final inst = SingleInstance._(await File(_path(dir, 'standalone.lock')).open(mode: FileMode.write), server, _newToken(), dir);
    inst._sub = server.listen((s) => s.destroy(), onError: (_) {});
    return inst;
  }

  static String _newToken() {
    final r = Random.secure();
    return List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }

  void _publish() {
    final tmp = File(_path(_dir, 'instance.port.tmp'));
    tmp.writeAsStringSync('${_server.port}\n$_token\n', flush: true);
    tmp.renameSync(_path(_dir, 'instance.port'));
  }

  static Future<bool> _handover(String dir, List<String> args, Duration timeout) async {
    final deadline = DateTime.now().add(timeout);
    final portFile = File(_path(dir, 'instance.port'));
    while (DateTime.now().isBefore(deadline)) {
      // 先に起動した側がポート情報を書き終えるまで、少し待つ。
      if (portFile.existsSync()) {
        try {
          final lines = portFile.readAsLinesSync();
          final port = int.parse(lines[0]);
          final token = lines[1];
          final socket = await Socket.connect(InternetAddress.loopbackIPv4, port, timeout: const Duration(seconds: 1));
          socket.writeln(jsonEncode({'token': token, 'args': args}));
          await socket.flush();
          final ack = await socket.cast<List<int>>().transform(utf8.decoder).transform(const LineSplitter()).first.timeout(
                const Duration(seconds: 2),
                onTimeout: () => '',
              );
          socket.destroy();
          if (ack == 'OK') return true;
        } on Object {
          // 読み取り中の更新、接続失敗: 再試行する。
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    return false;
  }

  void _onClient(Socket s) {
    s.cast<List<int>>().transform(utf8.decoder).transform(const LineSplitter()).first.timeout(const Duration(seconds: 2)).then((line) {
      final j = jsonDecode(line) as Map<String, dynamic>;
      if (j['token'] != _token) {
        s.destroy();
        return;
      }
      final args = [for (final a in (j['args'] as List)) '$a'];
      s.writeln('OK');
      s.flush().whenComplete(s.destroy);
      if (!_messages.isClosed) _messages.add(args);
    }).catchError((Object _) {
      s.destroy();
    });
  }

  /// 2つ目の起動から渡された引数。
  Stream<List<String>> get messages => _messages.stream;

  /// 終了処理: 待受けを止め、ポート情報を消し、ロックを解放する。
  Future<void> close() async {
    await _sub?.cancel();
    await _server.close();
    await _messages.close();
    try {
      File(_path(_dir, 'instance.port')).deleteSync();
    } on FileSystemException {
      // 消えていなくても、次の起動はロックで判定するため問題ない。
    }
    try {
      await _lock.unlock();
    } on FileSystemException {
      // 解放できなくてもプロセス終了でOSが解放する。
    }
    await _lock.close();
  }
}
