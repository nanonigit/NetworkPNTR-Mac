# チャット基礎部分の検証

状態：C1の有限APIと状態管理を実装し、C2の基本CRUDとデータ入り履歴・差分を署名付きアプリ内VMと固定したブラウザ版サーバーで比較し、VM再起動後の完全保持も確認しました。チャット基本画面を実装し外部UI比較を一部実施しました。AI応答・実行中停止、添付・SSE、全面的なUI比較は未完了で、feature-mapはin_progressです。

## 証拠と時系列

1. 履歴の重複・順序違い・過去ページの統合、既知と未知のイベント、ツールの対応・詳細・メタデータ、符号あり・なし64bit整数の精度、nullを含むLLM・実行・ピン情報、不正な必須データを7件で確認しています。最初は未実装のChatActivity参照で失敗（RED 4505d7c）し、実装後の7件が成功しました（GREEN 50e60ac）。
2. 読み取り専用レビューとソース比較で、空のpinned_atの扱いがブラウザ版と異なることが分かりました。追加テストを実行してXCTAssertFalseの失敗を再現しました（RED 3395e8e）。Swiftは値の有無を調べていましたが、JavaScriptでは空文字列はfalseです。明示したpinned=falseが時刻より優先される条件も維持します。
3. pinned ?? !(pinnedAt?.isEmpty ?? true)に修正し、追加ケースを含むSwift全49件が成功しました。ChatModelsの37/37行、36/36領域を通過した計測結果をevidence/chat/models-verification.jsonに保存しています。分岐カバレッジや製品全体のカバレッジを推定するものではありません。レビューは修正を承認しましたがテストの再実行はしておらず、テストの根拠はローカルの実行結果です。

## 原因と再発防止

なぜ差が出たか：値の有無と真偽変換を同じものとして扱ったためです。なぜ見落としたか：通常のDB時刻は空でなく、最初のテストが欠落・正常値・明示falseだけだったためです。なぜ移植で問題になるか：SwiftのOptionalとJavaScriptのBooleanの意味が異なるためです。今後はソースからnull・欠落・空・非空・明示falseの表を作り、今回の実際の失敗と回帰テストを残します。Fishboneの切り口は言語の意味、JSONのnull、過去データ、境界値のテストです。

利用者のブラウザ会話は作成・変更していません。空画面の基準画像は、データ入りのネイティブUIが同等である証拠ではありません。有限API・状態管理の証拠は以下に記録します。データ入り実ゲスト履歴、AI送信・実行中停止、添付、引用、SSE、承認、日本語IME、クラウド通信は未完了です。

## C1とC2基本操作の確認

基本CRUDを確認した時点では、Swift全66件とPython全28件が成功しました。チャットのSwiftテストはデータ型7件・サービス6件・状態管理11件の計24件です。正確なパスとJSON/null、Unicode文字数、不正応答、部分削除、機密情報を含めないエラーを検証しています。通信を意図的に待機させ、重複要求、選択・停止・リセット後の古い応答、過去履歴と差分の統合、編集中の下書き保持、送信成立後の更新失敗、最終1000件の排出、停止後の再開を確認しました。上記49件の記録は過去のモデル実装時点です。

core-verification.jsonの計測はChatModels 37/37行（100%）、ChatService 106/110行（96.36%）、ChatStore 197/209行（94.26%）。領域は100%・93.69%・82.66%です。分岐と製品全体のカバレッジは計測・推定していません。

署名付きdebugアプリからソースビルドした6.12.114-artexカーネル、1 vCPU、NICなし、ホスト共有なしの新規VMを起動しました。認証済みChatServiceで作成・改名、ピンの付け外し、明示nullによるモデル設定解除と復元、空履歴と差分、存在しない詳細の空応答、実行していない会話の停止、空送信と不正モデル拒否、重複除去・一部失敗を含む一括削除、単体削除と後片付けが成功しました。AIのターンは開始していません。その後の認証・LLM設定の再起動保持、ログイン・ログアウト、起動中の停止も成功しました。結果のui_click_workflow_verifiedはfalseです。

