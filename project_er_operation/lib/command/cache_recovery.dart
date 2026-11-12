import '../model/model.dart';
import '../persistence/persistence.dart';
import 'command_base.dart';
import 'command_factory.dart';

/// キャッシュの復元結果。
class RecoveryResult {
  RecoveryResult.ok(this.model, this.repairs) : error = null;
  RecoveryResult.fail(this.error)
      : model = null,
        repairs = Repairs();
  final ErModel? model;
  final Repairs repairs;
  final String? error;
}

/// `base.pero` に `commands.jsonl` を順に再生して復元する(9.2-4)。
/// 再生の失敗は [RecoveryResult.fail]。
RecoveryResult recoverFromCache(CacheState state, EntityLayouter Function(ErModel) layouter) {
  final base = PeroDecoder.decode(state.baseText);
  final model = base.model;
  if (model == null) return RecoveryResult.fail(base.error);
  try {
    final h = CommandHistory(CommandContext(model, () => layouter(model)), limit: 1 << 30);
    replayJournal(h, state.journal);
    final (ok, repairs) = IntegrityRepairer.repairAll(model);
    if (!ok) return RecoveryResult.fail('整合性を回復できませんでした');
    return RecoveryResult.ok(model, repairs);
  } on Object catch (e) {
    return RecoveryResult.fail('再生に失敗しました: $e');
  }
}
