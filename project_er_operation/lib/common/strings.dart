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
  static const fileExit = '終了';
  static const opUndo = '元に戻す';
  static const opRedo = 'やり直し';
  static const opAddTable = 'テーブルの追加';
  static const opAddJoinView = 'ビューの追加(結合ビュー)';
  static const opAddFunctionView = 'ビューの追加(関数ビュー)';
  static const opRemoveFromDiagram = 'このダイアグラムから外す';
  static const opDeleteFromModel = 'モデルから削除';
  static const opAddRelationship = 'リレーションシップの追加';
  static const opRemoveRelationship = 'リレーションシップの削除';
  static const opCopy = 'コピー';
  static const opPaste = '貼り付け';
  static const opDuplicate = '複製';
  static const opSelectAll = '全選択';
  static const opAutoLayout = '自動配置';
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
  static const confirm = '確認';
  static const tableListHeader = 'テーブルリスト';
  static const search = '検索';
  static const selectedCount = '個選択';
  static const diagramPrefix = 'ダイアグラム';
}
