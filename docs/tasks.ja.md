# フェーズとテストの合格条件

- [x] P0: 上流の全ナビゲーション・画面・API一覧、要件・設計・比較表・異常系テスト計画、ブラウザ実画面証跡、独立した非公開リポジトリ。
- [ ] P1: 署名したMacアプリからDocker不要のLinux起動/停止。ホスト共有とネットワークなし。改変検出で起動を拒否。起動→停止→再起動、失敗/タイムアウトと実ウィンドウ表示を確認。
- [ ] P2: VM内ARTEX/DB、永続化、認証付きvsock通信、クラッシュ復旧。同じfixtureのAPI・認証を比較。秘密情報と通信ポリシーを設計し拒否テスト。
- [ ] P3: LLM設定・ダッシュボード・チャット・タスク詳細・検出結果詳細をネイティブ化。同一データで成功・失敗・ストリーム・キャンセルを比較。API成功だけで画面完了にしない。
- [ ] P4: 残り全機能と詳細タブ。CRUD、入出力、通知、介入ルール、MCP、ツール、言語・アクセシビリティ・キーボードを比較。
- [ ] P5: ライセンスとゲストソース配布、署名/公証、初期Mac導入、移行・バックアップ/復元、安全な更新/復旧、性能、全体比較。

証跡はユニットテスト、実VMログ、同一操作のブラウザ/ネイティブ画面、fixtureによるAPI契約比較、異常注入で残す。サイドバーに名前があるだけの画面を完成扱いにしない。比較データに外部の実対象を使わない。最終的に各機能に出所・操作項目・データ・操作手順・期待結果・移植状態・証跡・差分理由を記録する。

バックエンドの中間記録は docs/phase2-verification.ja.md を参照。実ゲスト起動、認証付きvsock、保存・認証情報の保持、ブラウザ版との5つのAPI比較は確認済みです。ネイティブ認証は接続しましたが、間欠的なゲスト起動・復旧の失敗により実行環境は未合格です。ストリーム・外向き通信、実クリック・画面比較、全機能比較も未完了です。

P3のLLM中間記録：型付きサービスとネイティブ画面を実装し、11群のAPI比較が固定ブラウザ版と一致しました。外部操作で作成・編集・入力検証・Return保存・有効化を確認しました。全操作・外向き通信・画面比較の受け入れは未完了です。docs/llm-settings-verification.mdを参照してください。

P3ダッシュボード中間記録：表示項目と11個の認証付き取得APIを接続しました。データ入り12通りのトークン集計が、独立した計算と使い捨ての固定ブラウザ版に一致しています。一部の実操作は成功しましたが、同一データの画面比較・通信キャプチャ・異常表示・アクセシビリティ・実行環境等の条件は未完了です。docs/dashboard-verification.mdを参照してください。

ソースカーネル構築：ソース・設定・コンパイラ依存の固定、オフラインビルドと候補構成の組み立てツールを実装し、Python 24件で回帰検証しました。初回のオフライン構築、実VMの6起動、署名済みアプリの認証・LLM・ダッシュボード診断とブラウザ版比較が成功しました。同じMac上の別ビルドでカーネル・設定・ビルド報告のハッシュが一致しました。ライセンス文書は同じですがアーカイブのディレクトリ時刻とビルダー識別子は異なり、別環境・配布物全体の再現性、採用と信頼性の判定は未完了です。docs/kernel-build-verification.ja.mdに記載しています。docs/kernel-build-design.ja.mdとdocs/bugs/guest-boot-investigation.ja.mdを参照してください。

P3チャット：C1の有限APIと状態管理を24件（Swift全66件）で検証しました。C2基本CRUDと空履歴の10グループが署名付きアプリ内VMと使い捨ての固定参照サーバーで一致しました。参照環境の境界を含むPython全28件も成功。データ入り実ゲスト履歴、AI送信・実行中停止、チャットUIと高度な機能の比較は未完了です。docs/chat-verification.ja.mdとdocs/bugs/chat-state-investigation.ja.mdを参照。

P3チャット履歴：固定205件の最新200件＋過去5件、重複差分、最終6件を含む211件が固定参照の10グループと一致しました。署名付きアプリの新規VMで2回成功し、2回目はVM再起動後の全履歴・詳細保持とダッシュボード投入前の認証済み削除も確認しました。現在はSwift 66件・Python 34件が成功。チャットUI、AI送信・実行中停止は未完了です。docs/chat-verification.ja.mdを参照。

