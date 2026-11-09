# 設計

category/bulk/archiveの送信境界はtask-external-handoff-design.ja.mdに従い、型付きの開発コード用markerと処理枠照合を使う。直列化した実行能力やUIレイアウトは追加しない。

タスクhandoff再発修正はtask-mutation-handoff-design.ja.mdに従い、actor内ticketと共有取得の再照合で公開契約を維持する。外部の後続送信とLLM監査は別途残す。

既存Findingsのhandoff再発監査はfindings-mutation-handoff-design.ja.mdに従い、公開サービス署名とbackend契約を保つ。Task/LLMの監査は別途残す。

証跡のネイティブ操作前にfindings-traffic-state-design.ja.mdの状態層を実装する。世代付き読取とwindowのselection/session/activity、同期検証した固定要求を使い、取消確認後のtransport引渡しだけを送信済みとして扱う。guest能力は変更しない。

F5はfindings-advanced-design.ja.mdに従い、有限な証跡読取→変更/状態→lineage/retest/deepen/report→実bytes出力→UI/実guest/固定browser比較へ進む。F5aでは画面、host書込、通信許可、agent起動を変更しない。

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

T5はtasks-staging-design.mdに従い、UUIDの作成前添付を既存の上限付きmultipart/vsockと認証世代/進捗ガードへ接続します。ゲストの下書きパスを厳密検証しUnicode原文を保持、ホストURLには変換しません。TDD・不正応答/件数/認証世代/取消/ヘッダ試験、レビュー/全体回帰/署名を実施。作成モデル/UI/説明への一覧追加と実VM/ブラウザ添付比較は後続ゲートで、通信層のみのためLazyweb対象外です。

T6はtasks-staging-ui-design.mdに従い、T5通信を作成下書き・明示的ファイル選択・取消可能な進捗・参照版どおりの日英一覧へ接続します。閉じると本文保持、破棄/リセット/作成確定で下書きID更新、遅延応答を拒否し転送/選択中の作成を防止。TDD/レビュー/全体回帰/署名リソース、実UI比較は解除後のままです。

T7はtask-staging-runtime-design.mdに従い、新規使い捨て状態の候補を1回起動して添付/読戻し/衝突を実試験し、新規固定Docker参照版と比較します。エージェント/タスク/会話/クラウド/ユーザーデータは対象外。固定合成ファイル、全ログ監査、失敗も保持し、TDD/反例/レビュー/回帰後に実機へ進みます。実UI/OS選択/再起動信頼性は別ゲート、インフラのみでLazyweb対象外。

T8はtask-template-management-design.mdに従い、テンプレート一覧/新規/作成/編集/削除、分類/傍受ルール、作成フォームからの別名保存、結果不明時の保護、所有ID、日英UIを実装。固定契約/反例をTDD、レビュー/全回帰/署名で検証し、実操作/実ワークフロー比較は継続。比較版とVM隔離は保持します。

T9 は task-category-core-design.md に従い、カテゴリ CRUD と移動 API、明示 null、スキーマ・所有権・部分結果を検証。エージェントを起動しない。管理画面と実環境比較は後続必須。

T10 は task-category-ui-design.md に従い、ウィンドウ単位カテゴリモデル、型付き結果による一覧・作成連携、画面・編集・確認・セッションの所有権を検証。言語変更で状態を再生成しない。

T11 は task-catalog-runtime-design.md に従い、有限の本番クライアント検証、メモリ認証、新規VM1起動、終了後ログ監査、明示的な完了判定を実装。失敗のディスク/ログを残し、成功するまでの再試行や標準イメージ昇格は行わない。

T12 は tasks-bulk-design.md に従い、保持モデルと固定確認内容、カテゴリと共通の変更ゲート、確定結果だけの投影を使う。画面世代/確認UUIDで入力と順次処理を保護。結果不明IDの再操作は明示確認で解除。

T13 は tasks-archive-core-design.md に従い、有限通信・直接デコード、安全なエラー/警告有無、英日状態/段階ラベル、受付意味を実装。応答はソースの継承順序を尊重して集合照合する。

T14アーカイブ状態要件: ページ・検索・状態別の取得、ページ内のチェック選択、2秒間隔の重複しない更新、詳細の所有権、受付済み復元のID照合を保持する。受付済み復元を捕捉した詳細404のみでライブタスク更新を通知し、ページからの消失・無関係な404・取得失敗・古いセッションでは通知しない。停止時は受付を保持し、認証リセットで破棄する。ネイティブタブ・操作・実行時比較は後続の必須ゲート。

