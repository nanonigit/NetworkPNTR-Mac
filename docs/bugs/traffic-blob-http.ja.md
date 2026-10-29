# blob HTTP接続と配信互換性の回帰記録

## 証拠と再現

6d7f613で実Handler／JWTテストのREDを保持。メタデータ経路なし404、保存領域障害と不在の区別なし、同じ長さのリンクを既存配信が追跡する問題。2d50dffでhandler／分類と管理対象コピーだけのパッチを追加。固定ブラウザと稼働ゲストは変えていない。

独立した読み取り専用レビューで互換性漏れを発見。固定BlobはblobPath経由でstrings.ToLower(strings.TrimSpace(hash))を適用するが、厳密なopener直呼出しでは失われた。859d09dで直接Blobと認証HTTPの大文字／空白hash拒否404を再現し、df9df85で配信wrapperに正規化を戻した。保存されたmanifestの検証は厳密なまま、同じ試験が成功。.gitattributesの空白除外はunified patchの文脈データだけで、Goソースの検査は維持。

f6456f8で不正UTF8／長さ／HEAD／captureなしを追加し、オフラインのパッケージ全体とLinux backendビルドを検証。overlay15件すべて成功、サブテスト込み26成功イベント。全体373成功イベント、既存DB／fixture依存102スキップ、新規テストのスキップなし。専用JWT／SQLite／バイナリーfixtureはPostgreSQL／プロファイル／エージェント／外部対象を作らない。本番の初期パスワード／PGログインを試したとはしない。

## 5 Whys

1. 旧大文字hashが失敗した理由：安全な処理への置換で正規化を経由しなくなった。
2. openerが厳密な理由：保存メタデータは小文字hashを要求する。
3. 契約が混ざった理由：公開wrapperを安全な内部helperへ直接置き換えた。
4. 初期HTTP試験で見逃した理由：新metadataが返す小文字hashだけを使った。
5. wrapperに戻す理由：既存入力互換と内部／保存情報の厳密さを分けて維持できる。両方を独立して試験する。

## FishboneとTimeline

API：新metadataと既存hash経路。認証：既存JWT内、読取限定、例外なし。障害：不正400、不在／inline／無効404、保存障害503で汎用文言。ファイル：情報取得／配信でリンク非追跡・非ブロッキング・通常ファイル限定。試験：経路／配信RED→GREEN→互換性レビュー→hash RED→正規化GREEN→境界／全体／ビルド。来歴：固定archiveとpatch／ソース／手順／イメージ／バイナリーのハッシュ、固定checkout不変。

## 検証手順の修正と再発防止

最初のbuild-info確認は、go version -mにリンク版の値まで出ると誤って期待した。そこではコンパイラー／OS／CPU／CGO／trimpathを確認し、実ELFの文字列と元のmain.version定義でリンク版を別確認した。検査を通すための製品ビルド変更はしていない。

JWT／no-store／query／生ID／status／元バイト／正規化／リンクのテストを保持。新handler文網羅30/30、処理／opener60/65。パッケージ全体の網羅とPGスキップは別に明示。これはHTTPソフトウェア／ビルド段階で、ゲスト生成、ネイティブ転送／保存操作、実VM blob保存、UI／ブラウザ／カーネル／4社／ハーネス／リリースの完了ではない。