P3 C3：会話一覧・履歴・入力欄を実装し、ブラウザ/Macの一部比較、表示位置・下書き・変換中入力の回帰を確認。Swift75件（Core74＋AppKit1）/Python34件成功。Chatはin_progress。実行中停止、複数削除確認、クラウド応答、高度機能、全面的な外観/アクセシビリティは未完了。chat-verification.ja.md参照。

C4引用の有限API/モデル：7件とブラウザ関数11ケースが成功、Swift全82件。候補/挿入UI、実VM検索/ページ比較、128MiBストリーミング添付、サイド質問SSEは未完了。chat-advanced-design.ja.mdとchat-verification.ja.md参照。


C4操作段階: 引用コントロール、実ブラウザ編集9ケース、実VM・固定ブラウザの23件ページ分割比較を実装し、一部の実画面比較を確認。現在Swift95件（Core90＋AppKit5）、Python34件が成功し、再ビルドしたアドホックアプリの署名も検証済み。連続挿入・Undoはコンポーネント回帰が成功。追加取得時の一覧位置修正はMacロック解除後の実画面再確認待ち。再開時は新規VMと比較環境のマーカーを使い、一覧位置、連続挿入・Undo、全カテゴリ、実IME、VoiceOverを検証する。128MiB添付、サイド質問SSE、承認・詳細表示、クラウド応答と全21機能の受け入れは未完了。chat-verification.mdとbugs/chat-state-investigation.mdを参照。


A1添付本文readerを実装・対象テスト済み。本文全体128MiB、64KiB分割、観測可能なファイル変更拒否、取消後の再利用拒否、補助FormData3ケースを確認。Swift106件成功、アプリ再ビルド・署名検証済み。A1の基盤であり、添付通信や同等性の受け入れではない。次はA2の認証付きmultipart／runtime経路と実socketの逆圧・取消・早期応答・異常テスト。A3〜A5と引用の実画面再確認は未完了。chat-advanced-design.mdとchat-verification.mdを参照。


A2段階: 認証付きmultipart client／runtime、取り消せるdescriptor所有、await後の有効性確認を実装。socket11／認証client6／診断fixture1を含むSwift124件成功。新規の署名アプリ／VM再試行では3つの架空ファイルを転送・再取得し、全バイトとSHA256、後片付けを確認した。最初のソース候補実行はbootstrap前にpanicしたため、安定性の反証として保持する。A2の実停止／取消、A3の実128MiB／固定ブラウザ契約は未完了。次は使い捨ての固定ブラウザ添付比較を正式化し、上限・停止、A4／A5の状態とUI条件へ進む。カーネル候補は正式採用しない。chat-verification.mdとbugs/guest-boot-investigation.mdを参照。


A3 API境界段階: 新規の署名アプリ／VMと使い捨ての固定ブラウザ本体で、小さい3ファイルのハッシュ・順序・名前、本文128MiBちょうどの実受理／保存サイズ、1バイト超過拒否／元ファイル維持が一致した。Swift125件、Python39件が成功。Macの事前検証と本体HTTP400は異なる検証層であり、UI条件は合格にしない。次は大ファイルの上限付きダウンロード／ハッシュと実VZの転送取消・進捗を追加し、A4添付状態、A5選択UI／カード比較へ進む。カーネル安定性と全21機能の受け入れは未完了。chat-verification.mdとupload-a3-verification.jsonを参照。

A3全内容拡張: 有界ハッシュパーサ、実ソケットの取消/期限、認証専用API/世代検証をRED/GREENで実装。新しい署名付きVMと固定ブラウザ版バックエンドで134,217,517バイト全内容のSHA一致、8契約群一致、所有データ清掃を確認。Swift145件/Python42件成功。次は実VZ転送中の取消/停止と進捗、A4添付下書き状態、A5実画面比較。実測メモリ・カーネル安定性・全21機能の完成条件は未完了。

アップロード進捗/実中断: Swift157件（Core145・AppKit5・診断fixture7）/Python42件成功。新しい署名付きupload-cancel-a3-v2で17,852,806バイト通知後のTask取消でも利用継続。別転送は17,579,466バイト通知後、VM停止が稼働所有ソケット1本を取り消しCancellationError、再起動認証、未完成添付なし、所有データ清掃を確認。初回162バイト/停止証拠なしの実行は非合格として保持。128MiB全送信/ハッシュと固定比較8群も一致。実ダウンロード取消・multipart一時ファイル退避後の取消・実測メモリ・A4下書き状態/A5UI・引用外部再テスト・起動安定性は未完了。次はブラウザ由来の添付状態/会話引継ぎ/カード除去/送信失敗復元、その後pickerと実画面比較。

