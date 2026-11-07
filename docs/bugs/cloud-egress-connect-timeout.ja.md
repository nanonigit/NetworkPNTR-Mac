# クラウド中継の HTTP 送信前タイムアウト

署名済み VM で、1回の起動中に4社すべての失敗を再現した。Mac 側はゲストの要求を
読み終え、TCP 接続に進んでいた。最初の接続が約10秒で期限切れになり、TLS や HTTP
送信には進まなかった。別の起動では2社が TCP 接続で直ちに失敗し、残りは同じ
接続タイムアウトになった。

## 原因と修正

中継が確定した応答を返さず閉じたため、ゲストはモデル一覧を失敗とした。接続期限切れと
送信後の期限切れが C 側で同じ分類だったため、Mac 側は最初のアドレスで止まった。
送信後の再実行を避ける処理自体は必要だが、送信前に失敗した接続と、届いた可能性の
ある要求を区別できていなかった。観測した TCP 失敗のネットワーク側の原因は未確定。

C 側では最初の HTTP 書き込みより前の期限切れを、既存の接続失敗として返す。
Mac は同じ接続先の検査済みアドレスを、1件4秒、最大4件、共通期限の範囲で試せる。
キャンセル、証明書のホスト名、アドレス検査、送信後の扱いは従来の条件を維持する。

## 再現と回帰

ループバックで HTTP 送信前の TLS を保留すると、修正前は共通タイムアウトの結果5を返し、
安全に別アドレスを試せる結果2の期待を満たさなかった。修正後は結果2でソケットを閉じる。
HTTP 応答の保留は引き続き結果5、TLS 中のキャンセルもキャンセル扱いになる。
署名済み VM では本番中継を新規ディスクで起動して実 API の応答を確認し、別の試験で
4社のモデル一覧とストリーミングの模擬通信を確認する。

## 検証結果

ループバック TLS の12件が成功した。最終版の署名済み VM で4社の模擬モデル一覧、
ストリーミング、通信中の停止を確認した。本番経路の実 API 試験は2回とも外部の
応答ステータスが確定しなかった。同じ検証時間帯に別のホスト単体試験で4社への
TCP 接続が成立しており、プロバイダー全体が到達不能だったとは判断できない。
実接続の安定性は引き続き未確認とする。

[検証記録](../../evidence/llm/cloud-egress-connect-timeout-verification.json)

## 同じアドレスでの追加試験

署名済みプローブは TCP までで停止し、TLS や HTTP を送らなかった。同じ時刻に
別のホストプロセスから同じ数値アドレスへ接続すると、署名済みプローブが
タイムアウトした試行でも接続できた。待機を `select` に変えても差が再現し、
同じ署名済みプロセスの VM 作成前にも失敗した。

VM 作成前のタイムアウト1件で、カーネルの TCP は接続済みだったが、
`select` の書き込み可通知と期待する接続先を確認できず、`SO_ERROR` は0だった。
同じ試行中に macOS のコンテンツフィルタのソケット一覧を読み取り、
プロセス ID とアドレス種別が一致する TCP レコードを1件確認した。接続済みフラグは
立っていたが、初回判定とドロップのフラグは立っていなかった。この試行はフィルタの
判定待ちだった。この Mac の有効なネットワーク拡張は Little Snitch 6.5。
適用ルールと Release アプリに対する判定は別途確認する必要がある。

同じ診断のその後の VM 起動では、4社すべてに TCP 接続できた。今回の接続試験では
プロバイダーの API 応答を要求していない。実 API と安定性の検証は継続する。
本番の接続先検証とホストのフィルタ設定は維持した。
[Apple XNU のソケット接続処理](https://raw.githubusercontent.com/apple-oss-distributions/xnu/main/bsd/kern/uipc_socket2.c) ·
[Apple XNU のフィルタ状態](https://raw.githubusercontent.com/apple-oss-distributions/xnu/main/bsd/net/content_filter.c) ·
[Little Snitch の判定待ち接続](https://help.obdev.at/littlesnitch6/lsm-managing-rules)

[同時 TCP 試験の記録](../../evidence/llm/cloud-egress-tcp-pair-verification.json)

## 利用者による許可後の再試験

同じ署名済み診断を新規のゲストディスクで2回実行した。Anthropic と Groq は
両方で HTTP 401 が返り、OpenAI と Gemini はどちらも外部応答が確定しなかった。
Little Snitch の有効ルール一覧では ChatGPT 経由の VMProbe に対して外向きの許可と
接続先ドメインの拒否が表示された。個々の要求に適用されたルールと
ARTEX Mac Release 本体の判定は未確認。
[再試験記録](../../evidence/llm/cloud-egress-firewall-retest.json)

## 起動経路の比較

Little Snitch で通信を許可したとの連絡後、署名済み VMProbe を直接起動すると、
4社とも HTTP 応答を確認できなかった。対象プロセスの TCP ソケットだけを
macOS のコンテンツフィルタ一覧から読み取ると、接続済みで初回判定とドロップの
フラグが立っていない状態を160回観測した。同じソケットを複数回数える場合がある。

起動経路を比較するため、診断を署名済みのバックグラウンドアプリにまとめた。
同じ実行ファイルと固定ゲストを使い、`open -n -W -g ... --args --cloud-live-models ...`
で Launch Services から起動する場合と、`Contents/MacOS/VMProbe` を直接起動する場合を
比べた。各回で新規の状態ディレクトリを使い、NIC と共有がなく VM が停止したことを
監査した後に結果を書き出した。

Launch Services 経由の2回はどちらも OpenAI・Anthropic・Groq が HTTP 401、
Gemini が HTTP 400 を返した。直接起動では4社とも応答が確定しなかった。
Gemini への到達は確認できたが、診断は応答を認証拒否には分類できなかった。

Little Snitch は、別のアプリから起動されたツールに個別のルールを適用できる。
今回の観測から起動経路を切り分けられたが、個々の接続に適用されたルールは未特定。
配布用プレビューは署名上の識別情報が異なるため、手順書の Launch Services コマンドで
別途確認する。実キーでのモデル一覧取得と Mac 版の一般 Web 閲覧は未確認。
[Little Snitch のルール優先順位](https://help.obdev.at/littlesnitch6/concepts-rules) ·
[macOS のフィルタ状態](https://raw.githubusercontent.com/apple-oss-distributions/xnu/main/bsd/net/content_filter.c) ·
[起動比較の記録](../../evidence/llm/cloud-egress-launch-context-verification.json)
