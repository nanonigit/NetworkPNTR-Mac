# クラウド4社対応の追加目標

ユーザー要望としてOpenAI・AnthropicにGemini・Groqを追加し、接続先として識別してモデル選択・ストリーミング・ローカルのツール呼出しまで扱う。初期導入には両社の公式OpenAI互換APIを使う。[プリセットの検証](cloud-presets-verification.ja.md)ではモデル一覧取得とストリーミングをループバックの模擬APIで試験した。[専用VMの検証](cloud-profile-vm-verification.ja.md)では4社の設定を保存し、再起動後に復元した。[チャット履歴の検証](cloud-history-vm-verification.ja.md)では模擬APIを使い、VM再起動をまたいで署名付きツール履歴が保持されることを確認した。実API接続（CP3）とMacアプリの画面操作の受入試験（CP4）が残っている。固定ブラウザ互換、既存のカスタム接続先、VM隔離、全リリース条件を維持する。今回は接続契約／通信設計であり画面配置は扱わない。画面変更前にはLazywebを使う。

現状のLLMFormatはanthropic／openai／openai-responsesという通信形式で、LLMServiceはこれをbackendのproviderへ送る。固定agent/provider.goもAnthropic／OpenAI形式の接続先を扱う。会社名と通信形式は別物なので、gemini／groqを同じenumへ足して未対応値を送るだけでは完成しない。既存プロファイルやユーザー指定URLを維持する。

| 接続先 | 最初に検討する方式 | 主な条件 |
| --- | --- | --- |
| OpenAI | 既存Chat Completions／Responses | 両形式と既存動作を維持。 |
| Anthropic | 既存Messages | ストリーム／ツール契約を維持。 |
| Gemini | Developer APIの公式OpenAI互換方式を評価 | ツール往復でthought signature等の不透明な履歴情報を保持。固定ライブラリで失われる場合は直接APIアダプターを検討。Vertex AIは別の将来範囲。 |
| Groq | 公式OpenAI互換方式 | 未対応パラメーターを送らず、モデル別の並列ツール／reasoning等に対応。 |

確認した公式資料：[Gemini互換API](https://ai.google.dev/gemini-api/docs/openai)、[Gemini function calling](https://ai.google.dev/gemini-api/docs/function-calling)、[Groq互換API](https://console.groq.com/docs/openai)、[Groq tool use](https://console.groq.com/docs/tool-use/overview)。候補URLはhttps://generativelanguage.googleapis.com/v1beta/openai/とhttps://api.groq.com/openai/v1。固定クライアントで実際の経路を確認し、v1二重追加や未対応フィールドを防ぐ。モデル名や提供状況は取得／検証し、特定モデルが恒久利用できる前提で固定しない。

会社の識別、通信形式、モデル能力を別に設計する。組込み設定は初期URL／能力を供給し、既存カスタム設定を残す。既知の正確なoriginだけを移行判定に使い、独自ゲートウェイを勝手に別会社へ変更しない。識別情報の保存／インポート／ロールバックも試験する。ブラウザ基準を変更せず、必要なゲストbackend拡張は独立版とソース／イメージハッシュで管理する。

通信はすべてゲスト経由。現在のNICなし実証だけではクラウドへ接続できない。別途設計する出口制限でgenerativelanguage.googleapis.com、api.groq.com等の正確なHTTPS接続先を扱い、Google全域のワイルドカードや別originへのキー転送／リダイレクトを避ける。秘密情報は既存の寿命／保存方針に従い、チャット・ログ・Git・証跡へ残さず、編集終了／ログアウトで下書きを消す。接続先追加によってクラウド側コード実行・ブラウザー・remote MCPを暗黙に有効化しない。

CP1：識別／形式／能力／保存の契約、既存設定互換、URL／ヘッダー／payload、接続先間のキー分離を通信なしで試験。

CP2：ゲスト内アダプターとモデル一覧。分割SSE、usage、エラー、キャンセル、ツールの往復を模擬サーバーで検証。Geminiのsignature保持を明示条件にする。別会社への自動切替やツール操作の黙った再実行をしない。

CP3：出口制限の拒否試験後、アプリから入力したキーで4社それぞれ最小限のモデル一覧・文章・ストリーム・ゲスト内ツール往復を実測。未入力／誤キー、429／5xx、時間切れ、キャンセル／VM停止、再試行／結果不明、永続化を確認。モックの挨拶だけで完了扱いにしない。

CP4：英日表示、能力に沿う入力検証、キーボード／VoiceOver、共通操作の実ブラウザ比較。ブラウザ側にない追加機能は拡張として受入条件を作る。4つの名前が出るだけでなく、4社とも利用できることを最終条件にする。

CP1a 実装契約（2026-11-05）：既存プロファイルと編集値に、派生値 `endpointIdentity` を追加する。既存通信形式に合う公式HTTPSのベースパスだけを識別し、末尾スラッシュ1つと明示ポート443を許容する。認証情報・クエリ・フラグメント・別ポート・別パス付きは識別しない。空URLは既存形式の既定先に従い、独自ゲートウェイはcustomのままにする。この値は説明用であり、外向き通信の許可やモデル能力の証明には使わない。保存・移行・モデル選択・キー・URLは変更しない。明示的な接続先選択と永続化、能力、ゲスト要求フィクスチャは引き続きCP1の残作業。Gemini／GroqのURLは公式互換資料で再確認したが、Geminiのツール署名保持はCP2で検証する。

CP1b：公式ベースURLと既存通信形式を持つ4社の新規プロファイル用プリセットを導入する。古いゲストが無視するvendor項目を追加せず、既存APIで具体的なURLと形式を保存する。必ず新規編集値を作り、保存ID・APIキー・プロキシ・モデル・セッションヘッダー・再試行上書きを引き継がない。モデルと名前は入力必須のまま、能力を推測しない。既存プロファイルや独自URLの編集方式は維持し、このAPIでは保存済み設定の接続先切替を提供しない。実際のLLMService保存／モデル一覧要求エンコーダーと応答デコーダーをプロセス内フィクスチャで検証する。PostgreSQL永続化、実ゲスト／クラウドHTTP、画面の受け入れ検証は別途必要。