A4.1: Swift171件（Core159・AppKit5・診断fixture7）/Python42件、対象chat39件成功。相対メタデータ、UTF8完全一致の識別、会話別カード、送信時クリア/失敗・stop復元、添付のみ送信を実装。checksum固定のブラウザ送信4ケースを実行し待機/完了状態とJSONが一致、再生成と不一致ソースの実行前拒否も確認。アプリ再ビルド/署名確認。picker/cards/upload引継ぎの合格ではない。次はA4.2認証typed upload adapter、選択時会話作成/本文引継ぎ、会話削除と古いupload/取消/resetの所有権。その後実ゲスト/固定比較とA5実画面へ。Unicode空白の端点同等性も残る。

A4.2有限所有権/実機確認: Swift190件（Core176・AppKit5・診断fixture9）、Python45件、所有権/既存chat対象46件成功。認証typed upload、作成/本文/カード引継ぎ、最新1件進捗、古い結果/取消/次処理/stop/reset/削除の所有権を実装・レビュー。初回attachment-handoff-a4-v1はディスク全ゼロでもbootstrap前の空判定segfault/カーネルメモリ警告で失敗し保持。同じ構成の対照1回attachment-handoff-a4-v2で実typed vsock引継ぎ、LLMなし503復元2回、内容ハッシュ、カード除去後ファイル保持、選択分離、所有データ清掃を確認し、固定backend6契約群が一致。カーネル安定性/UIは合格にしない。次A5は最新Lazyweb、native picker/cards/進捗/エラー/取消の実装と外部比較。Unicode空白、退避後/ダウンロード取消、既知実行基盤faultは未完了。


A5前のUnicode送信判定: 固定oracleを拡張実行し、Store・本文・復元・会話作成前・Service判定のREDを確認して記録。共有trimでGREENを確認して記録。レビュー・全テスト・カバレッジ・署名ビルド・CIを確認する。ネイティブUI・実プロバイダー受入は未完了。


Unicode処理GREEN: Swift193件/Python45件、固定送信oracle9例、共有trimレビュー・行/領域/関数100%、署名アプリ再ビルド完了。UI判定はA5に残し、UI/実行安定性の受入条件は閉じない。次はLazyweb参照、固定ブラウザと比較しファイル選択・カード・進捗・取消・エラー・送信ボタン判定を実装。


A5順序: 入力可否・進捗・サイズ・権限寿命・ネイティブパネル設定をREDで記録→最小実装でGREEN記録→レビュー→全テスト/カバレッジ/署名ビルド→実ネイティブの選択取消・複数ファイル・カード・削除・LLMなし送信失敗の復元・進捗/取消・キーボードを使い捨て固定ブラウザと比較しスクリーンショットを残す。起動失敗は保持。未観測の条件は未完了に残す。


A5部分確認: ネイティブ操作部品を実装・レビューしSwift205件/Python45件・厳密署名検証成功。実パネル・取消・カード・解除・容量表示修正・転送途中取消を確認。ブラウザの送信前メタデータ/本文は一致、失敗条件は不一致で比較待機は観測後タイムアウト/片付け。次はLLM診断の設定投入前に新しい設定なしネイティブ環境を用意して失敗復元を比較し、送信後の添付描画を実装。進捗の見た目・キーボード・VoiceOver・引用再確認と全21機能/実行安定性は未完了。bugs/chat-attachment-ui-investigation.md参照。


A5互換確認: ファイル操作クロージャのMainActor明示でCIのコンパイル失敗へ対応、ローカルSwift206件成功。新しいリモートCIを確認する。復元の同一比較・履歴の添付・進捗同期・アクセシビリティ・実行安定性は未完了。


A6順序: チェックサム固定の解析例とモデルをRED/GREEN→MainActorの行取得でinline・空/失敗・再試行・取消・古い応答/defer・所有権をRED/GREEN→読取専用カード/本文UIとレビュー→全テスト/カバレッジ/ビルド・実際に保存した添付のVM/ブラウザ比較・スクリーンショット・所有権と片付け。他のA5条件・製品全体の条件は未完了に残す。


A6保存済み本文のチェックポイント: Swift221件（成功220、プロセス内SwiftUI AX検査1件は明示的スキップ）、Python49件成功。固定ソースのparser12ケースは再生成一致・改変ソースの実行前拒否を確認。署名済み新規VMと使い捨てブラウザで、本文＋添付／添付のみ／重複参照の保存内容が一致。外部CUAでNFD名54B・空ファイル0B、アスタリスクと改行の文字どおり表示、重複カード2個・削除操作なし、空の入力欄と送信無効を確認。両環境の所有データ削除・終了0、VM停止・一時Keychain削除も確認。parser/store行100%、store領域94.3%。user view行77.1%で、エラー／再試行UIは外部未検証。次はLLM未設定時の送信失敗復元を同条件で比較し、詳細取得エラー、長い履歴のスクロール・メモリ、VoiceOverを確認。進捗表示同期、カーネル信頼性、全21機能のゲートは未完了。