同じ10グループを、独立した固定ブラウザ版バックエンドとPostgreSQLでも確認し、結果が一致しました。参照環境は内部専用Dockerネットワーク、ホスト共有・公開ポートなし、非特権アプリ、capability除去、使い捨てtmpfsです。削除するのは今回作成したコンテナとネットワークだけで、利用者の既存ブラウザ環境は変更していません。比較用Docker Desktopは動作したままであり、Docker未導入のMacでの受け入れ試験ではありません。参照fixtureはimport時に通信せず、ホストや専用マーカーのないLinuxでの実行をHTTP前に拒否します。

証拠はevidence/chat/finite-contract-vm.json、finite-contract-reference.json、finite-comparison.json、finite-native-results.json、core-verification.jsonです。生ログ・状態ディスク・セッション情報はgit対象外です。この時点ではデータ入り履歴・実行中停止・ネイティブUIは未完了でした。データ入り履歴の追加検証は以下に記録します。

## レビューで見つかった回帰

RED da2b6c7で古い停止済み差分が新規送信を見失う3つの失敗を再現し、GREEN 28d8e6dで変更世代と同じ通信枠での再取得を導入しました。RED 6a46acbで停止後に古い送信が通信を再開する3つの失敗を再現し、GREEN 539a5abで一覧更新のawait後にも世代とキャンセルを確認します。参照環境の境界はHTTPをモックしてRED f7d3827の2失敗・1エラーを確認し、GREEN bdd01e5でLinux・UID・明示マーカーとmain限定実行を導入しました。詳細と再発防止はbugs/chat-state-investigation.ja.mdに記録します。レビューは読み取り専用で、実際のテストはローカルで実行しました。

## C2：データ入り履歴・最終差分・再起動保持

最新の検証ではSwift全66件・Python全34件が成功しました。投入処理の追加テストはホスト・CPU・UID・DSN・処理段階の拒否、機密を含めない失敗、認証情報の環境変数への配置、チャットとダッシュボード双方のlibpq環境継承を確認します。単体テストはpsqlをモックし、実SQLはVMと専用の参照PostgreSQLだけで実行します。レビューによるRED/GREEN修正はbugs/chat-state-investigation.ja.mdに記録しています。

新規VMを使う署名付きアプリの2回の検証で、205件のデータから最新200件と過去5件の取得、カーソルの維持、未知値を含む7種のイベント、ツール入出力の対応、トークン情報、一覧からの詳細除外と10,752バイトの完全詳細の別取得、5件が重なる差分の重複除去、最終6件を加えた211件を確認しました。別の会話から最初の会話の詳細は取得できません。両方とも検証用データを削除した後、ダッシュボードの投入・検証まで成功しました。

2回目は211件を保持したままVMを正常停止・再起動し、Keychain認証を復元しました。最新200件と過去11件を再取得して全イベントを再起動前と比較し、完全な詳細も確認した後に削除・後片付け成功の証拠を保存します。再起動後の認証セッションを使い、古い起動時の通信情報は使いません。履歴保持と、その後の認証・LLM・ダッシュボード検証がすべて成功しました。

同じ初期・追加SQLを使う固定ブラウザ版の独立したHTTP取得・統合と、履歴の10グループが一致しました。2回のネイティブ結果も同じ参照結果と一致しています。libpq修正後もダッシュボード12シナリオが独立したブラウザ集計・使い捨て参照環境と一致しました。利用者のブラウザデータと固定ソースは変更していません。

証拠はevidence/chat/内のhistory-contract-vm.json、history-contract-reference.json、history-comparison.json、history-native-results.json、history-verification.jsonです。2回目はホストPATH=/usr/bin:/bin、使用できないDOCKER_HOSTで実行しました。比較・ブラウザ用のDocker Desktop自体は起動しており、Docker未導入Macでの受け入れは未完了です。選択したソースビルドの1 vCPUカーネルは開発候補のままで、標準ランタイム・信頼性を合格にはしません。チャットUI、AIバックエンドでの実行中停止、添付・SSE・引用・承認・クラウド通信は未完了です。画面写真をチャットUI同等性の証拠にはしていません。

## C3 ネイティブ基本画面（受け入れは一部のみ）

