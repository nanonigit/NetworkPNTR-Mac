# 認証／設定／ダッシュボードのエラー移行 — L4c

## 1. 再現／2. 証拠収集

現在のソースではAuthenticationSession／LLMStore／DashboardLoadStateが表示済み日本語エラーを保持し、L4bの対応はChatのみでした。LLM完了通知も表示済み文字列です。明示言語の表示境界が不足するソース証拠で、新規実画面再現とは扱いません。

`a229ee3`は型付きエラー／通知値の意図したコンパイルRED、`7b6c8c5`は4件のstore／service試験GREEN。途中のLLMSettingsViewで型の異なる値を結合するコンパイルエラーをコンパイラー／レビューで発見し、GREEN前に`(localError ?? store.failure)?.text(language: language)`へ修正。上流製品の不具合や追加の製品REDとは数えません。`4cbb734`で回帰3件を追加し、対象7件成功。実サービスとスクリプト応答transport／メモリ内vaultを使い、実認証情報やクラウド呼出しはありません。

## 3. 分析

5 Whys：エラー／通知が日本語のまま→表示済みStringを保持→catchですぐ文字列化→そこにview localeがない→安全な識別を保持する共通境界がなかった。Fishbone：認証／vaultの順序・変更確定と再取得の区別・前回データ／日時・poll／キャンセル・シート内状態・生backend文言・カタログ同梱。Timeline：現状／要件／設計／計画→Lazyweb隣接メタデータ→意図したRED→型付き保持／view表示→コンパイル修正／GREEN→レビュー→全試験→coverageから操作／poll回帰を追加→最終全試験／署名リソース。

## 4. 修正

AuthenticationSession／LLMStoreは安全なAppErrorMessageを保持し、日本語Stringは計算プロパティで互換。DashboardLoadStateは前回値／日時を保って型付き失敗を保持。認証・LLM設定／編集／rotation・dashboardは現在localeでエラーを表示し、編集／規約読込のローカルエラーも型付きにしました。確定したLLM通知6種類はカタログキーを保持し、変更成功後の再取得だけが失敗しても成功通知を失いません。未知エラーの詳細は直ちに捨て、既知エラーの数値情報だけを安全に保持します。

task同一性・認証／vault順序・パスワード／APIキー保存・入力binding・規約同意・poll間隔・キャンセル／世代の仕様は変更していません。既存backendのpool診断やモデル返答はそのままで、出所を確認する別監査が必要です。Lazyweb検索`settings inline validation error`は隣接Gopuff captchaメタデータのみ（.356）で、画像を閲覧した／UI一致の証拠とはしていません。固定ブラウザの配置／エラー位置を参照にします。

## 5. 検証と再発防止

最終件数とCoreファイルcoverageは`evidence/localization/screen-error-verification.json`／`screen-error-coverage.json`に記録。認証検証／phase／副作用なし・未知エラー秘密除去・保存成功後の再取得失敗・LLM完了通知全6種類・失敗時の偽成功なし・dashboard前回値／日時・poll3群のエラー・言語取得による通信追加なし・キャンセル終了を試験。既存回帰で認証／添付／セッション／古い世代応答も検証。最終署名のエラー／通知文言は単一カタログと照合し、差分検査・厳格署名検証も成功しました。

実native／browser切替・周辺画面ラベル・英語規約と読了条件・実IME／VoiceOver・runtimeエラー・backend言語同期／初期会話名の出所・未実装18画面・全21機能の受け入れは未完了です。前ターンでユーザーがMac解除を延期したため、今回は新規UI操作の試行やruntime fixture起動を行っていません。解除後の実比較は必要で、全体目標は継続中です。