A7ゲート: モード判定・0件検証のRED→DEBUG比較環境実装GREEN→レビュー・全試験・署名再ビルド→新規使い捨ての両画面で本文＋添付／添付のみの503復元を確認→履歴・ファイル照合と後始末→リモートCI。以前のモデル試験だけでUI復元を合格にしない。


A7エラー修正: 完全一致の静的変換をRED→サービス境界修正GREEN→全試験・レビュー・ビルド→新規ネイティブUI再試験。初回の誤案内スクリーンショットも保持。入力復元は観測済みだが、エラーUX一致は再試験まで未完了。


A7チェックポイント: DEBUG未設定モード実装・レビュー済み。固定ブラウザとMac版の本文＋添付／添付のみで失敗後に元の本文・36B/0Bカード2個が実画面上で復元。Mac版は再起動前後ともLLM0件。初回は未設定503をDB障害と誤案内しUX不合格。5言語の完全一致・静的案内へRED5assertions→GREEN7テストで修正。Swift224件（成功223・AX1スキップ）、Python49。plan行100%、ChatService96.95%。両プロセス終了0、VM停止・Keychain削除、参照リソース削除を確認。ネイティブの私的な比較用ディスクにはfixtureファイルを保持し、個別削除・内容ハッシュは今回再確認していない。次は2285311の署名済み実画面再試験、失敗後の履歴・ファイル照合と削除、その後進捗・アクセシビリティ・長い履歴・全21機能の残項目。


A7修正後の外部再試験: 2285311の署名済み新規VM V2で、本文のみの送信拒否後に静的なLLM設定案内・正確な入力保持・空の会話を実画面確認。画像・AX・repaired native-resultsを保存。終了0、VM停止・Keychain削除も確認した。これにより上記「修正後の案内再試験待ち」は解消。本文＋添付／添付のみの復元証拠は修正前12a8a8eのままで、ファイル個別削除・内容ハッシュ・API履歴照合、長い履歴・アクセシビリティ・進捗・カーネル・全21機能のゲートは未完了。


言語リリースゲート(R8): ネイティブ直書きとbackendの組み込み・生成文言を監査→日英限定の永続切替・String Catalog→backend出力言語同期→初回・双方向切替・再起動・既存状態の試験→全21機能の通常・エラー・空・読込・確認・アクセシビリティを日英両方で固定ブラウザのフローと比較。独自／ユーザー／モデル内容を保持し、対応言語の意図した相違を記録。初期監査のみ実施済み、実装・全受入は未完了。日本語固定のままで目標完了にしない。


L1順序: 言語・Locale・初回優先・不正移行・永続・無関係設定隔離テストRED→型付きobservable設定GREEN→レビュー・全試験・対象カバレッジ・署名ビルド・CI。その後日英String Catalogと実切替、切替時の入力・選択保持、backend output_language同期の失敗・復旧、全21画面監査。設定テストだけでUI合格にしない。


L1チェックポイント:690c4e1は型付きの日英設定保存だけを実装。対象5テスト、追加2ファイルの行・領域100%、全Swift229件（成功228・AX1スキップ）・Python49成功、レビュー承認。保存値優先・不正値の英語修復・suite分離と無関係設定保持を新規インスタンス間で確認。実画面切替・カタログ・backend同期・アプリプロセス再起動は未検証。次L2はUI前Lazyweb、String Catalogとリソース、Chat状態を再作成／消去しない切替、両言語画面比較。その後失敗時の扱いを定めbackend同期。全体目標は未完了。


L2順序: コンパイル済みカタログの日英・機能名・フォールバックRED→リソース／ヘルパーGREEN→pickerとRoot接続・レビュー→全試験・対象カバレッジ・署名リソース→実画面の双方向切替と入力／選択／VM保持を比較。機能内部とbackend同期は未完了のまま。