T15アーカイブ操作要件: 単体・一括アーカイブ、復元、完全削除、失敗状態の再試行を明示的な捕捉コンテキストで扱う。カテゴリ・一括・通常タスク操作とアーカイブ取得を共通排他する。202は受付のみで削除・復元を先取りしない。順序が変わる部分成功はIDごとに保持し、不明結果を自動再送しない。不明なタスク・アーカイブIDは明示確認まで保持し、停止・リセット・キャンセルで進行中の書き込みを早期解除しない。ネイティブUIと実ジョブのブラウザ比較は必須の後続工程。

T16アーカイブ画面要件: ライブ/アーカイブのタブ、サーバー検索・状態・初期20件と10/20/50件切替、ページ内選択、参照版9列、型付き進捗・エラー/警告の要約、行/一括の復元・削除・再試行、完全削除件数を含む捕捉確認、英日結果と不明確認を実装する。202はキュー受付のみ。復元再照合でライブ一覧を更新し、言語・サイドバー移動で状態を保ちログアウトで消す。実キーボード・AX・見た目・実行時比較は解除後の必須工程。

T17アーカイブ実行要件: 新しい使い捨て状態だけを使い、通常のcreateTask/launchTaskを通さず終了済みタスクと固定バイトを投入する。ネイティブAPIによるアーカイブ/復元/削除を固定参照版と比較し、同じディスクの再起動永続性も検証する。実モデル・LLM・エージェント・ホストコマンドは起動しない。前提フィクスチャの境界検証T17aとVM/参照版の実操作T17bを分け、片方だけで実行時受け入れを完了としない。失敗証拠を保持し、1回の成功でカーネル候補を昇格しない。

T17b Core検証契約: 固定タスク7101のready保管ファイルだけを隔離/修復するゲスト専用制御とエージェント活動0の監査を必須にする。各待機は120回/45秒上限で書き込み自動再送なし。第2起動で終了済み行/ファイル、一括保管、意図的restore_failedと明示再試行、復元一致、片方の削除と再保管チェックポイントを証明する。第3起動で同一ディスクのready保管残存と最終復元/ファイル/削除維持を確認する。時計・待機・障害制御の差し替えは単体試験用で実行証拠ではない。プローブ・参照・実機接続は引き続き必要。

F1はfindings-core-design.mdに従い型付き有限読取/分類更新/削除の契約を実装する。Findingsの高度な全機能も後続必須ゲートとして維持。基盤のみでLazyweb対象外。Core試験を画面/実行時の受入には数えない。

F2はfindings-state-design.mdに従い所有権付き読取/ページと保持状態、ページを跨ぐ選択、4xx/停止/リセット時も保守的に不明を扱う捕捉変更を実装。自動再送なし。状態基盤のみでLazyweb対象外。


F4b CI修正: SQLデータから通信形式への変換を型明示した試験専用helperへ抽出し、短い式と型付き資産変換で構成します。生の値と一意な通信キーを保持し、製品コード・SQLは変更しません。


型を明示した集計検証器とソースハッシュ付き初期/変更後JSONを用い、UTF8文言・由来・並び・重要度別件数・時刻を確認します。全体exerciseで共有する有限通信ゲートの128要求/90秒前後検査と再試行禁止を維持します。


Pythonの期待値はSwiftや集計JSONを読み込まず固定SQL値から独立計算します。Findings限定128要求/90秒前後検査・更新再試行なし。初期100読取、共通の編集/状態/部分HTTP500/読戻し/削除、再起動後100読取を比較します。キャッシュ/選択/結果不明の明示確認は共通射影から分離。VM停止証拠・reference起動/停止と同一backend/seed/audit hashを結び付けます。


別の7要求段階: GET9101→nameのみ→classのみ→severityのみ→空name→8192byte class→元の3項目へ復元。全応答を独立した全行期待値と照合し、他項目の変化も拒否します。既存更新14要求は維持。外側100+7+14+集計2=123を128要求/90秒内で実行し、境界後監査を追加。型付き境界記録を加えschema2へ上げ、再起動後100要求は維持。独立referenceは実API境界6検査を比較し、ローカル拒否は分離。schema1証拠は履歴として保持します。

## 調査ハーネスの追加目標

Dirsearch、Fscan、Masscan、SoftEther VPNをネイティブ操作から利用可能にする。ゲスト内実行、対象／ネットワーク制限、証跡の出自、英日表示を維持する。実装は未着手。[設計と段階別受入条件](investigation-harness-design.ja.md)を参照。ブラウザ互換と既存リリース要件を維持する。

