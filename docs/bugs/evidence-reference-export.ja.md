# 比較用export診断の回帰

## 1. 再現

2f47a9fでdescriptor失敗注入が7件中2失敗を再現。658efb9で最後の許可requestの誤拒否を再現。d43bc4bで明示builder／非公開native記録の不足契約を追加。実行1はDocker cpがtmpfs取得ディレクトリーを読めず終了1。API成功だけでホスト比較成功とはしない。

## 2. 証拠

失敗記録と全cleanup結果を保持。Docker公式資料にtmpfsのcopy制限がある：https://docs.docker.com/reference/cli/docker/container/cp/ 。c3f7471の不足export契約は追加3テストで6エラーとなった。これは不足契約エラーで、6回の実転送失敗ではない。

## 3. 原因分析

5 Whys：本文はtmpfs内／Docker cpで読めると仮定／mountされた記憶領域を考慮していない／単体試験はAPI中心で実抽出を未確認／受入条件に独立したホストファイル取得が不足。根本原因は実環境で確認する前に抽出方式を仮定したこと。descriptorは所有権移譲不足、request上限は送信判定を応答完了にも適用したことが別原因。

Fishbone：mount、descriptor所有権、request数、builder選択、native記録とソースの同一性、実抽出試験。Timeline：descriptor RED2f47a9f/GREENc346585、実parser c68b3d3、上限RED658efb9/GREEN64d8b05、記録REDd43bc4b/GREEN6a2c7bf、実行1失敗、export REDc3f7471/GREEN5cf3bcd、8accf4f実行2終了0。

## 4. 修正

ExitStackと作成ファイル所有権、送信／完了の上限分離、明示builderと独立native記録検証を導入。固定ゲストファイルのみを上限付きpipeで取得し、正確な長さ・終了・時間を検証後、実ファイルを独立比較。所有権不明のcleanup対象は保持し、失敗記録を残す。

## 5. 検証と再発防止

関連18件・Python全155件成功。実行2で8ファイルを取得してnative全バイト／hash一致、全所有cleanupと既存資源保持を確認。短い／過剰／非0終了／stderr上限／timeout／既存fileの負例と実HTTP区切り試験を保持する。原本本文API比較だけの完了で、プレビュー／更新／UI／全製品は未完。