L2共通画面チェックポイント: カタログ・ヘルパーとツールバーの日英選択を接続。署名5a66610の実画面でja→en→jaの本文・23B添付・Chat／会話保持を確認。別プロセスでもen保持、元のjaへ戻した。固定ブラウザはen→ja→en、候補5種類に対しnativeは意図した2種類。画像後に機能名6か所をd949dc8 RED6→ad9a7fe GREEN5カタログ試験で修正し、最終署名リソースも検証。Swift234件（成功233・AX1スキップ）、Python49、ヘルパー行100%・領域97.4%。初回incrementalで93失敗したが変更なしのprobe・新規scratch成功、原因未確定の反証を保持。VM診断2実行・参照は終了0、停止・Keychain／参照リソース削除。機能内部・backend同期・中国語説明／韓国語初期名・システムメニュー／生状態名・VoiceOverと全体ゲートは未完了。次L3は移植済み画面内部と静的エラーの翻訳、独自内容保持、その後backend同期と失敗状態。


CI互換ゲート: 実CI失敗をREDとして保持、exporterのschema・決定性・陳腐化検査RED→GREEN、互換リソースとCI/build接続、legacy native build-systemのcold試験・署名同梱・レビュー・リモートCI。同じ非互換物を再試行して合格待ちしない。


L2互換チェックポイント: 初回CI40110609236は旧SwiftPMのカタログ未コンパイルコピーで失敗。厳格exporter・派生en/jaリソース・一致検査で修正。cold legacyカタログ5件、通常Swift234件（成功233・AX1スキップ）、Python52成功、exporter行94.6%。最終署名同梱とリモートCIを確認し、言語全体・backend・全21ゲートは未完了を維持。


L3ゲート: 初期文言／編集保持とchatカタログRED/GREEN→AppKitボタン・パネル・エディタ・進捗の日英RED/GREEN→操作／空状態接続・レビュー・全試験・coverage・署名→本文・添付・カーソル保持と固定ブラウザ比較。エラー・会話初期名・backend・読み上げの残ゲートまでChat/R8全体は合格にしない。

L3チェックポイント：Chat操作・既定文言をSwift240件（成功239・既存AX1スキップ）、Python52件、警告なしの署名ビルドで検証。実native／browserの英語→日本語で混在本文と21B添付を保持。画像2a62b55は全文修正5232876より前で、最終リソースは別検証。韓国語初期名は明示翻訳するとbackend自動命名を壊すため未解決。専用State全体を破棄し、個別ファイルハッシュは主張しない。[Chat日英検証](localization-chat-verification.ja.md)を参照。R8／Chat／全21ゲートは未完了。

L4aエラー基盤：ネイティブの静的検証文字列をBackendValidation型に移し、日英エラープレゼンターを追加。store移行中は従来の日本語LocalizedError互換を保持。明示言語で取得しOS設定に依存せず、未知のエラーを文字列化しない。HTTP／Keychain数値のみ埋め込み、任意のserver本文・パス・秘密を表示しない。この基盤だけでUIエラー切替／R8を合格にしない。

L4a検証済み：ea39007の意図した未実装表示／理由RED→a3f7681 GREEN3。全Swift243（成功242・既存AX1スキップ）、Python52、表示ヘルパー行26/26・領域21/21。最終署名同梱は各言語29項目一致、レビュー済み。store／UI言語接続は未完了。bugs/error-localization-investigation.ja.mdを参照。

L4b Chatエラー：storeは安全な型付きAppErrorMessageを保持し、viewの現在localeで表示。view再作成・リクエスト発行・本文／添付／選択変更をしない。診断／旧試験向け日本語Stringは計算プロパティで互換保持。一覧／履歴／送信／停止／workspace／添付／部分削除／引用ページング／本文／詳細を対象とし、キャンセル・世代・所有者判定を維持。未知のエラーはraw情報を保持せず型付きfallbackへ縮退。store RED/GREEN・全試験・レビュー・署名・実native/browser失敗送信中の言語比較を別ゲートとする。Lazyweb検索chat error retry messageは隣接DoorDashメタデータのみ（類似度.385）で視覚証拠とせず、固定版のエラーUIを基準にする。

L4bチェックポイント：96eae3e型付きstore未実装RED→0796897 GREEN3。Swift246（成功245・既存AX1スキップ）、Python52、安全な値の行13/13・領域11/11。署名アプリと各言語33エラー項目一致、レビュー済み。ユーザーはMac解除を後で行うため、実native/browser失敗送信中の言語UIゲートは未完了。新規runtime fixtureは未開始。localization-chat-errors-verification.ja.md参照。

