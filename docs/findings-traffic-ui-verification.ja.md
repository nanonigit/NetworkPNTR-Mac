# F5e1 native証跡の閲覧・保存チェックポイント

16e97f7時点の閲覧・保存チェックポイント。現在の編集／削除／並替え／回復はfindings-traffic-mutations-verification.ja.mdを参照。

finding詳細から、そのwindowが所有する証跡sheetを開けるようにした。一覧のrole／note／ID／method／status／URL／capture時刻、継承データの読み取り専用表示、原文とheader、request／response切替、明示した追加byteページの累積表示、binary案内、認証済みVM経由の原本全体保存を接続した。記録URLは文字列のまま。NSSavePanelは実sheetへ付け、global key-window参照やホスト共有・ホストでのagent実行は追加していない。既存fileを保持し、選択manifestと一致する検証済みstagingだけをcommitする。cancel、遅いreceipt、親終了、古いcallbackを防御した。

全F5設計のうち閲覧／保存部分の実装段階。画面は追加・編集・並替えを開発中と示し、削除・captured pickerも未完。F5全体、21workflow同等性、クラウド4社、kernel昇格、新規インストール、公証、releaseの完了ではない。

## 証拠

- TDD：a4b28fa不足契約→666bb50の9件、7e45408画面／presenter不足→6029c49の11件。実行RED5989dd7で古いidentity、異なるreceipt、同期終了再入を再現しprocessがsignal11で失敗→59063fcの20件成功。親RED9628164もsignal11→5ba58f6の関連50件成功。cancel／getterのREDf0f71a9は22件中2失敗→98aa36eの関連51件成功。英日のbugs/evidence-sheet-lifecycleを参照。
- coverage付きSwift全789件：788成功、既存の外部アクセシビリティ1件skip、失敗0。内訳はprobe19／app213／core557。
- GuestArtifactTests全155件成功。localization生成確認、shell構文、固定inventoryのnavigation21／route27／handler243も確認。native workflow同等性は未完のまま。
- LLVM行coverage：FindingTrafficWorkspace280/282（99.29%）、FindingScreenModel179/188（95.21%）、FindingBindings51/52（98.08%）、FindingTrafficView189/253（74.70%）、EvidenceSavePanel27/81（33.33%）。file全体の範囲付き集計で、全変更行や未試験panel操作の証明ではない。chooser／window実操作は手動受入待ち。画面外描画はkeyboard／accessibility受入ではない。
- 新規workspace22件は固定JSON、保留continuation、同期Observation callback、排他的な実一時fileを使い、全byte／hash、既存file保持、別receipt拒否、遅延receiptの残骸なし破棄を確認。agentやmodel APIは実行しない。
- 前チェックポイントのnative／固定比較原本一致はevidence/findings/evidence-reference-comparison.jsonに保持（2起動で8file、135266321バイトを含む）。以前のtransport／診断binaryの証拠で、新UIを実ゲストへ接続した受入実行ではない。

script/build_and_run.sh --build-onlyでbundleを再buildし、strict署名確認を行った。最後のweak capture名整理後も関連51件を再確認し、transportの意味変更はない。ローカルbundleのbuildで、インストール／公証／実UI受入ではない。

## 残る受入条件

新sheet／保存panelを実managed guestへ接続し、詳細preview本文・binary／切詰め・原本を固定ブラウザと比較する。ユーザーはMac解除を後で行う方針のため、panelのmouse／keyboard／VoiceOver、見切れ、sheet／window／複数window、画面比較は未確認。captured picker、role／note／削除／並替えを実装し、非空データの実更新・競合／結果不明・永続化をguest／比較側で検証する。全app／VM／クラウド／release要件を維持。Actions枠枯渇中はCI未検証とし、公開HEADに[skip ci]を付け、dispatch／再実行／課金変更はしない。
