# 設計

SwiftPMの複数ターゲット、SwiftUI/AppKitのネイティブ画面、Virtualization.framework、Linux ARM64ゲストを採用する。最終形はWebViewではない。フェーズ1ではネットワーク・ディスク・共有なしの最小Linuxを起動し、シリアル出力でゲスト起動を確認する。成果物のSHA-256を固定し、起動前に検証する。

構成: ArtexCore（機能一覧、状態遷移、整合性、通信契約）、ArtexMac（画面とVM管理）、VMProbe（署名した実VM検証プログラム）。画面からホストシェルを起動しない。VM状態はアプリ全体で共有しMainActorで更新する。リソースはアプリ管理、ログは上限付き、起動・停止エラーを隠さない。

フェーズ2では読み取り専用のOSイメージと専用ext4データディスク、ゲスト内PostgreSQLと非root ARTEXを構築する。ホスト共有は作らず、専用vsockポートとセッション認証でAPI通信する。ホストに任意コマンド実行APIを置かない。ネットワークは別途設計と拒否テストを通過してから追加し、LANへサービスを公開しない。ブラウザ版の認証情報は自動流用しない。Mac側のセッション・秘密情報はKeychainで管理する。

更新はアプリとゲストイメージの組をmanifestへ記録し、署名/ハッシュ確認→正常停止→整合したバックアップ→イメージ交換→ヘルス確認→失敗時復旧を行う。DB移行後に古いイメージへ戻すだけの危険なロールバックはしない。通常停止と強制停止を明確に分ける。VMとAPIの成功だけでは画面の同等性を満たさない。

根拠: AppleのLinux VM・VZLinuxBootLoader・VZVirtioSocketDevice公式文書。上流の主要21項目、全画面ルート/APIハンドラーを抽出。最新版/system/llmの実画面でプロファイルとタブを確認。Lazyweb検索d85df937-aa86-420d-ad7f-e702652210e7ではCommandbar/Fingerprintのナビゲーション・状態表示例を取得（保存確定APIはレート制限）。安定したサイドバーと状態・作業・設定の区別を取り入れ、ブラウザ版の実際の操作を優先する。


言語設計: en/jaの型と永続化したネイティブ設定、String Catalog共通リソース、組み込み初期値に限定した表示変換を採用する。新規バックエンドシステム出力は既存の認証付きoutput_language設定と同期し、言語フェーズでguest起動のja固定を検証済み選択値へ移行。固定比較ソース・任意のユーザー内容を保持。不明言語は英語へフォールバックし、既存backendの非対応言語は明示的に選択済み日英へ移行する。漢字だけでは日中を識別できないためCJK一括除去をせず、文言の出典・カタログ単位で監査する。localization-audit.ja.md参照。


L1: AppLanguageはCodable/CaseIterable/Identifiable/Sendableなen/ja型で、自言語名とLocaleを提供。AppLanguagePreferencesはMainActor observableとしUserDefaultsを注入、専用の言語キーだけを読み書き。初回のOS候補はen-/ja-地域指定やアンダースコアを認識するが保存値は正規en/jaだけ。不正な保存値と未選択を区別し、前者を英語へ修復。選択APIは型で制限。UI・String Catalog・backend同期は後続ゲートで、Core設定だけの段階はLazyweb対象外。


L2: 英語原文のString CatalogをCoreのSwiftPMリソースでprocessしdefaultLocalization=en。AppStringsで型付き共通キー・明示言語取得・英語フォールバックを提供し、機能IDを翻訳名へ対応。ユーザー内容は変換しない。AppはStateに言語設定を1つ保持してRootへ渡し、ツールバーのメニューPickerを自言語名で表示。localeを設定しても言語.idやruntime再作成を使わない。Rootのラベルを共通カタログへ移行。固定settings/page.tsx:124/665が即時UI切替とbackend失敗の別通知の根拠で、同期は後続。Lazyweb検索76693227-6d1e-45bf-9de0-c269b458b639のAmazon/Freevee言語選択メタデータは補助情報のみで、画像を見た証拠ではない。レポート生成は依頼されていない。


L2 CI訂正:40110609236はCIのSwiftPMがxcstringsを未コンパイルのままコピーすることを証明。ローカルSwift Buildとの差。String Catalogを原本とし、生成したUTF8 plist形式.stringsをen.lproj/ja.lprojへコミットしてprocess、rawカタログを実行リソースから除外。標準ライブラリの厳格exporterは現行の単純なtranslated stringUnitと対応localeのみ許可しvariation等を拒否。--checkで生成バイト一致を検査し、CI・署名buildラッパーのSwift実行前に必須化。直接swift testもコミットした派生リソースを使い、翻訳を二重に手修正しない。