L4c移植済み画面のエラー／通知ゲート：AuthenticationSession・LLMStore・DashboardLoadStateはAppErrorMessageを保持し、日本語Stringは計算プロパティで互換。LLM完了通知はカタログキーで保持し、再取得失敗と独立させる。認証・LLM設定／編集／rotation・dashboardの現在view localeで表示。localeによる認証／変更操作／poll再起動やパスワード／APIキー保存をしない。フォーム・規約同意・世代・前回データを保持。周辺未翻訳操作／規約言語は別ゲート。検証失敗・未知エラー秘密除去・保存成功後の再取得失敗・dashboard前回データ保持を試験。Lazyweb settings inline validation errorは隣接Gopuff captchaメタデータのみ（.356）で視覚証拠としない。実native/browser比較はMac解除まで延期。

L4cチェックポイント：a229ee3型付き値未実装RED→7b6c8c5 GREEN4、4cbb734操作／poll回帰追加GREEN7。最終Swift253（成功252・既存AX1スキップ）、Python52、署名エラー／通知は各言語39項目一致。認証／LLM／Dashboard安全なエラーと通知6種類を接続、レビュー済み。実native/browser、周辺ラベル／規約とruntime／backend／全体ゲートは未完了。localization-screen-errors-verification.ja.md参照。

L5認証／規約：ネイティブ認証ラベルを型付きカタログで日英化。AuthTerms.loadAllで固定規約の両言語を一度読み込み、既存シートの現在localeで表示。パスワード／確認／同意／focusのbinding・task同一性・送信・phase変化時の消去を保持。読了は固定browser同様、シートを開くたびリセットし、表示中の言語変更ではreadToEndを保持。言語に基づくview再作成なし。各言語28項目のauth.terms全文が固定参照と一致し、規約改変や実行時ネットワーク取得なし。自動setup-token／固定ユーザー名の案内はnativeの実動作に合わせる。resource/API RED/GREEN・レビュー／全試験／署名同梱を確認し、実native/browserの操作／scroll／読了はMac解除まで未完了。Lazyweb terms agreement modalはPostman隣接メタデータのみ（.479）で画像証拠にはしない。

L5隣接読了判定修正：初期の空スクロール領域で、規約読み込み前に読了を付与しない。シート内の読了状態を型で保持し、Equatableなviewport観測にdocumentLoadedも含める。短文でatEndがtrueのままでも読込完了を別イベントとして扱う。失敗／空文書は同意ボタンを有効化せず、読込済み文書の末尾で読了を保持し、表示中の言語変更では維持、新規シートは未読。ログイン権限強化ではなく読了UIの修正で、独立した同意checkboxは変更しない。別RED/GREENと実scroll比較待ち。

L5チェックポイント：b4c3172キー／loader未実装RED→3c70904 GREEN3、cc1e53c読了状態RED→a9e3fa3 GREEN5。Swift258（成功257・既存AX1スキップ）、Python52、loader／読了行100%。署名は各言語23文言・規約28項目一致。レビュー済み、実geometry／パスワード入力／browser比較はMac解除待ち。他画面／backend／runtime／全21ゲート未完了。localization-authentication-verification.ja.md参照。

L6 LLM UI：設定／カード／編集／モデル選択／rotation／全体retry／数値検証／ヘルプを型付き日英カタログへ。名前付きplaceholderを一度だけ展開し、任意モデル名・マスク済みキーhint・値を再帰的にテンプレート解釈しない。tag／API列挙値／prefix／binding／不正入力／dirty／シート所有者を保持し、既存fieldGenerationは確定した再取得／保存時だけ変更。localeのid／taskや通信／変更操作は追加しない。Lazyweb AI model provider settingsはV7隣接メタデータ（.535）で画像証拠とせず、固定browserを基準にする。カタログ／format RED/GREEN・全試験／レビュー／署名を確認し、実native/browser切替はMac解除待ち。

L6チェックポイント：e377f16 formatter／catalog意図したRED→c855245 GREEN3。Swift261（成功260・既存AX1スキップ）、Python52。LLM108文言／埋込11を日英化、展開ヘルパー行100%、署名両言語108項目／token一致。5ファイルCJK0／Picker tag維持、レビュー済み。モデル／独自／backend内容保持。実数値入力／layout／sheet／browser合格は解除後、全21／全体ゲート未完了。localization-llm-ui-verification.ja.md参照。

L6 CI訂正：40135493632のJSON Data比較2失敗を、1da4b81の意味上比較＋対照試験で対象3件成功。コンパイル失敗中のd09e852 GREEN表示は無効証拠。製品処理は変更なし、最終hosted再実行の成功が必要。

