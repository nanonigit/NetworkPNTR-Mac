# Findingsの専用VM・固定backend比較チェックポイント

基本Findings API/状態の実測記録です。実画面・Findings全体・全21機能の受入ではありません。固定browser/backendはe75ae371ad777ffd1eecdd28d2781a6519b05591、native実装73ac82a、修正版の独立reference20b915bです。evidence/findings/f4b-api-comparison.jsonを参照してください。

## nativeの実行

署名したVMProbeを、Docker停止中に実行しました。新しい2GiBディスク1つと、既定へ昇格していないcpu1 source-profileで3起動。1回目は初回認証・未認証401・空schemaのSQL監査・固定データ投入・投入後監査。2回目はタスク読込後の100読取・14更新関連要求・変更後の集計2要求。3回目はloginの代替なしに同じBearerで100読取し、削除行/nodeも確認しました。全3回で準備完了・協調停止・転送中断0・停止後全ログ/資格情報/隔離監査に合格。formatは初回だけ、診断異常は0です。ディスク・ログ・実行した署名バイナリは非公開で保持し、安全な実測結果と入力hashをf4b-native-vm.json、f4b-native-source-inputs.json、f4b-native-host-inputs.jsonへ保存しています。

初期33件で一覧20/グループ10のページ・範囲外ページ・重要度/時刻ソート・重要度4種/状態9種/分類3種/タスク12選択・資産5範囲・Unicode/NFC/エスケープ/複合検索を検証。全詳細のUTF8・資産順・由来・時刻を照合します。グループ/統計/資産階層の件数・順序・祖先での重複除去、nodeとstandalone IDの区別、8111が8101を継承する構造、変更handleを持たない旧形式を確認。所有/継承の詳細は読め、無関係の文脈は404です。

通常の編集では名前/分類/重要度を1つのPATCHで変更し、状態は別要求です。risk_acceptedとNUL入り名前の複合要求は実際に500となり、状態だけ保存され名前は元の編集値のままと確認しました。nativeのキャッシュは保守的に残り、読取だけで結果不明を解除せず、該当回の明示確認まで更新を拒否。その後に意図したfixed更新を行います。9102と孤立9133の削除で選択/詳細/キャッシュと404を確認。再起動後は31行・旧形式込み31finding node・8101所有20node・8111計22node（継承20）でした。模擬通信ではなく実APIでの照合です。

## 独立reference

キャッシュ済み入力から作る空のLinux/arm64コンテナをUID1000・root読取専用・network-none・cap-drop-ALL・権限昇格不可で実行。stateはtmpfs、hostのbind/volume共有とport公開は0です。backendの0ebad83d...バイナリ・seed/audit hash・ソースcommitをnativeと一致させました。PythonはSwift出力や集計JSONを使わずSQLデータから独立計算します。backend3起動で認証/データを保持し、再起動前116要求・後100要求を照合。SQL監査7記録では終端タスク/exploration各11・関係/会社各1・資産3・最終finding31/node31でした。監査対象の外部データ/実行履歴/profile/usage/conversation/retest/traffic/channel/deliveryは全て0、内部の9101状態イベントは実測3です。タスク/資産の外部linkは拒否しますが、この監査で33link全件の存在を再証明したとはしません。

比較器はVMの全起動/停止ログ、両者のライフサイクル、ソース/バイナリ/データhashと共通検査の一致を必須にします。共通は編集・別状態変更・部分500/読戻し・最終状態・2削除。native独自のキャッシュ/選択/結果不明の5検査をbrowser UIの同等性とは区別し、実画面受入はfalseのままです。2つのpassedフラグを比べただけではありません。

DBdumpとログを非公開で保存後、所有referenceコンテナ・派生タグ・入力別名2つを削除。元のimageタグ/IDと既存5コンテナのIDは保持しました。安全なreference/host掃除/比較記録を保存しています。初回referenceはbackend起動前にsysfs名の検査で停止しており、f4b-reference-network-red.jsonと日英bug記録を保持。別の最小再現で停止中の仮想トンネルと非機器項目を確認し、既存の機器/UPリンク/外部経路の検査で3値の0を要求しました。危険な観測は引き続き拒否し、ネットワーク方針は緩めていません。

## 検証と未完了条件

ローカルSwift全616件（615成功・既存外部AX1件明示保留）、Python全120成功。Core対象33件とguest adapter4件にはRED/GREEN・不正/外部入力・結果不明・キャンセル・再実行拒否・起動/停止失敗を含みます。LLVM行カバレッジは全体exercise/更新/本文検証100%、集計97.96%、読取97.85%、通信97.83%、データ94.94%、guest adapter96.05%。Pythonの単体+実referenceは監査100%、独立reference98.04%、比較器93.90%。ソースと実測記録を確認しましたが、最後の小さなnetwork再利用修正は補助レビューagentの利用制限により手元の確認/試験です。公開時には署名付きbuild・厳密署名・修正HEADのCIも必要です。

F4b計画には、名前/分類/重要度を個別PATCHで確認するケースと追加の境界/正規化試験が残ります。今回の通常編集は3項目をまとめています。実画面・キーボード・VoiceOverは手動ロック解除後です。F5のexport/traffic/lineage/retest/deepen/高度なreport、全21機能、nativeのcloud通信、以前の断続的kernel障害、既定artifact昇格、別Macでの導入/配布も未完了です。1回の3起動成功で信頼性確立や昇格とはしません。