L3は既存locale環境・型付きchatキー・単一カタログと派生互換リソースを使用。表示だけを変え言語.idは使わない。AppKitは同じコントロールのtitle/help/読み上げを更新し、エディタの本文・選択・marked textに触れない。パネルは作成時localeで案内し所有者callbackを維持。ChatUploadPresentationに言語引数を追加し従来callerは日本語既定、製品UIは明示指定。BuiltinAgentTextは固定db/db.goの既知キーと既定UTF8全文一致だけで表示変換し、server書込みや文字種一括置換をしない。任意エラー・初期会話名来歴・backendテンプレートは未完了。Lazyweb38aa7a86のSkypeはメタデータのみで、固定composerとA5/A6画像を基準にする。


L3会話名の安全確認: 固定conversations.go:74/493は空／韓国語の初期名を自動命名センチネルとして扱う。作成時の翻訳名指定は最初のメッセージによる自動命名を止めるため、この案の試験は実装・checkpoint前に撤回。型未実装probeを有効な製品REDとして数えない。来歴と両立するbackend移行設計までwire／初期名／自動命名を保持し、既存独自名を一括変更しない。

L4aエラー基盤：ネイティブの静的検証文字列をBackendValidation型に移し、日英エラープレゼンターを追加。store移行中は従来の日本語LocalizedError互換を保持。明示言語で取得しOS設定に依存せず、未知のエラーを文字列化しない。HTTP／Keychain数値のみ埋め込み、任意のserver本文・パス・秘密を表示しない。この基盤だけでUIエラー切替／R8を合格にしない。

L4b Chatエラー：storeは安全な型付きAppErrorMessageを保持し、viewの現在localeで表示。view再作成・リクエスト発行・本文／添付／選択変更をしない。診断／旧試験向け日本語Stringは計算プロパティで互換保持。一覧／履歴／送信／停止／workspace／添付／部分削除／引用ページング／本文／詳細を対象とし、キャンセル・世代・所有者判定を維持。未知のエラーはraw情報を保持せず型付きfallbackへ縮退。store RED/GREEN・全試験・レビュー・署名・実native/browser失敗送信中の言語比較を別ゲートとする。Lazyweb検索chat error retry messageは隣接DoorDashメタデータのみ（類似度.385）で視覚証拠とせず、固定版のエラーUIを基準にする。

L4c移植済み画面のエラー／通知ゲート：AuthenticationSession・LLMStore・DashboardLoadStateはAppErrorMessageを保持し、日本語Stringは計算プロパティで互換。LLM完了通知はカタログキーで保持し、再取得失敗と独立させる。認証・LLM設定／編集／rotation・dashboardの現在view localeで表示。localeによる認証／変更操作／poll再起動やパスワード／APIキー保存をしない。フォーム・規約同意・世代・前回データを保持。周辺未翻訳操作／規約言語は別ゲート。検証失敗・未知エラー秘密除去・保存成功後の再取得失敗・dashboard前回データ保持を試験。Lazyweb settings inline validation errorは隣接Gopuff captchaメタデータのみ（.356）で視覚証拠としない。実native/browser比較はMac解除まで延期。

L5認証／規約：ネイティブ認証ラベルを型付きカタログで日英化。AuthTerms.loadAllで固定規約の両言語を一度読み込み、既存シートの現在localeで表示。パスワード／確認／同意／focusのbinding・task同一性・送信・phase変化時の消去を保持。読了は固定browser同様、シートを開くたびリセットし、表示中の言語変更ではreadToEndを保持。言語に基づくview再作成なし。各言語28項目のauth.terms全文が固定参照と一致し、規約改変や実行時ネットワーク取得なし。自動setup-token／固定ユーザー名の案内はnativeの実動作に合わせる。resource/API RED/GREEN・レビュー／全試験／署名同梱を確認し、実native/browserの操作／scroll／読了はMac解除まで未完了。Lazyweb terms agreement modalはPostman隣接メタデータのみ（.479）で画像証拠にはしない。

L5隣接読了判定修正：初期の空スクロール領域で、規約読み込み前に読了を付与しない。シート内の読了状態を型で保持し、Equatableなviewport観測にdocumentLoadedも含める。短文でatEndがtrueのままでも読込完了を別イベントとして扱う。失敗／空文書は同意ボタンを有効化せず、読込済み文書の末尾で読了を保持し、表示中の言語変更では維持、新規シートは未読。ログイン権限強化ではなく読了UIの修正で、独立した同意checkboxは変更しない。別RED/GREENと実scroll比較待ち。

L6 LLM UI：設定／カード／編集／モデル選択／rotation／全体retry／数値検証／ヘルプを型付き日英カタログへ。名前付きplaceholderを一度だけ展開し、任意モデル名・マスク済みキーhint・値を再帰的にテンプレート解釈しない。tag／API列挙値／prefix／binding／不正入力／dirty／シート所有者を保持し、既存fieldGenerationは確定した再取得／保存時だけ変更。localeのid／taskや通信／変更操作は追加しない。Lazyweb AI model provider settingsはV7隣接メタデータ（.535）で画像証拠とせず、固定browserを基準にする。カタログ／format RED/GREEN・全試験／レビュー／署名を確認し、実native/browser切替はMac解除待ち。

