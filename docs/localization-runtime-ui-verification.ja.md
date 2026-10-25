# 実行環境と比較状況の表示 — L8

## 再現と証拠収集

RuntimeViewの日本語操作／生のlifecycleコード、sidebarの生コード、表示済みraw診断String、比較表の日本語見出し／状態／metadataをソースから確認しました。ユーザーが解除を延期しているため、新規の実画面再現は主張しません。

`346f7b4`はruntimeキー／表示／安全な失敗値の未実装を確認する意図したコンパイルRED、`a4e9c7b`で同じ4試験成功。34項目の日英表・6状態／安全なエラー4種類・起動前の不正な専用data root・machine作成前のartifact欠落を確認。読み取り専用のVirtualization能力フラグだけで分岐し、新規VM／guest disk／ログは作りません。通常の所有ファイルを不正rootのfixtureとして作り、終了後に削除。比較表の21機能／27画面／243endpointも検証しました。

## 分析

5 Whys：実行環境表示が切り替わらない→literal／rawコード／文字列化済みerror→理由の識別を捨てた→診断と表示が結合→初期の言語対応は機能画面を先行した。Fishbone：lifecycle所有者・runtime世代・起動／fail境界・任意path／stageの安全性・guest診断・比較status／件数の正確性・標準AppKitメニュー。Timeline：ソース／Lazyweb／要件／設計／計画→意図したRED→表示／並行する安全なエラー値→GREEN→レビュー／全試験／ソース監査→署名リソース。Lazyweb検索`virtual machine status settings`はHeight隣接メタデータ（.383）で画像証拠ではありません。アプリ管理runtimeにはbrowser同等画面がなく、実nativeで別に検証が必要です。

## 修正

操作・準備完了・lifecycle6名称・sidebar・比較表を現在の日英リソースで表示。比較機能名は共通mapping、browserパス／機能IDはraw保持、nativeStatus分岐は従来通りで、件数は実catalogから取得します。説明に部分移植済みのChatも含め、合格ゲートを完了扱いにはしていません。

VMController／DesktopRuntimeは従来のlastError／error診断に並行して安全なAppErrorMessageを保持し、同じguard境界で設定／消去。RuntimeErrorは種類キーだけをUI値へ残し、任意stage／path／詳細を保持・埋め込みしません。未知frameworkエラーはruntime用の一般文言。RuntimeViewは現在localeで解決します。従来のraw error description／ゲストログは診断として保持し、自動翻訳や他言語なしとは主張しません。

追加したfield／reset／assignmentだけを取り除くと両runtimeファイルが元ソースとbyte一致することを確認。lifecycle／configuration／artifact／disk／provisioning／feature-mapは不変。VM権限／network／管理protocol／状態遷移／poll／認証／diskパスは変更していません。これはソース不変の証拠で、新規実guestの受け入れ試験とは別です。

## 検証と残ゲート

Swift268件（成功267・既存AX1件スキップ）、Python52件成功。RuntimeLabels／AppErrorText／AppErrorMessageはそれぞれ行coverage100%。読み取り専用レビューでguard付きエラー対と安全な表示を確認。最終署名ビルド・厳格署名・exporter成功、同梱は両言語34文言一致、埋込3種類もキー一致。証拠は`evidence/localization/runtime-ui-*`です。

新規native／menu試行・runtime fixture・VM起動・画像・クラウド呼出しはありません。実起動／停止／失敗／復旧表示、言語変更時のnative／表／sidebar保持、診断の見え方、VoiceOver／IMEは未完了。OS標準メニューはSwiftUI locale以外のAppKit接続が必要で、今回未対応。Rootカタログ読込のfallbackとbackend／出所文言も最終監査が必要です。全21機能・未実装18画面・runtime安定性／network・配布・言語全体の合格は未完了で、全体目標を維持します。
