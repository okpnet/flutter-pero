import '../model/model.dart';

/// 画面に表示するデータベースの種類(kind)。ポストファイルがある種類だけを表示するために使う
/// (対象DBのプルダウン、メソッド・型・トリガーの対象DBごとのタブ)。
/// セッションがポストファイルの一覧から更新する。未設定(null)のときは、すべての種類を表示する。
abstract final class DbKindFilter {
  static Set<DbKind>? _visible;

  static List<DbKind> get visible => [
        for (final k in DbKind.values)
          if (_visible == null || _visible!.contains(k)) k
      ];

  static set visibleKinds(Set<DbKind>? kinds) => _visible = (kinds == null || kinds.isEmpty) ? null : kinds;
}