L7 Dashboard UI：見出し・群・空／前回／読込状態・選択・chart軸／系列／凡例／読み上げ・集計・期間件数・資産／通信／システムを日英化。metrics／計算／日付ID／query／poll／選択ID／tag／遷移は保持。既知task／engine／severityは固定status辞書と一致し、raw識別子完全一致だけ変換、未知文言保持。活動5コードは表示だけ翻訳し、独自tool名／worker／summaryはそのまま。chart系列と凡例scaleのキーは同じ翻訳を使い、色／選択の実一致はUI確認待ち。既存の一度だけの埋め込み展開を使用。resource／status／集計不変RED/GREEN・レビュー／全試験／署名、実native/browserは解除待ち。Lazyweb usage analytics dashboardはGoogle Analyticsメタデータ（.631）で画像証拠ではなく、固定browserを基準にする。

L8 runtime／比較画面：操作・lifecycle6状態・sidebar・機能比較表／件数を現在localeで表示。nativeStatusゲート・機能ID／browserパス・未知機能名を保持。VMController／DesktopRuntimeは既存raw診断に安全なAppErrorMessageを並行保持し、同じ起動境界で消去、既存fail／catchだけで設定。RuntimeError種類をカタログキーへ変換し、任意stage／path／detailは埋め込まず、未知frameworkエラーはruntime用fallback。VM構成／権限／protocol／状態遷移／認証／disk／pollは変更なし。ゲストログ／CLI診断はraw保持。VMを起動しないresource／状態／失敗境界RED/GREEN・レビュー／全試験／署名。実native操作とOS標準メニューは未完了で、SwiftUI localeだけでは標準AppKitメニューは変わらない。Lazyweb virtual machine status settingsはHeight隣接メタデータ（.383）で画像証拠ではない。

L9 menu境界：既存NSMenu／action／responder／shortcut／target／有効状態を保持。既知の標準actionと静的表示名の組だけ翻訳し、登録済みwindow／help／servicesの同一性とroot見出し名＋操作から標準群を識別。未知／独自／装飾／custom view・動的window／service名は保持し、menuを再構築しない。アプリ言語とAppKit didBeginTrackingで更新し、SwiftUIによる差し替えに備え毎回現在mainMenuを取得。selector observer1つを明示stopし、timer／操作実行／保存／VM変更なし。合成menuのmetadata／往復／未知・observer差替／stopと28項目catalogをTDD。実OS dispatchと全動的／未知項目の網羅は解除後。Lazyweb desktop application menu barはCluely隣接メタデータ（.340）で画像証拠ではない。AppKit interopスキルの狭い接続を使い、SDKの通知／登録menu APIを確認。

T1 Tasks有限coreはtasks-core-design.ja.mdに従う。作成全optionと一覧／詳細／metadata／control／batch／delete、所有者／変更結果と日英型付き検証を実装。active化の副作用やUI完了扱いなし。RED/GREEN／全回帰／review／署名後、実VM／参照／UI合格を検証する。

T2タスク状態はtasks-state-design.mdに従います。一覧/詳細と選択ID、競合/ライフサイクル保護、T1全有限操作の確定/入力拒否/不確定結果、再取得失敗後も操作確定保持、自動再試行/アクティブ選択なし、キャンセル可能な10秒ポーリングを実装します。画面/機能/実行環境の受入は未完了です。バックエンド状態のみでLazyweb対象外。RED/GREEN、応答順序/キャンセル/リセット制御試験、全体回帰、レビュー、署名付きビルドを必須とします。

T3はtasks-ui-design.mdに従い、一覧/詳細、検索/状態/並べ替え、名前/ピン/制御/削除をウィンドウ所有T2ストア、認証ルート、ダッシュボード遷移へ接続します。日英文言、不確定結果表示、既定オフの削除5項目、言語切替で画面再生成なし。機能はin_progressのみ。作成、分類/アーカイブ/一括/高度な詳細と実比較は今後も必須です。RED/GREENの表示/状態/レイアウト試験、レビュー/全体回帰/署名ビルド、実比較は解除後に実施します。

T4はtasks-create-design.mdに従い、選択肢とT1全12項目の作成フォーム、順序付きモデル、関連タスク/会社/分類、テンプレート適用、安定IDのルールを実装します。全入力/取得/確定/閉じるをコンテキストIDで保護し、作成は明示的に1回、確定で取得失敗と分離して消去、不確定は下書き保持/再送抑止します。作成添付/テンプレート分類管理/全タスク/実行/UI受入は継続。RED/GREEN、競合制御、全体回帰/レビュー/署名、実比較は解除後です。

B1はboot-preflight-design.mdに従い、空/非空と検査異常を区別し、fail-closedの書式化条件を維持します。専用の新規使い捨て状態に1回だけ起動し、読み取りAPIと固定の秘密を含まない結果を出すVMProbeを追加します。ユーザーデータ/隔離方針は変更せず、TDD/判定/書式化ガード試験、旧新プロファイル各1回の制御実験、レビュー/全体回帰/署名を行います。カーネル原因/安定性/実UI比較は未完了、インフラのみでLazyweb対象外です。
