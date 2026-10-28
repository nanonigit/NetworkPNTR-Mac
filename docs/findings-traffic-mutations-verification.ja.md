# F5e2 証跡の編集・削除・並替えと回復

native一覧にrole／note編集、確認付き紐づけ削除、隣接上下の並替えを接続。開始時のversion／membershipとdialog／draft UUIDで操作を固定する。未知roleは既知roleの明示選択が必要。noteのFEFF／NFD／CJK byteを保持し、継承は更新不可。確認済み更新後は親finding／report metadataを再取得。競合・dispatch後のcancel・所有権喪失は結果不明とし、refreshだけで解除／再送しない。

認証済みwindowがevidence storeと回復target／contextを保持し、sheetを閉じても未決着／結果不明を維持。通常finding更新とbusy／unknown gateを共有し、filter変更後も親の回復操作から該当findingを開く。新しいsummaryと明示確認後だけ更新再開。古いsheetの遅延消失・旧session更新cleanupは新ownerを停止できない。終了で表示原文を消し、logoutでsession resetする。

時刻は固定traffic.go／browserと同じUnix秒に修正。数値epoch試験は修正前に3assertion失敗し、ミリ秒fixtureも修正した。source契約の同等性で、画面・locale表示の受入ではない。

## 検証

- action不足契約b9dd4f6→4eade81（31件）、画面／表示version／cancel不足契約5f5542c→6b8d4fb（関連75件）。共有ownerの実行REDa81c4d0はaction14件中2case・9assertion失敗→26c540b（関連77成功）。時刻REDf72bcab→bda51bd（workspace23成功）。英日RCAはbugs/evidence-mutations。
- coverage付きSwift全804件：803成功、既存外部アクセシビリティ1件skip、失敗0（probe19／app228／core557）。GuestArtifactTests全155成功。
- LLVMのfile全体行coverage：Actions121/134（90.30%）、ActionBindings24/24（100%）、ActionView84/103（81.55%）、Workspace302/305（99.02%）、Presentation13/13（100%）、ScreenModel206/215（95.81%）、TrafficStore173/175（98.86%）。範囲付き数値で、全製品／実画面coverageではない。
- 英日dialogの画面外描画、既存list／viewerの明暗回帰を確認。固定fake HTTPと保留continuationでrequest欄・version／順序・cancel・古いidentity・結果不明・metadata read所有権を試験。実capturedデータのbackend更新効果・永続化の証明ではない。
- localization生成、shell構文、固定inventoryのnavigation21／page27／handler243を確認。native workflow同等性は未完。依存追加なし、外部SwiftPM package依存なし。

script/build_and_run.sh --build-onlyでローカルbundleを再buildし、process終了後のcodesign --verify --strictも成功。インストール／公証／起動／実guest接続UIの受入ではない。

## 残る受入

captured trafficを選んで追加するpicker UIは未実装で、既存typed state／契約は前提部分。managed guestと固定比較側の非空通信で編集／削除／順序／追加、競合／結果不明、再起動後の永続化を実測する。詳細preview／byte offset／binary／切詰め／原本downloadも比較。実save panel、keyboard／VoiceOver、複数window、native／browser画面は、後で行う手動解除を待つ未確認項目。21workflow、隔離VM、kernel信頼性／標準採用、新規インストール／署名／公証／release、4社、調査ハーネス目標を維持。

Actions枠枯渇中はCI未検証。公開HEADに[skip ci]を付け、dispatch／再実行／課金／network policy変更は行っていない。ローカルbundle build／署名結果は公開時に記録し、これや画面外試験でインストール済み・製品完了とはしない。
