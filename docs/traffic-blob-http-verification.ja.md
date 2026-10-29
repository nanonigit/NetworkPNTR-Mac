# blob HTTP接続とbackendビルド

管理対象source overlayにGET /api/traffic/blob-metadataを既存JWT API内へ登録し、管理対象Traffic.Blobも安全なFD方式へ接続。固定ソース／ブラウザと稼働ゲストは変えていない。id／side各1個、UTF8／長さ／制御文字／重複／余分なquery、no-store JSON、固定400／404／503を実装。DB読取障害を不在／inline／無効captureと区別し、既存配信では空白／大文字小文字の正規化を維持して通常ファイルだけを開く。

実Server.Handler／JWTと非公開SQLite／本文ファイルで、未入力／不正token、元バイナリー／Content-Length、inline／不在、query／method、DB停止、manager／captureなし、リンク拒否を試験。専用鍵と手動投入データは本番パスワード／ログイン／実VM captureの証明ではない。6d7f613経路／配信RED→2d50dff GREEN、レビューでhash互換漏れを確認し859d09d RED→df9df85 GREEN、f6456f8で境界／全体／ビルド。bugs/traffic-blob-http.mdと日本語版を参照。最終読み取り専用レビューで阻害指摘なし。レビュアーは試験していない。

overlay15件、サブテスト込み26成功イベント、新規スキップなし。オフラインtraffic／server全体は373成功イベント（トップレベル270）、既存DB／fixture依存102スキップ、失敗なし。未検証スキップ一覧はevidence/traffic/blob-http-verification.jsonに記録。新handler文網羅30/30（100%）、処理／opener60/65（92.31%）。全traffic787/1194（65.91%）、server2274/12764（17.82%）は別に明示。分岐／製品全体／PG統合／実UI／導入済みゲストの受入ではない。

固定Linux／arm64 Go1.26.3でmodule検証、patch検査・適用、ネットワークなし試験、CGO不要・trimpath／buildvcs=false・版artex-mac-e75ae371-blob1のbackendをビルド。ELF64／AArch64、29,360,290バイト、SHA256は0cbb7cb32f05843de7b733fb76ed4e22b9b2acd386878d4ce34b89d819a3750a。テストだけ増やした再ビルドでも同じhash。Go情報でコンパイラー／OS／CPU／CGO／trimpathを確認し、表示されなかったリンク版は実ELFで別確認。ソースf6456f8、各source／patch／手順／compiler／image／binary／検証結果／網羅hashを公開記録へ保持。無視対象.build-cache/managed-backend-blob-v1に次のゲスト生成用候補と入力manifestを配置し、インストールやGitへのバイナリー追加はしていない。ネイティブ用backendにはブラウザUIを内蔵せず、別の比較用ブラウザを維持。

固定e75ae371は変更なし、21／27／243一覧一致、既存アプリの厳格署名確認。ネイティブソース不変のため前回972Swift／179Pythonを新規試験とは扱っていない。ゲストイメージ／昇格、ネイティブmanifest／転送／保存基盤／保存画面、新しい実VM endpoint／保存、外部スキャン／クラウド呼出しは未追加。元blob保存はこれら全経路と実バイト／所有範囲／中断／UI比較が通るまで未完。21機能／カーネル／4社／ハーネス／リリース全体も未完。ホステッドCI未検証、公開[skip ci]。