会話一覧・履歴・AppKit入力欄をアプリ内VMに接続しました。機能表はin_progressで、全機能の合格条件は未完了です。最新ローカル検証はSwift75件（Core74件＋実NSTextViewの変換中文字列回帰1件）、Python34件が失敗0。対象ファイルの行・領域カバレッジはevidence/chat/ui-verification.jsonに記録し、分岐・製品全体の網羅性は主張しません。

実画面操作で空/データ入り画面、同じ211件の最新200件と過去11件、別取得の10KB詳細、名前変更、ピン留め、明示モデル、エージェント絞り込み、複数行下書き保持、Shift+Enter、制御キー送信モードを確認。実際のEnter送信は会話作成・ユーザー本文保存後、NICなしVMでモデル/通信エラーになりました。クラウド応答成功ではありません。使い捨ての固定ブラウザ版では同じデータと変更操作、および送信中の停止を確認しました。Mac版の実行中停止と複数削除の確認画面は実操作検証待ちです。

過去履歴取得で先頭表示が12から2へ飛ぶ不具合を実操作で再現（RED48981f5）。表示アンカー保持とスクロール対象レイアウトで修正し、11件追加後も12が同じ位置に残ることを再確認しました。履歴待ち中の下書き消失/上書きもRED後に69a4b3aで修正。実NSTextViewの変換中コールバックが別会話の下書きを上書きしない回帰も成功しました。物理的な日本語IME操作、VoiceOver/フォーカス、全面的な外観評価は未完了です。

比較用VMの1回目は正常停止と一時Keychain削除に成功。2回目は画面操作後に外部レビュー待ちの明示的タイムアウトで終了しました。検証ハーネスのタイムアウトであり、全診断成功にも製品のVM障害にも数えません。該当プロセスは残っていません。MacキャプチャにはシステムのPasswordsオーバーレイが写っており、外観合格の証拠にはしません。

