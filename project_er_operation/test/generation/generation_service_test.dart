import 'package:flutter_test/flutter_test.dart';
import 'package:project_er_operation/generation/generation.dart';
import 'package:project_er_operation/model/model.dart';

import '../support/sample_models.dart';

class _CountingRunner implements PostRunner {
  int calls = 0;
  String? json;

  @override
  Future<String> run({
    required String script,
    required String jsonText,
    required Duration timeout,
    void Function(String message)? onLog,
    String? library,
  }) async {
    calls++;
    json = jsonText;
    return 'OUT';
  }
}

void main() {
  test('生成前検証と生成用JSONの作成は別Isolateで行い、結果(モデル・エラー・警告)を受け取れる', () async {
    final m = ErModel.empty();
    table(m, 'users', [col(m, 'id', 'auto', pk: true)]);
    final runner = _CountingRunner();
    final out = await GenerationService(runner).generate(m, '// post', timeout: const Duration(seconds: 5));
    expect(out.isOk, isTrue);
    expect(out.text, 'OUT');
    expect(runner.calls, 1);
    expect(runner.json, contains('"physicalName": "users"').or(contains('"physicalName":"users"')));
  });

  test('検証エラーがあるときは、ポストファイルを実行せず、エラーの一覧を返す', () async {
    final m = ErModel.empty();
    table(m, '', [col(m, 'id', 'auto', pk: true)]); // 物理名が空
    final runner = _CountingRunner();
    final out = await GenerationService(runner).generate(m, '// post', timeout: const Duration(seconds: 5));
    expect(out.isOk, isFalse);
    expect(out.errors, isNotEmpty);
    expect(runner.calls, 0);
  });

  test('prepareGeneration: 警告だけのモデルは、警告を返してJSONを作る', () {
    final m = ErModel.empty();
    table(m, 'no_pk', [col(m, 'name', 'text')]); // 主キーなし(警告)
    final p = prepareGeneration(m, r'^[A-Za-z_][A-Za-z0-9_]*$', const PkNaming(), false);
    expect(p.errors, isEmpty);
    expect(p.warnings, isNotEmpty);
    expect(p.jsonText, isNotNull);
  });
}

extension _OrMatcher on Matcher {
  Matcher or(Matcher other) => anyOf(this, other);
}
