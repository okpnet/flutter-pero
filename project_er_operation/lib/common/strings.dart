/// UI文言(2-16)。将来の多言語化に備えて1か所に集約する。
class Strings {
  Strings._();

  static const appName = 'PERO';
  static const untitled = '無題';

  // メニュー
  static const menuFile = 'ファイル';
  static const menuOperation = '操作';
  static const menuRun = 'RUN';
  static const fileNew = '新規作成';
  static const fileOpen = 'ファイルを開く';
  static const fileSave = '上書き保存';
  static const fileSaveAs = 'ファイルに保存';
  static const fileRecent = '最近使ったファイル';
  static const fileSettings = '設定';
  static const fileImportSql = 'SQLインポート';
  static const fileExit = '終了';
  static const opUndo = '元に戻す';
  static const opRedo = 'やり直し';
  static const opAddTable = 'テーブルの追加';
  static const opAddJoinView = 'ビューの追加(結合ビュー)';
  static const opAddFunctionView = 'ビューの追加(関数ビュー)';
  static const opAddSqlView = 'ビューの追加(SQLビュー)';
  static const opRemoveFromDiagram = 'このダイアグラムから外す';
  static const opDeleteFromModel = 'モデルから削除';
  static const opAddRelationship = 'リレーションシップの追加';
  static const opRemoveRelationship = 'リレーションシップの削除';
  static const opCopy = 'コピー';
  static const opPaste = '貼り付け';
  static const opDuplicate = '複製';
  static const opSelectAll = '全選択';
  static const opAutoLayout = '自動配置';
  static const hideSideMenu = 'サイドメニューを隠す';
  static const showSideMenu = 'サイドメニューを表示';
  static const hideRightPane = 'プロパティを隠す';
  static const showRightPane = 'プロパティを表示';
  static String loadingFile(String name) => '$name を読み込み中…';
  static const generating = '生成しています…';
  static const importingSql = 'SQLを取り込んでいます…';
  static const tabScrollLeft = 'タブを左へ';
  static const tabScrollRight = 'タブを右へ';
  static const generateCanceled = '生成ファイルの保存を中止しました';
  static const autoLayoutNothing = '自動配置の対象がありません';
  static const autoLayoutFailed = '自動配置に失敗しました';
  static String autoLayoutDone(int n) => '自動配置: $n件を配置しました';
  static const opManageMethods = 'メソッド管理';
  static const opManagePatterns = '共通列パターン管理';
  static const opManageTypes = '型管理';
  static const opLock = 'ロック';
  static const opUnlock = 'ロック解除';
  static const opAddDiagram = 'ダイアグラムの追加';
  static const opRenameDiagram = 'ダイアグラム名の変更';
  static const opDeleteDiagram = 'ダイアグラムの削除';
  static const opShowInDiagram = '表示するダイアグラム';
  static const opEditProperty = 'プロパティ編集';
  static const runGenerate = '生成実行';
  static const runJson = 'JSON出力';
  static const runImage = '画像出力';

  // サイドメニュー
  static const sideTable = 'テーブル';
  static const sideJoinView = '結合ビュー';
  static const sideFunctionView = '関数ビュー';
  static const sideSqlView = 'SQLビュー';
  static const sideTabAdd = '追加';
  static const searchHint = '検索';
  static const searchRegex = '正規表現';
  static const searchPrev = '前のヒットへ(Shift+Enter)';
  static const searchNext = '次のヒットへ(Enter)';
  static const searchHitCount = '件ヒット';
  static const searchInvalidRegex = '正規表現が不正です';

  // ダイアログ・メッセージ
  static const save = '保存';
  static const dontSave = '保存しない';
  static const cancel = 'キャンセル';
  static const ok = 'OK';
  static const yes = 'はい';
  static const no = 'いいえ';
  static const apply = '適用';
  static const close = '閉じる';
  static const unsavedTitle = '未保存の変更';
  static const unsavedMessage = '変更を保存しますか?';
  static const restoreTitle = '復元';
  static const restoreMessage = '前回は異常終了しました。編集中の内容を復元しますか?';
  static const error = 'エラー';
  static const warning = '警告';
  static const confirm = '確認';
  static const tableListHeader = 'テーブルリスト';
  static const search = '検索';
  static const selectedCount = '個選択';
  static const diagramPrefix = 'ダイアグラム';
}