evidence/chat/ui-verification.json、ui-scroll-red.json、ui-scroll-green.jsonとMac/ブラウザの画像を参照。すべて合成データで、実ユーザー情報やAPI秘密を含みません。画面構成は実際に閲覧した[Lazyweb参照](https://www.lazyweb.com/agentic-search/5c99e8ec-0f3a-4e76-a173-994b1b86da0a)を参考にし、挙動は固定ARTEXを正とします。組み込みエージェントの名称/説明の言語差、添付・引用・サイド質問・承認・SSE・高度表示・todo・クラウド通信・配布/VM安定性は引き続き未完了です。

## C4 引用の有限API・モデル

chat-advanced-design.ja.mdに根拠と設計を記録。RED395c5a0では型未実装で失敗し、GREEN46ceb2dで6件成功。9分類、正確なInt64、Unicode/プラス記号の検索とカーソル、入力上限、不正応答/エラー秘匿、ブラウザと同じトークンを確認しました。固定TypeScript関数をNode26で実行した11ケースとSwiftの結果が一致。括弧/BOM空白/UTF-16サロゲート境界も含みます。この基準データはクラウド/UIの成功証拠ではありません。

全Swift82件（Core81＋AppKit1）が失敗0。引用ファイルは85/85行・50/51領域を実行し、分岐/製品全体の網羅性は主張しません。Pythonコードは変更しておらず前回の34件がチェックポイントです。署名付き開発アプリの再ビルド/検証は別途実施。画面への挿入、実VM検索/データ入りブラウザのページ送り比較、C3未完了条件は引き続き保留。ブラウザのJavaScript数値精度制限を移植せず、ネイティブIDは正のInt64を正確に保持します。

途中の実行ではnext_cursor消失と不正カーソル検証漏れの2失敗を検出。共通デコーダーがsnake_case変換する一方、型にも生のsnake_caseを指定していたことが原因でした。CodingKeysをnextCursorに修正し、継続と拒否の両方を回帰に保持。5 Whys：重複したキー指定→デコーダー変換と不一致→optionalがnil→ページ送りが黙って終了→以前に引用応答テストなし。Fishbone：共通復号、optional、通信キー、ページ送りテスト。Timeline：型なしRED→実装→実行2失敗→キー修正→対象6件/全81件GREEN。evidence/chat/mention-token-reference.jsonとmention-verification.jsonを参照。この単体/関数比較では実ユーザー/VMデータを変更していません。

追加の検索境界回帰c78069cで、FoundationがU+200Bを削除しGoは保持する差を検出しました。[Go White_Space](https://pkg.go.dev/unicode#IsSpace)を明示しスカラー単位で除去して送信値を修正。NELは除去し、U+200B/BOMは符号化した要求に保持します。別の調査でFoundationのquery値復号自身が先頭BOMを落とすと分かったため、その検証は同じ復号器でなく送信percent符号化値を比較するよう修正しました。これは検証ハーネスの問題で、2個目の製品欠陥ではありません。最新はSwift82件（Core81＋AppKit1）、引用7件。5 Whys：プラットフォームの文字集合差→名前で標準trimを選択→検索バイト変更→不透明カーソルの検索条件不一致→非ASCII書式文字の境界未検証。再発防止：ソース規定の空白と送信バイトの回帰。


## C4 ネイティブ引用操作の検証段階

現在はSwift95件（Core90件、実AppKitコンポーネント5件）とPython34件が全件成功。ソースビルドのカーネル候補を使って開発用アプリを再ビルドし、アドホック署名を検証した。カーネルの正式採用、配布やクリーンMacでの実行安定性の合格を意味しない。

入力欄にカテゴリ選択、検索の待機集約、候補のページ分割、インライン再試行、キー選択、引用文字列の挿入、選択済み引用の削除を実装。世代チェックで古い検索・ページ応答を無効化する。固定ブラウザのヘルパーを実行した編集9ケースと比較した。従来の引用文字列11ケースは別の検証段階として保持する。対象の行カバレッジは編集90/90、検索状態43/45、引用サービス85/85であり、製品全体や分岐のカバレッジとはしない。

新規の専用VMと使い捨ての固定ブラウザ環境で同じ架空の企業23件を作成。ID、表示名、説明、降順、先頭20件＋次3件、カーソル終了、ID検索、空検索の正規化結果は完全一致した。両方の実画面で検索、残り3件の取得、Enterによる23番の引用挿入（送信なし）、チップからの削除を確認。Mac版では下矢印2回とEnterによる企業カテゴリ選択も確認した。全9カテゴリ、アクセシビリティ、実IME、画面全体の受け入れは未完了。

Mac実画面で、一覧を下へスクロールして「さらに読み込む」を押すと先頭へ戻る不具合を再現した（RED6d37916）。追加取得後のスクロール指定をキーボード継続時だけに限定した。ビルドと既存テストは成功したが、OSのロックにより実画面の再確認は保留。ロック中に失敗した操作は実行済みと扱わない。同じ引用の連続挿入とUndoは実NSTextViewの回帰テストが成功しており、最後の実画面再確認は残っている。

診断処理は所有する企業IDだけを削除し、一時Keychain項目の削除とVM停止まで成功した。比較用プロセスも正常終了し、所有するコンテナとネットワークを削除済み。既存8787環境は維持した。次の実画面検証では、新しいVM状態と比較環境のready/終了マーカーを使い、古いready情報を稼働中の証拠にしない。

証拠はevidence/chat/mention-interaction-verification.json、mention-contract-vm.json、mention-contract-reference.json、mention-native-results.json、mention-page-scroll-red.json、mention-native/browser-candidates/insertedのPNGペア。今回のC4画像には旧C3画像のPasswords浮動表示がない。レイアウトには目視確認した[Lazyweb資料](https://www.lazyweb.com/agentic-search/4f3afa9b-e394-453b-a6da-171ce7617832)を使用し、動作の基準は固定ARTEXとする。128MiB添付、サイド質問SSE、承認・ツール表示、クラウド応答、機能全体の合格条件は引き続き未完了。


## A1 添付本文の上限付きreader

RED42e642aでは未実装ChatMultipartBodyを参照するテストのコンパイル失敗を確認してから実装した。GREEN2d72026で最初の8件が成功。さらにNode標準FormData/Requestの実行結果との正確なバイト比較、同サイズでメタデータが変わる変更、タスク取消後の再利用拒否を加えた。現在ローカルSwift106件（Core101＋AppKit5）が全件成功し、変更のないPythonは従来34件を検証段階とする。開発用アプリの再ビルドとstrictアドホック署名検証も成功した。ソースレビューとテスト実行は別々に行った。

readerはmultipart構造全体を含む長さを事前計算して128MiB以内に制限し、1回最大64KiBで読み取る。本文全体をメモリへ結合しない。上限ちょうどと1バイト超過は架空のスパースファイルで確認し、128MiBの送信・メモリ確保はしていない。5MiBのテストは分割読み取りとバイト数を確認するもので、プロセスメモリ測定やsocket逆圧テストではない。device/inode/size/mtime/ctimeで観測できる置換・内容／サイズ変更を途中読み取り後も検出するが、ファイルシステムのスナップショット保証ではない。不正選択、通常ファイル以外のFIFO、名前によるヘッダー注入、不正boundary、close、タスク取消をテストした。汎用JSONの4MiB制限は維持している。

対象readerのカバレッジは行150/154（97.40%）、領域105/121（86.78%）、関数24/26（92.31%）。分岐・製品全体の割合とはしない。証拠はevidence/chat/upload-a1-verification.jsonとupload-formdata-reference.json。後者はネットワーク送信なしの補助エンコーダであり、実ブラウザやARTEXへの添付成功ではない。認証付きmultipart通信、socket取消・逆圧、実VMと固定ブラウザの128MiB比較、ネイティブ添付状態・選択UIはA2〜A5として残る。引用候補位置・Undoの実画面再確認と機能全体の受け入れも未完了。


## A2 認証付きmultipartと署名アプリによる最初の実転送

現在ローカルSwift124件（Core118、実AppKit5、診断fixture1）が全件成功。Pythonは変更がなく従来34件を検証段階とする。実socket11テストで小さいバッファの部分送信、遅い受信、早期401、EOF前完了、未読要求を残したTCP reset、期限、送信中・応答待ち・worker完了後の取消、不正／途中切れ／曖昧／過大応答、早すぎる成功を確認。認証・client6テストで入力、セッション世代、Keychain削除失敗時の401無効化、VM未起動より前の上限検証、開始前取消を確認。診断fixtureのテストは内容不一致を注入し、所有ファイル・会話・ローカルの後片付けを検証する。RED/GREENと対象カバレッジはevidence/chat/upload-a2-verification.json。製品全体や分岐のカバレッジとはしない。

BackendJSONClientは不変Sendableのmultipart計画をMainActor外で事前検証してから接続する。正の会話IDによるsession添付専用経路だけを扱い、BearerはAuthenticationSession／client内に保持する。Runtimeはロック付き複製descriptorを所有し、取消・停止・異常で中断し、workerのawait後にもVMと転送の有効性を検証する。汎用JSON4MiB、本文待機64KiB、有限応答4MiBの制限は維持する。socketテストやVM未起動の境界テストだけで、実VZの転送中停止を確認済みとはしない。

署名アプリの新規実行upload-a2-v1は、1vCPUソース候補でbootstrap／転送前にpanicした。upload-a2-boot-red.jsonに記録する。終了と後片付けを確認後、同じ条件の新規実行upload-a2-v2は完走した。productionの認証付きvsockで、架空の70,001バイトのバイナリ、空ファイル、28バイトの同名ファイルをアップロード。固定本体は後者をfixture-1.binへ変更した。既存ゲストworkspace APIでダウンロードし、全バイトとSHA256が一致。所有するゲストuploads・会話・選択用ローカルファイルを削除し、一時Keychain削除、認証を保持する停止／再起動、最後のプロセス終了も成功した。証拠はupload-contract-vm.json、upload-native-results.json、upload-native-failed-results.json。

再試行の成功で最初のカーネル障害を取り消したり、実行安定性を合格にしたりしない。今回128MiBの実データは送っていない。実上限転送、メモリ測定、停止／取消の実機統合、固定ブラウザ添付契約、ネイティブ添付状態とUI/UX比較は未完了。引用の実画面再確認と全機能の受け入れも残っている。


## A3 添付APIの正式比較と実128MiB境界

現在ローカルSwift125件（Core118、実AppKit5、診断fixture2）とPython39件が全件成功。REDab3c169では比較用fixture／modeの未実装を確認し、GREEN6471933で新規5テストが成功した。REDf94bb95では任意のネイティブ上限検証を要求し、GREENb84ebd7で診断fixture2テストが成功。全体テスト、開発アプリ再ビルド、strictアドホック署名も成功した。Python比較fixtureはホスト／不正UID／非マークLinuxでHTTP前に拒否し、importだけでは通信しない。本文生成は最大64KiBずつで長さを検証するが、プロセスメモリ測定ではない。

ソース候補カーネルを使った新規署名アプリ／VMのupload-a3-v1は完走した。スパース選択ファイルlimit.binの134,217,517バイトとmultipart構造211バイトにより、本文全体を134,217,728バイトちょうどにした。ARTEXは受理し、workspaceの保存サイズも一致。選択ファイルを1バイト増やすとMac側の事前検証でtooLargeとなり、元のゲストファイルは維持されlimit-1.binは作られなかった。小さい3ファイルも全内容とハッシュが一致し、所有するゲストファイル／会話／選択用ローカル、一時Keychain、VMの後片付け・停止も成功した。

別の固定ブラウザ本体とPostgreSQLをDocker内部ネットワークで動かすと、小ファイルのハッシュ・名前・順序、本文上限、保存サイズ、超過拒否と元ファイル維持の正規化結果が完全一致した。内部loopback APIを使い、入口・公開ポート・ホスト共有はない。使い捨てstate512MiB／tmp256MiBにより実際のmultipart退避を許し、既存入口の64MiB制限と取り違えない。比較用本体は超過本文をHTTP400で拒否し、Macは事前検証で拒否する。検証層が異なるためUI同等性とはしない。比較処理は正常終了し、比較用コンテナ／ネットワークも削除済み。元の8787環境と固定ソースは変更しなかった。

証拠はevidence/chat/upload-limit-contract-vm.json、upload-limit-contract-reference.json、upload-limit-comparison.json、upload-limit-native-results.json、upload-a3-verification.json。共通の正規化項目だけを比較し、診断実装のメタデータを本体互換性に含めない。大きいファイルの全ハッシュ、メモリ・逆圧の測定、実VZの取消／停止、ネイティブ添付状態・UI、引用の実画面再確認は未完了。以前のカーネルpanicは実行安定性の反証として残し、今回の成功で正式採用や機能全体の受け入れを完了とはしない。

## A3大きい添付の全内容

新しい署名付き実行upload-hash-a3-v1でmultipart本文128MiBを送信後、実装した認証付きvsock取得でペイロード134,217,517バイトを全取得した。元の選択ファイルと独立した使い捨て固定バックエンドのSHA256がa8f734b2b3cda26b7ee98640acdf9ee6096eb40c1f720934466e4a9b9f4f2873で一致し、全内容ハッシュを含む8契約群が一致。ゲスト/ローカル所有ファイルと会話、仮Keychainを清掃し、VM停止・アプリ終了を確認。元のDocker4サービスは正常で、比較用コンテナ/ネットワークは清掃済み。添付UIの同等性は証明していない。

Swift145件（Core137、実AppKit5、診断fixture3）/Python42件成功。ダウンロード19件で128MiB逐次ハッシュ、4MiB超の実ソケット、途中切れ/曖昧フレーム、空、期限、早期401、取消、認証世代を確認。独立レビューで要求送信前の成功受理を発見し実行REDa17b157→GREENc81b1f6。+名はRED5cfdd3a→GREEN807912c。ハッシュ不一致でも診断成功となるRED9ecc5c4から、照合必須・失敗清掃をGREENca4f3d9で確認。詳細はbugs/attachment-download-investigation.ja.md。

対象LLVM行カバレッジはパーサ99/99、通信54/60、経路22/22。領域は90/93、44/57、15/16。未通過のソケットエラー処理は残り、分岐/製品全体/プロセスメモリの保証はしない。証拠はupload-hash-verification.json、upload-hash-contract-vm/reference.json、upload-hash-comparison.json、upload-hash-native-results.json。旧A3サイズのみの証拠は保持。実VZ転送中の取消/停止・進捗・A4/A5状態/UI・引用外部再テスト・クラウド/SSE・カーネル安定性・全機能完成条件は引き続き未完了。今回の起動成功で過去のpanicを取り消したり候補を昇格しない。

## 進捗と実VZでの転送中断

6a81f95でSwift157件（Core145、実AppKit5、診断fixture7）/Python42件成功。対象25件で時計制御の最初/間引き/最終通知、不正/逆行値、本文のみの実送信量、socket取消、通知ゲート終了、古いログイン/要求の通知、コールバック内取消、取消を無視した成功の拒否を確認。診断4件は部分転送の失敗と清掃、停止前自然失敗、稼働証拠0、不意の成功を拒否。RED/GREENは0f3ec38/da649bb、e2a9c89/3dab2d4、944592a/9068f9e、レビュー回帰80ed15a/f312d40、原子的証拠d2b7904/6a81f95。詳細はbugs/attachment-download-investigation.ja.md。

署名付き候補VMのupload-cancel-a3-v2は従来の128MiB本文/全内容ハッシュ確認後、新しい大きい転送を2回開始。最初は全134,217,728バイト中17,852,806バイト通知後にTask取消し、CancellationError、保存添付なし、引き続きAPI利用可能を確認。別転送は17,579,466バイト通知後、コントローラ停止が開いていて未取消の所有接続1本を同じロック下で取消。停止前にTask未完了を確認し、CancellationErrorとなった。VM停止/再起動とKeychain認証後、未完成添付がなく、所有会話/ゲストファイル/選択ファイルを清掃。従来LLM/全内容ハッシュ/VMライフサイクル、仮Keychain除去、最終停止/プロセス終了も成功。これは実VZの結果でありfake callbackの根拠ではない。数値にはmultipartフレーミングも含み、送信通知のサンプルであって保存済み量やカーネルI/O実測ではない。

新しい固定使い捨てバックエンドとも8契約群が一致。元のブラウザ4サービスは正常、比較コンテナ/ネットワークは清掃。数値通知/VM停止はネイティブ実行環境の拡張で、ブラウザのスピナー/操作無効化や取消UIの同等性の合格ではない。初回upload-cancel-a3-v1は非合格の予備証拠として保持。全体Swift実行による対象LLVM行/領域は進捗26/26・20/20、認証130/130・105/117、通信171/185・133/171。残るエラー処理、分岐/製品全体のカバレッジを推定しない。

証拠はupload-progress-verification.json、upload-cancellation-vm.json、upload-cancellation-native-results.json、upload-cancellation-contract-vm/reference.json、upload-cancellation-comparison.json、upload-cancellation-preliminary.json。実ダウンロード取消、32MiB退避後の取消、プロセスメモリ実測、A4/A5添付状態/UI、全機能完成条件は未完了。過去の候補panicを保持し昇格しない。次は選択時の会話作成/下書き引継ぎ、添付のみ送信、失敗復元と除去の所有権を移植してからpicker/cardsと実画面比較を進める。

## A4.1添付メタデータと会話別下書き復元

Swift171件（Core159、実AppKit5、診断fixture7）、Python42件、対象chat39件成功。ChatAttachmentはname/path/sizeを検証し任意のabsを捨て、UTF8 DataでUnicodeの別バイト名をcoding/比較/追加/除去/復元まで区別する。カード除去はゲスト削除を呼ばない。service/workspaceは添付のみ送信を許可し、両方なしは通信前に拒否。送信snapshotで一旦クリアし、未確定失敗/stopで復元、新しい編集/添付を維持してreset後の古い応答を拒否。本文改訂で編集後クリアのABAも検出し、accepted後の再取得失敗で送信済みを戻さない。

REDcfb9327は添付API未実装、GREEN5e22964で対象34件。レビューのUnicode衝突を実行RED25c877aの5失敗で再現しGREEN512d9c0で36件。古い本文のバイト不一致とworkspace本文必須条件は31e4daaの5アサーションRED→5ae3434の38件GREEN。固定ブラウザ証拠の欠落RED173676c→GREENe93f575で39件、最終レビュー承認。bugs/chat-attachment-state-investigation.ja.mdを参照。

script/chat_attachment_send_oracle.mjsは固定chat/page.tsx全体SHA2565f53e5667d1ff131585be7bc0ca1f3641cae49d9a98c68fb0375590788abed22を確認後、ChatView.sendを抽出、TypeScriptのエラーcast1箇所だけ除去し限定API/状態スタブで実行。本文+添付失敗、NFC/NFD別名添付のみ失敗、本文+添付成功、空の拒否の4ケースでSwiftの要求JSONと待機/完了状態が一致。再生成一致と不一致ソースの実行前拒否も確認。実ブラウザ操作、ゲスト送信/LLM結果、添付UI全体の根拠ではない。新しい編集/stop/resetは別のSwift回帰で確認。

全体実行による対象LLVM行/領域: モデル23/23・21/21、service110/114・108/115、store249/257・184/213、workspace104/109・91/108。分岐/製品全体の保証はしない。証拠はattachment-send-browser-reference.jsonとattachment-state-core-verification.json。開発.app再ビルド/署名成功、カーネルの既知faultと未完了の安定性ゲートは保持。A4.2認証upload adapter/会話作成/本文引継ぎ/削除/取消、Unicode空白の端点、A4実ゲスト/固定比較、A5 picker/cards実操作比較が必須で、全機能完成ゲートは未完了。

## A4.2型付きupload/会話作成引継ぎと所有処理

Swift190件（Core176・実AppKit5・診断fixture9）、Python45件、所有権/既存chat対象46件成功。feature adapterはJWT/任意経路を受けず、生きた認証、成功status、厳密なメタデータ応答と選択数一致を要求。Workspaceのworker/pumpは起点/解決先ID、処理UUID、世代、最新1件の進捗、親/明示取消、stop/reset、部分削除、本文改訂を守る。新しい行登録で古い一覧を失効。削除成功IDだけキャッシュを消し、遅い送信/停止応答も失効する。取消で受理済みファイルを黙って削除しない。

adapterはRED372ea2b/GREENf1361eeの3件、workspaceはRED2b41865/GREENc3482cbの10件。一覧await後の古い成功をRED2219e94/GREENb0d16e6、対象編集でroot消失をREDc296b78/GREEN7be783cで修正。現在14workspace件とレビューで未解決createの削除、遅いsend、進捗、次処理、選択、古い一覧も確認。実fixture欠落REDb96d724/GREEN3d89cafでnative2件/Python45件成功。比較fixtureはhost/UID/markerをHTTP前に拒否。既存のブラウザ送信ソース実行比較も成功。

新しい署名付きattachment-handoff-a4-v1はsetup/添付前に空判定がsegfaultし、Bad rss-counter state/non-zero pgtables_bytes警告を出した。停止後のホスト全走査で2GiB全ゼロの未変更sparseディスクと確認。nonblank-state-diskはデータ拒否と実行失敗を同じ名前で示すため、走査やformatを迂回せず証拠を保持。同じ構成の対照1回attachment-handoff-a4-v2では実認証typed vsockの作成/本文/添付引継ぎ、3内容ハッシュ、LLM設定前の添付のみ/本文あり503復元、拒否履歴なし、カード除去後のゲスト保持、選択分離、所有データ清掃に成功。Keychain復元/最終停止/プロセス終了も成功。対照成功で今回の異常や過去panic、安定性ゲートを取り消さない。

実fixture名は明示NFD名、other.bin、empty.txt（1/1/0バイト）。Darwin URL分解形変換を別に実測し、実native転送でNFC/NFD別URL名を送れたとは主張しない。別名受信はモデル/store/ソース実行で保持。新しい固定Go比較ではUnicodeメタデータ/内容、添付のみ503、本文あり503、カード除去後保持、拒否履歴なし、清掃の6群が一致。nativeだけの状態フラグは比較から除外しAPIとUIを混同しない。元のブラウザ4サービスは正常、比較容器/ネットワークは清掃。

対象LLVM行/領域: ChatAttachments26/26・23/23、ChatStore273/282・202/232、ChatWorkspace247/257・172/197、LLMService81/87・65/80。分岐/製品全体を推定しない。証拠はattachment-handoff-verification.json、attachment-handoff-vm/reference/comparison/native-results.json、attachment-handoff-boot-red.json、attachment-handoff-failed-native-results.json、attachment-darwin-url-reference.json。picker/cards/外部UX、実プロバイダ成功、Unicode空白端点、退避後/ダウンロード取消、メモリ実測、カーネル安定性と全機能合格は未完了。開発.appを再ビルド/adhoc検証した段階で公証配布版ではない。