L7 Dashboard UI：見出し・群・空／前回／読込状態・選択・chart軸／系列／凡例／読み上げ・集計・期間件数・資産／通信／システムを日英化。metrics／計算／日付ID／query／poll／選択ID／tag／遷移は保持。既知task／engine／severityは固定status辞書と一致し、raw識別子完全一致だけ変換、未知文言保持。活動5コードは表示だけ翻訳し、独自tool名／worker／summaryはそのまま。chart系列と凡例scaleのキーは同じ翻訳を使い、色／選択の実一致はUI確認待ち。既存の一度だけの埋め込み展開を使用。resource／status／集計不変RED/GREEN・レビュー／全試験／署名、実native/browserは解除待ち。Lazyweb usage analytics dashboardはGoogle Analyticsメタデータ（.631）で画像証拠ではなく、固定browserを基準にする。

L7チェックポイント：9a2e383表示未実装RED→a41c2fa GREEN3。Swift264（成功263・既存AX1スキップ）、Python52、helper行100%。署名両言語103項目／埋込16一致、固定status15・未知／tool保持。Core集計／model／service／store不変、tag／色をソース監査、レビュー済み。実native/browser chart／layout／選択／VoiceOverは解除後、全21／runtime／backendゲート未完了。localization-dashboard-ui-verification.ja.md参照。

L8 runtime／比較画面：操作・lifecycle6状態・sidebar・機能比較表／件数を現在localeで表示。nativeStatusゲート・機能ID／browserパス・未知機能名を保持。VMController／DesktopRuntimeは既存raw診断に安全なAppErrorMessageを並行保持し、同じ起動境界で消去、既存fail／catchだけで設定。RuntimeError種類をカタログキーへ変換し、任意stage／path／detailは埋め込まず、未知frameworkエラーはruntime用fallback。VM構成／権限／protocol／状態遷移／認証／disk／pollは変更なし。ゲストログ／CLI診断はraw保持。VMを起動しないresource／状態／失敗境界RED/GREEN・レビュー／全試験／署名。実native操作とOS標準メニューは未完了で、SwiftUI localeだけでは標準AppKitメニューは変わらない。Lazyweb virtual machine status settingsはHeight隣接メタデータ（.383）で画像証拠ではない。

L8チェックポイント：346f7b4表示未実装RED→a4e9c7b GREEN4。Swift268（成功267・既存AX1スキップ）、Python52、runtime／error helper行100%。署名両言語34文言／埋込3一致。安全な並行errorはraw診断とguard／resetを保持、ソース復元／hash監査で状態／構成／protocol／disk／認証flow不変。レビュー済み、新規試験はVM／disk前で停止。実native／標準menu／Rootcatalog／backend／出所／全21は未完了。localization-runtime-ui-verification.ja.md参照。

L9 menu境界：既存NSMenu／action／responder／shortcut／target／有効状態を保持。既知の標準actionと静的表示名の組だけ翻訳し、登録済みwindow／help／servicesの同一性とroot見出し名＋操作から標準群を識別。未知／独自／装飾／custom view・動的window／service名は保持し、menuを再構築しない。アプリ言語とAppKit didBeginTrackingで更新し、SwiftUIによる差し替えに備え毎回現在mainMenuを取得。selector observer1つを明示stopし、timer／操作実行／保存／VM変更なし。合成menuのmetadata／往復／未知・observer差替／stopと28項目catalogをTDD。実OS dispatchと全動的／未知項目の網羅は解除後。Lazyweb desktop application menu barはCluely隣接メタデータ（.340）で画像証拠ではない。AppKit interopスキルの狭い接続を使い、SDKの通知／登録menu APIを確認。

L9静的menuチェックポイント：8d65447未実装RED→bab27b4 GREEN5、b97a197 Close Window実RED1→b757992 GREEN7。Swift275（成功274・既存AX1スキップ）、Python52、Mac実行objectのmenu行100%／領域96%、署名両言語28項目一致。22selectorのmetadata保持・observer差替／stopを試験、レビュー済み。動的Undo／ExitFullscreen／ShowHide／SwiftUI selector・実tracking／dispatchは解除後で未確認、OS-menu／全21合格にはしない。localization-menu-verification.ja.md参照。

T1 Tasks有限coreはtasks-core-design.ja.mdに従う。作成全optionと一覧／詳細／metadata／control／batch／delete、所有者／変更結果と日英型付き検証を実装。active化の副作用やUI完了扱いなし。RED/GREEN／全回帰／review／署名後、実VM／参照／UI合格を検証する。

T1記録：36b227b未実装APIの意図したコンパイルRED→3f47d06 GREEN8。追加後の全体Swift287件（286成功/既存AX1件スキップ）、Python52件成功。最終タスク13件に送信前/後キャンセルを含みます。新規3ファイルの行/領域100%、署名付きビルドと日英各5文言を照合、レビュー済みです。固定参照ハッシュ一致、実API/UI/VM通信なし。Tasksはpending、状態/UI/実参照/実行/全21機能のゲートは継続します。tasks-core-verification.md参照。

