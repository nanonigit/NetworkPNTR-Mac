# F5e3 取得済み通信pickerのsoftwareチェックポイント

証跡画面から認証済みVM client経由の通信pickerを開く。host／method／keywordは250msのcancel可能なbyteベースticketを使用し、変更時だけpage0、同じtask再開は現在pageを保持。25行paging、byte単位の複数ページ選択、ページ選択／消去／件数、既存紐づけ除外を接続。URL／method／status／time、request／response原文は選択可能な文字列で、記録URLを取得・開かない。RFC3339／小数秒は同じ時点で表示し、不明形式は原文へ戻す。

子表示・行／draft binding・query owner・preview IDを別々に固定し、picker中の親更新／export／refreshを止める。現ownerの確認済み追加だけで親metadataを更新し、古い証跡previewを消して閉じる。失敗／dispatch後cancelは共有結果不明gateを保持し、自動再送しない。送信中の通常cancelは無効、親強制終了は未決着を保持。同期公開中の受理済みcloseはqueueし、dispatch前の送信獲得も失効できる。

## 証拠

- 不足契約9dc8489→ae53eb2（10成功）、view不足5505d8b後の14件実行は同じfilterでpage1→0を再現。実行REDcd9c347ではinactive draft復活と子closeのprecondition／process signal5も再現。GREEN4a313ddは関連100件成功。busy前close、時刻、原文／loading／failure／empty／送信中描画を追加しpicker20件。
- coverage付きSwift全824件：823成功、既存外部アクセシビリティ1件skip、失敗0（probe19／app248／core557）。GuestArtifactTests全155件成功。
- LLVMのfile全体行coverage：Picker141/143（98.60%）、Bindings23/23（100%）、View325/394（82.49%）、Workspace333/336（99.11%）、Presentation19/19（100%）、core PickerStore206/208（99.04%）。softwareの範囲付き集計で、全製品・手動操作coverageではない。
- 英日・明暗の画面外構築でhistory／unavailable／安全なerror／原文を確認。loading／preview failure／empty／送信中も余分なrequestなしで構築。NFC／NFD別ID、FEFF／CJK原文、実core store、保留continuationを使用。実captured indexは未投入。
- 固定e75ae371ad777ffd1eecdd28d2781a6519b05591のinventory21navigation／27route／243handlerとlocalization生成・shell構文を確認し、native workflow同等性は未完。依存・キー・guest state・network policyの変更なし。英日RCAはbugs/captured-picker-ui。

script/build_and_run.sh --build-onlyでローカルapp再buildが成功し、process終了後のcodesign --verify --strictも成功。ローカルbuild／署名確認で、install／公証／起動／実guest接続UIの受入ではない。

## 残る受入条件

実managed guest／固定比較側の非空captured indexでfilter／paging／選択／原文／追加／編集／削除／順序、version競合／結果不明回復、再起動後の永続化を検証する。詳細previewのbyte offset／binary／切詰め／原本も比較。過去の原本transport／native／比較証拠を、新UIの実行証拠とはしない。mouse／keyboard／VoiceOver／save panel／複数window／画面比較は、後で行う手動解除を待つ未完条件。画面外試験で代替しない。

元の21workflow、source kernel信頼性／標準採用、新規install／署名／公証／release、4社、調査ハーネスを維持し、全目標は継続。Actions枠枯渇でCI未検証のまま、公開HEADに[skip ci]を付け、dispatch／再実行／課金変更は行わない。