## クラウド接続先の追加

OpenAI・Anthropic・Gemini・Groqでモデル取得、ストリーミング、ゲスト内ツール呼出しを扱う。既存カスタムURLと通信形式を維持。4社すべてをMacアプリから隔離Linux VM経由で利用できることを受入条件とする。GeminiとGroqは設定プリセットと模擬APIの試験まで進んでいる。実API接続と画面操作の受入試験は残っている。[4社対応の計画](cloud-providers-design.ja.md)を参照。

ツール実行履歴は認証済みのGET /api/commandsとGET /api/commands/statsを使用する。
一覧は0始まりのページ番号を使う。両リクエストで正規化したキーワードと探索IDを共有する。
パラメーター名は `task` だが、照合対象は `exploration_id`。集計にはページ番号と
ページ件数を送らない。記録済み入出力は原文テキストとして扱い、遅延した応答が
新しい絞り込み結果を上書きしないようにする。Mac版は固定ブラウザ版の列、入力の
プレビュー、詳細、独立した集計を踏襲する。Lazywebで確認したFrontの監査ログを参考に、
絞り込み欄を表の上に置き、状態を独立した列に表示する。Enterまたは「絞り込む」で
条件を適用し、読み込みエラーと結果が空の場合は分けて表示する。

LLM呼び出し履歴は、認証済みVM通信で `GET /api/llm/records`、`GET /api/llm/records/tasks`、`GET /api/llm/records/{id}` を使う。ページ番号は0始まりで、表示件数は25・50・100件。モデルとタスクは完全一致、セッションは前後の空白を除いてからバックエンドの部分一致に渡す。履歴IDはInt64で扱い、本文は行を選択した時に取得して原文を保つ。既存通信の応答上限は4 MiB。画面実装では詳細を選択中の行に結び付け、通信エラーと空表示を区別する。記録設定は更新後に読み戻す。タスク単位の削除は実行前の確認と実行後の読み戻しを検証する。

履歴の記録スイッチは `PUT /api/settings` で `llm_record` のみを送り、新しいGETで取得した値を表示する。タスク削除は確認済みのIDをそのまま `DELETE /api/llm/records?task=…` に渡す。前後の空白をサーバーが除去して別のIDに変わる入力は拒否する。削除が反映された後に応答が失敗する場合があるため、成否にかかわらず一覧とタスク別件数を再取得する。

資産画面の6種類の一覧は固定版の `GET /api/assets`、種別ごとの件数は `GET /api/assets/counts` を使う。一覧はオフセットと25・50・100・200件の表示に対応する。検索式は単一のDSLパラメーターとしてエンコードし、構文の検証はゲスト側で行う。行の任意項目と識別子は型を付けて受け取る。会社管理、削除、SwiftUI画面の比較は読み取りサービスの後に進める。

### 資産削除の通信境界

正で重複のない64ビットIDを、固定版のDELETE JSON形式で認証済みゲストに一度だけ送る。要求サイズに上限を設け、応答の削除件数が0件以上かつ送信件数以下であることを検証する。通信が中断してもゲストで削除が適用済みの場合があるため、画面は一覧を再取得して状態を照合する。選択と確認操作をつなぐ前に、要求と応答をSwiftの通信境界で試験する。

資産一覧には行ごとのチェック欄、現在のページの選択操作、単一削除ボタンを設ける。同じタブではページをまたいで選択できる。確認時に対象IDを確定し、件数と取り消せないことを表示する。固定ブラウザ版の動作と、Lazywebで確認したConfluenceの選択・削除確認の分離を参考にする。削除要求の後は一覧を読み直し、最終ページがなくなった場合は表示ページを補正する。

会社スコープの更新は、認証済みの資産カタログクライアントから構造化されたルールを送る。固定版の要求サイズとルール長の上限を適用し、作成はHTTP 201、重複名はHTTP 409として扱う。追加では一部のルールだけが登録される場合がある。置換では空の配列で全ルールを解除でき、不正なルールを含む置換はゲストが拒否する。会社削除では確認済み応答を検証し、帰属資産を削除するかどうかを明示する。

会社スコープの入力は、固定ブラウザ版と同じく1行に1ルールとする。保存済みの行は種別を引き継ぎ、ドメインに見えるキーワードを編集・並べ替えしても帰属の挙動が変わらないようにする。送信前に不正な行番号を表示する。追加ボタンの配置と一覧から開く編集画面は、Lazywebで確認したAttioとRetoolを参考にする。