T2タスク状態はtasks-state-design.mdに従います。一覧/詳細と選択ID、競合/ライフサイクル保護、T1全有限操作の確定/入力拒否/不確定結果、再取得失敗後も操作確定保持、自動再試行/アクティブ選択なし、キャンセル可能な10秒ポーリングを実装します。画面/機能/実行環境の受入は未完了です。バックエンド状態のみでLazyweb対象外。RED/GREEN、応答順序/キャンセル/リセット制御試験、全体回帰、レビュー、署名付きビルドを必須とします。

T2記録：9e10d78未実装RED→732ab69 GREEN10、8ceabdf追加13。1efb06fキャンセル済み遷移の実行RED1件/7失敗→e950f21 GREEN14。最終Swift302件（301成功/既存AX1スキップ）、Python52成功。ストア行99.26%/領域94.55%、レビュー・署名ビルド・厳密署名検証済み。状態層のみ、UI未接続、実API/VM/ホストAI実行なし。セッション所有/リセット/不確定表示は今後の連携必須事項です。タスク/全21機能/実行/配布ゲート継続。tasks-state-verification.md参照。

T3はtasks-ui-design.mdに従い、一覧/詳細、検索/状態/並べ替え、名前/ピン/制御/削除をウィンドウ所有T2ストア、認証ルート、ダッシュボード遷移へ接続します。日英文言、不確定結果表示、既定オフの削除5項目、言語切替で画面再生成なし。機能はin_progressのみ。作成、分類/アーカイブ/一括/高度な詳細と実比較は今後も必須です。RED/GREENの表示/状態/レイアウト試験、レビュー/全体回帰/署名ビルド、実比較は解除後に実施します。

T3記録：0c01a4b未実装RED→f0e460b GREEN6、80ca7c3内訳/エラーRED→b38f3b3 GREEN8、51c0531対象切替実行RED1/2失敗→e286140 GREEN9、d1d2464入力所有RED→741717f GREEN14。最終Swift316件（315成功/既存AX1スキップ）、Python52成功。表示ロジック行91.36%/モデル98.46%、UIカバレッジは部分的です。署名付きビルド/厳密署名と日英57文言を照合。21/27/243の機能表を同期しTasksはin_progress、17画面pending。レビュー済み。実API/VM/実UI/インストールなし。作成/一括/分類/高度タスク/全21機能/実行/配布は継続します。tasks-ui-verification.md参照。

T4はtasks-create-design.mdに従い、選択肢とT1全12項目の作成フォーム、順序付きモデル、関連タスク/会社/分類、テンプレート適用、安定IDのルールを実装します。全入力/取得/確定/閉じるをコンテキストIDで保護し、作成は明示的に1回、確定で取得失敗と分離して消去、不確定は下書き保持/再送抑止します。作成添付/テンプレート分類管理/全タスク/実行/UI受入は継続。RED/GREEN、競合制御、全体回帰/レビュー/署名、実比較は解除後です。

T4記録：889b32d→c1b9fe4 CoreGREEN3、6c85680→d8ea915状態GREEN4、ee46711実ID/BOM実行RED4失敗→8105e5c GREEN8、cfa4c93→bc4c674 UI GREEN10、d5b6a25追加14、e1edf9f上書き実行RED3失敗→f56c82a GREEN15、fe75585 Unicode実行RED12失敗→a8e3302 GREEN16。最終Swift332件（331成功/既存AX1スキップ）、Python52成功。署名ビルド/厳密署名/日英42文言を確認。Core/状態の行93〜100%、UI分岐は部分的、レビュー済み。添付/管理/実作成と拒否/比較/全21機能/実行/配布は継続。tasks-create-verification.md参照。

- [ ] 他のサービス一覧変換にも生FEFF/NFC/NFD試験を広げる。T4の修正は自身のカタログのみ。

B1はboot-preflight-design.mdに従い、空/非空と検査異常を区別し、fail-closedの書式化条件を維持します。専用の新規使い捨て状態に1回だけ起動し、読み取りAPIと固定の秘密を含まない結果を出すVMProbeを追加します。ユーザーデータ/隔離方針は変更せず、TDD/判定/書式化ガード試験、旧新プロファイル各1回の制御実験、レビュー/全体回帰/署名を行います。カーネル原因/安定性/実UI比較は未完了、インフラのみでLazyweb対象外です。
