# LLM設定UIの日英対応 — L6

## 再現と証拠収集

L4cでエラー／通知を対応した後も、LLMの5ファイル（設定／カード・編集／モデル選択・rotation・全体retry・数値／retry部品）に固定日本語の操作／説明が残っていました。ソースから不足を確認した段階で、新規の実画面再現は主張しません。`Tests/NetworkPNTRCoreTests/Fixtures/llm-ui-localization.json`に、11種類の埋め込み文言を含む108項目の日英対応表を記録しました。

`e377f16`はAppStrings.formatted／render未実装の意図したコンパイルRED。最初の試験で存在しないretry-policy初期化子を使った点は、既存の変更可能プロパティへ直してから正式REDを確認しており、製品不具合に数えません。`c855245`で同じ3試験成功。全カタログと対応表の一致・繰返し／未指定／閉じていないtoken・テンプレート風の文字を含む混在モデル名の保持・表示処理後もdraft／retryの送信形式が変わらないことを確認しました。

## 分析

5 Whys：LLM画面が日本語→操作／説明がliteral→初期移植が全体言語要件に先行→モデル値と表示を統一的に分離していない→共通型付き表示を後の言語対応で導入した。Fishbone：キー所有者・動的値・API tag・入力途中の数値・retry未保存状態・fieldGeneration・シート／task同一性・placeholder再帰・リソース同梱。Timeline：ソース／Lazyweb→要件／設計／計画→試験設定訂正／意図したRED→キー／一度だけの展開／view接続→GREEN→レビュー／全試験／coverage→署名リソース。Lazyweb検索`AI model provider settings`はV7隣接メタデータ（.535）で、画像を閲覧した／一致の証拠とはしません。操作比較の基準は固定browserです。

## 修正

固定のLLM操作・ラベル・説明・空状態・確認・数値検証を現在localeで表示します。埋め込み文言は元カタログ内のtokenだけを一度展開し、モデル名やマスク済みhintの中身を再解釈しません。API／protocolのtag・独自設定名／モデルID・キーhint・モデル返答・既存backend pool診断はそのままです。最後の診断などは他言語が残り得るため、別の出所／backendゲートが必要です。

service／model／認証情報・言語に基づくview同一性／task・新規変更操作は追加していません。5ファイルのCJKソース行は0となり、Picker tag式も移行前後で一致。ただしソース監査であり実画面の言語監査ではありません。binding・数値解析／検証／入力途中のState・retry未保存フラグ・操作closure・保存／再取得確定時の既存fieldGenerationは維持。実際のレイアウト／入力の同一性は実操作で確認が必要です。

## 検証と残ゲート

Swift261件（成功260・既存AX1件スキップ）、Python52件成功。文字列展開ヘルパーは行coverage100%。読み取り専用レビューで文言／状態／API値の具体的な不具合なし。最終署名ビルド・厳格署名・exporter検査成功、両言語各108項目が署名同梱でも対応表と一致。ソース監査／coverage／結果は`evidence/localization/llm-ui-*`に記録しました。

ユーザーがMac解除を延期しているため、新規runtime fixture・UI試行・画像・クラウド呼出しはありません。実際の日英レイアウト／選択／シート・不正な数値入力の保持・retry未保存欄・接続試験／モデル選択・VoiceOver／IME・固定native/browser比較は未完了。Dashboard／runtimeラベル・backend言語／初期名の出所・未実装18画面・全21機能／runtime／配布の受け入れも残り、全体目標は継続中です。

CI訂正：31d8fadのhosted40135493632は、送信値保持試験のData直接比較2件だけが失敗。BackendJSONCodingのJSONEncoderはキー順を固定せず、byte順は送信値の不変条件ではありません。解析後にキー順を正規化して比較し、順序違いは一致・値違いは不一致の対照試験を追加。製品のencode処理は変更していません。同じbyte長だけで値の一致を断定せず、hosted再実行の成功が必要です。d09e852は第2引数のtry不足でコンパイル失敗中にGREEN名で誤コミットしたため、無効なcheckpointとして成功証拠から除外。1da4b81で構文を修正後、対象3件の実成功を確認。意味上の比較／対照試験はレビュー済みです。失敗runと誤表示commitの反証を保持し、最終CI成功前にリモート成功と主張しません。
