# 標準メニューの表示境界 — L9（部分的な接続）

## 再現と証拠収集

RootのSwiftUI localeだけでは既存AppKitメニューの表示名を扱えず、アプリはNew Item群を除去するだけでした。AppKit interopスキルの狭い接続に従い、言語設定はSwiftUIが所有。ローカルSDKでNSMenu.didBeginTrackingNotificationとNSApplicationのwindow／help／services登録menuを確認しました。Lazyweb検索`desktop application menu bar`はCluelyダウンロード画面の隣接メタデータ（.340）で、画像未閲覧のためmenu証拠ではありません。

`8d65447`はmenuキー／adapter未実装の意図したコンパイルRED、`bab27b4`で最初の5試験成功（合成AppKit4＋catalog1）。最初のGREEN実行では、attributedTitle設定でAppKit自体がtitleを変えることを試験が考慮していなかったため、apply前の実値を保持して比較するよう訂正し、製品不具合とは数えません。`b97a197`で全操作／見出しを追加し、Close Window表示だけのRED1失敗を実行。`b757992`は閉じる別表記3件だけを足し、対象7件成功しました。

## 分析

5 Whys：menuが追従しない→既存AppKit値がview環境外→言語に応じるtitle adapterがない→command再作成はresponder／shortcutへ影響→既知識別／aliasのtitle専用境界が必要。Fishbone：native action識別・静的／動的文言・登録submenu同一性・未知／独自／装飾内容・observer寿命・SwiftUI menu差し替え・native validation順序。Timeline：ソース／SDK／skill／Lazyweb→要件／設計／計画→意図したRED→adapter／resource／AppDelegate接続→試験訂正／GREEN5→全22操作／見出し／Close別表記RED1→最小alias修正／GREEN7→レビュー／全試験／coverage／署名リソース。

## 修正と不変条件

既知native selectorと静的タイトルの組だけを、同じ項目のまま変更。root見出しは既知名＋native操作が必要で、登録window／help／servicesはオブジェクト同一性を使用。menu／項目／target／action／key／modifier／有効状態／state／identifier／representedObject／tooltipは維持。未知selector／独自名・装飾／custom view・動的window／service名はそのままです。alias表内の中国語／韓国語は識別入力であり、出力対応言語や一括翻訳ではありません。

selector方式のtracking observerを1つだけ登録し、毎回現在mainMenuを取得。言語変更時に適用し、start反復でobserverを増やさず、stopで明示解除します。AppDelegateが所有し、共通設定からappearance／change・launch後refresh・終了時stopへ接続。menuの再構築／command実行・timer・OS全体言語変更・新規保存・VM要求・view同一性変更はありません。applicationShouldTerminateはbyte一致で、言語preferences・RootView・runtime2ファイルもこの段階では変更していません。

## 検証と限界

Swift275件（成功274・既存AX1件スキップ）、Python52件成功。AppMenuLocalizer／bridgeファイルは行100%・領域96%。SwiftPM最後のJSONはCore側のみだったため、Mac試験実行ファイルから別途coverageを取得しました。metadata／observer所有者・対応22selector／見出しguardをレビュー済み。最終署名ビルド・厳格署名・exporter成功、両言語28項目とアプリ名の任意文字保持を検証。証拠は`evidence/localization/menu-*`です。

試験は画面に出さない合成NSMenuで、ユーザーのアプリを調査／操作したものではありません。解除延期中の新規runtime／VM fixture・実native操作・画像・クラウド呼出しはなし。初回表示／tracking順・SwiftUI固有selector・responder validation・shortcut／undo／copy／quit実行・framework差替後の適用は未確認。操作名付きUndo・Exit Full Screen・状態付きShow／Hideは静的alias対象外で保持するため、OS文言に他言語が残り得ます。OS標準menu全体の言語対応は未完了で、証拠に基づく拡張と解除後検証が必要です。backend／出所・未実装18画面・全21機能／runtime／配布／言語全体の受け入れも未完了です。
