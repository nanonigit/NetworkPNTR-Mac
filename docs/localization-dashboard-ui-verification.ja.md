# Dashboard UIの日英対応 — L7

## 再現と証拠収集

L4cのエラー移行後も、Dashboardの4ファイルに日本語見出し／説明と生のtask／engine／severity表示が残っていました。ソースから不足を確認した段階で、新規の実画面再現とはしません。対応表103項目はUI／活動の88項目と、固定browserのstatus.task／engine／severityから投影した15項目。独立したstatus fixtureに`e75ae371ad777ffd1eecdd28d2781a6519b05591`と元JSONハッシュを記録し、参照HEADも再確認しました。

`9a2e383`はDashboardLabelDomain／Labels・キー未実装の意図したコンパイルRED、`a41c2fa`で同じ3試験成功。日英全文／placeholder一致、固定status全項目、未知／独自内容保持、tool名優先、両集計元の表示前後の集計不変、テンプレート風文字を含むタスク説明の保持を試験しました。

## 分析

5 Whys：Dashboardが混在／raw表示→view文言とstatusがカタログを通らない→集計／chart初期移植が言語対応に先行→識別子と表示が結合→全panelを覆う表示境界がなかった。Fishbone：旧集計／台帳の定義・status出所・任意内容・chart系列／scaleキー・選択／日付ID・埋込値・前回日時のlocale・不変な集計／query。Timeline：ソース／固定status／Lazyweb→要件／設計／計画→意図したRED→カタログ／helper／view GREEN→レビュー／全試験／coverage→署名リソース。Lazyweb検索`usage analytics dashboard`はGoogle Analyticsメタデータ（.631）で、画像未閲覧のため実画面一致の証拠ではありません。

## 修正

見出し・集計・選択・空／読込／前回状態・期間・chart軸／系列／凡例／読み上げ・活動／task／finding／asset／traffic／systemを現在の日英localeで表示。chart markと凡例scaleは同じ翻訳キーを使い、blue／green／purpleを保持します。前回取得日時の書式には選択localeを明示し、保存日時自体は変えません。埋込値には既存の一度だけの展開処理を使用します。

DashboardLabelsは既知のtask／engine／severity識別子完全一致だけを固定翻訳へ変換し、未知値はtrim／大文字小文字変換せず保持。活動5コードはnative表示名を日英化し、browserのraw活動識別子表示とは意図した言語対応差分です。tool_useでは指定されたtool名を優先する仕様を維持。worker・独自説明・モデル／profile名・asset種別名・summary・URL・未知値はそのままで、色／filter判定はraw識別子を使います。

Core DashboardMetrics／Models／Service／Storeは移行前とbyte完全一致。Picker tagとchart scaleの色順も一致し、4viewのCJKソース行は0です。ただしソース上の不変条件であり、実データにCJKがない／描画後のchart状態を保持する証拠ではありません。localeのview再作成／task・poll／query／遷移・データ移行は追加していません。

## 検証と残ゲート

Swift264件（成功263・既存AX1件スキップ）、Python52件成功。表示helperの行coverage100%。読み取り専用レビューで文言・未知／tool保持・chart scaleキー／色・選択／遷移を確認。最終署名ビルド・厳格署名・exporter成功、両言語各103項目と埋込16種類のキー一致を確認。証拠は`evidence/localization/dashboard-ui-*`です。

実際の凡例／色・選択／hover日付・profile／source／期間／展開／scroll保持・前回／再試行／空画面・遷移・VoiceOver／IMEはMac解除後のnative/browser比較が必要です。新規runtime fixture・画像・クラウド呼出し・UI試行はありません。runtime／backend言語／初期会話名の出所・未実装18画面・全21機能／runtime／配布の受け入れも未完了で、全体目標は継続中です。
