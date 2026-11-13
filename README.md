<p align="center">
  <img src="project_er_operation/assets/icons/pero.png" alt="PERO" width="160">
</p>

# PERO

**ER図を描いて、そのまま SQL にするための Windows デスクトップアプリ。** Flutter 製、MIT ライセンス。

テーブルとビューをドラッグ&ドロップで並べ、リレーションシップを線で結び、保存して、`F5` で `CREATE TABLE` まで一気に出力します。
PERO は「ER図(ER)」を「ペロッと(PERO)」SQL にしてしまう、くらいの気持ちで作っています。

> 「ER図を描くのは面倒。でも、描かないと後で泣く。」
> 泣く前に、せめて楽に描きましょう。

## できること

**描く**
- タブ(ダイアグラム)で機能ごとにページを分けて、テーブルとビューを自由に配置できます。1つのテーブルを複数のタブに置くこともできます。
- IE記法のリレーションシップ(親・子の多重度、依存関係、自己参照、ON DELETE / ON UPDATE、DEFERRABLE)。列を別のテーブルへドラッグするだけで作れます。
- テーブルの右上のボタンで折りたたみ。サイドメニューとプロパティも、ボタンひとつでスライドして隠せます。キャンバスが広い。
- 検索(正規表現も可)で、ヒットしたテーブル・列・関数・トリガーをハイライト。↑↓(または `Enter` / `Shift+Enter`)でヒットへ順に移動できます。400テーブル級でも描画がもたつかないよう、描画結果をキャッシュしています。
- 自動配置(層に分けて並べます)、元に戻す / やり直し、コピー / 貼り付け、PNG / PDF 出力。

**設計する**
- 共通列パターン(テーブル名の正規表現で `update_at` や `remove` のような列を自動付与)。仮想列なので、パターンを直せば全テーブルに反映されます。
- 結合ビュー / 関数ビュー / SQLビュー、CHECK 制約、ユーザー定義型(複合型・列挙型)、トリガー、スキーマ。
- 物理名の形式チェック、生成前検証(予約語や識別子の長さの警告つき)。

**出力する**
- ポストファイル(`*.post`、JavaScript)で SQL への変換を差し替えられます。同梱は **PostgreSQL / MySQL 8.0 / SQL Server**。自分の方言用に書くこともできます。
- ポストファイルのメタ情報から対象 DB が決まり、画面もその DB の分だけ表示されます(使わない DB のタブは出ません)。

**守る**
- 保存は一時ファイル経由(途中で失敗しても元のファイルは無事)。異常終了しても、編集内容をキャッシュから復元できます。定期バックアップつき。
- 読み込み時に整合性確認をして、壊れた参照は直してくれます(直した内容は一覧で見せてくれます)。

## 動かす

**必要なもの**: Windows 10 / 11(64bit)。

1. [Releases](https://github.com/okpnet/flutter-pero/releases) から zip(`PERO-v*-windows-x64.zip`)またはインストーラー(`pero_*.exe`)をダウンロードします。
2. 展開して `project_er_operation.exe` を起動します。`.pero` ファイルを渡すと、そのファイルを開きます(多重起動はせず、既存のウィンドウに渡します)。
3. `post` フォルダに、使えるポストファイルが1つもないと起動しません(同梱のものが入っています)。

はじめてのとき:

```text
テーブルを追加 → 列を足す → 別のテーブルへ列をドラッグ(リレーションシップ) → F5 → 保存先を選ぶ
```

使い方の詳細は [使い方](doc/contents/使い方.md)(Wiki にも置いています)を見てください。

| よく使う操作 | キー |
|---|---|
| 新規 / 開く / 保存 / 名前を付けて保存 | `Ctrl+N` / `Ctrl+O` / `Ctrl+S` / `Ctrl+Shift+S` |
| 元に戻す / やり直し | `Ctrl+Z` / `Ctrl+Y` |
| ダイアグラムの切替 | `Ctrl+Tab` / `Ctrl+Shift+Tab`(循環)、`Ctrl+1`〜`Ctrl+9`(n番目) |
| コピー / 貼り付け / 複製 | `Ctrl+C` / `Ctrl+V` / `Ctrl+D` |
| このダイアグラムから外す / モデルから削除 | `Delete` / `Ctrl+Delete` |
| SQL を生成 | `F5` |
| 設定 | `Ctrl+,` |
| ズーム / パン | `Ctrl+ホイール` / 中ボタンドラッグ(または `Space` を押しながらドラッグ) |

## 正直なところ(制限事項)

- **Windows 専用**です。macOS / Linux には対応していません。
- MySQL / SQL Server 用のポストファイルは、期待値(golden)のテストで確認していますが、**実際のサーバーに流しての確認はしていません**。流してみて、おかしかったら教えてください。
- データベースへの接続やリバースエンジニアリング(既存の DB から ER 図を起こす)、複数モデルの同時編集、印刷機能はありません(画像 / PDF 出力はできます)。
- UI は日本語のみです。

## 開発する

```powershell
cd project_er_operation
flutter pub get
flutter analyze
flutter test
flutter build windows --debug
```

- Flutter(stable)と Dart 3 系、Visual Studio の「C++ によるデスクトップ開発」が必要です。
- テーマの管理に、同じ作者の共通ライブラリ(`flutter-pms` の `theme_lib`、`logger_provider`)をパス依存で使っています。リポジトリの隣に `flutter-pms` を置いてください(`pubspec.yaml` の `path:` を参照)。
- ポストファイルの生成テストは QuickJS(`flutter_js`)を使うため、**先に一度 `flutter build windows --debug` を実行**してください。
- `flutter test` や `flutter analyze` の直後の初回ビルドが、`cpp_client_wrapper` のソースが無いというエラーで失敗することがあります。`windows\flutter\ephemeral\cpp_client_wrapper` を削除してビルドし直すと直ります(これは PERO のせいではありません。たぶん)。
- インストーラー(Inno Setup)は `inno/build_installer.ps1`。

```text
project_er_operation/
├─ lib/        model / command / persistence / generation(純Dart)と、UI(canvas / panel / dialog / app ...)
├─ post/       同梱のポストファイル(postgresql / mysql / sqlserver)
├─ test/       lib と同じ構成のテスト
├─ doc/        使い方(contents)とサンプルモデル(sample)
├─ tool/       SQL → .pero の取り込みツール
└─ CLAUDE.md   仕様書(実装の指示書を兼ねています)
```

仕様はすべて [CLAUDE.md](project_er_operation/CLAUDE.md) にあります。長いです。覚悟してください。

## ライセンス

[MIT](LICENSE)

---

*PERO は、ER図を描く時間より、ER図を眺めてコーヒーを飲む時間を増やすために作られました。*
