# ネイティブ通信履歴の操作画面（TR3）

独立Traffic全体とTR4/TR5／ブラウザ／VM／release／4社／harnessの要件を維持する。今回は読取・検索・ソート・ページ移動・host選択・raw詳細・削除確認を既存モデルへ接続する。finding紐付けとblob原本保存拡張は後続必須作業で、動かないチェックボックスを表示したり完全同等と扱わない。実操作ができてから対応表をin_progressにする。

設計前の証拠：固定e75ae371の/function/traffic、HttpCodeBlock、紐付けダイアログを直接の基準にする。Lazyweb0.15.14は正常。検索ab57014f-3bb4-46d0-ac7b-4c0e43bd1b98はWriterログ表（screens:955168ba148c457c50ec8e4c,.493674）とCloudflare分析（screens:c4c75edcdf9d1bd7264de3c8,.496524）のmetadataを返した。中程度の関連例で画像自体は未確認、ARTEX同等性の証拠ではない。Hosted reportや画面アップロードは依頼されていない。Lazyweb経由でClarify指針全文を取得した：https://raw.githubusercontent.com/pbakaus/impeccable/main/.claude/skills/impeccable/reference/clarify.md 。常設ラベル、動詞と対象の操作名、削除の影響明示、回復メッセージの重複回避、英日で完結した文を、元の構成内へ適用する。

配置は見出し／記録状態／proxy／件数、host／method／query、body／path／status／応答長の詳細検索、host選択popoverと3種類の削除、横スクロール可能な一覧とserver sortボタン、隣接ページと25/50/100/200の件数選択。raw詳細sheetは要求／応答、折返し／コピーを持つ。DTOとCJK／FEFF／NFD／blob文字列は原文のまま、legacy Host補完は表示だけにする。任意URLへ通信せず、コピーは利用者の操作時だけ行う。元画面にないcapture切替は追加しない。

rootが認証セッション／ウィンドウごとにモデルを保持し、認証離脱でreset、セッション置換で旧モデルを破棄する。viewタスクが不変leaseを取得し、キャンセル時にそのleaseだけを停止する。古いdisappear／Bindingで新表示を停止させない。入力はモデルのガード付きAPIを使い、行／host／詳細／確認はquery所有権と不変ID／更新番号も保持する。未反映入力中は削除と行選択を止め、適用済み対象を明確にする。部分一致／選択host厳密一致／全消去を個別に固定し、他の検索条件で削除範囲が狭まらないことを示す。結果不明では最新読取と明示承認を要求し、自動再送／承認しない。

先にraw／Host補完、不変Binding／確認／dismiss／ack、英日ラベル、light/darkの非表示レイアウトと描画時の副作用なしを試験する。その後レビュー、全試験／coverage／固定比較／翻訳、署名ビルド。非表示レイアウトは実ブラウザ／マウス／キーボード／VoiceOver受入ではない。Mac解除は利用者が後回しにしているため再依頼せず、実画面比較は未完了のままにする。
