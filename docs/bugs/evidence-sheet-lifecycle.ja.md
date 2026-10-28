# 証跡sheetの寿命・所有権の回帰

## 1. 再現

a4b28faの不足契約REDから666bb50の9件成功、7e45408の画面／presenter不足契約REDから6029c49の11件成功へ進んだ。この最初のREDはcompile時の契約不足で、実行時障害ではない。

追加負例で実障害を再現：sheet Aの古いdismissが新しいBを閉じる、空本文の検証済みreceiptで3バイトのresponse保存が成功してしまう、busy通知中に終了してもchooserが開く、stop通知がcleanupへ再入する。12件実行は古いdismissで2assertion失敗、17件はdismissとreceiptで6失敗。5989dd7の20件REDは再入／chooserの失敗後、プレビュー公開時の終了でsignal11となった。9628164の親画面公開REDもsignal11。f0f71a9の22件REDはTask作成前のcancelと古いbinding getterの2assertion失敗。

## 2. 証拠

固定JSONと実際の排他的な一時ファイルを使用し、キーや記録URLにはアクセスしない。保留continuationでread／receiptを遅延し、同期Observation callbackでwillSet中の終了を試験する。可能な再入counterは上限を設けた。signal11は試験processの失敗で、受入成功にはしない。ローカルログは非公開で、ユーザー文書はfixtureに使っていない。

## 3. 原因分析

5 Whys：保存したidentityでなく現在値を使用／観測propertyの書込完了前に終了が可能／同じpropertyをcleanupで再更新しtransition境界が不足／Task参照の存在だけでcancel判定／通常の非同期終了までしか負例がなかった。根本原因は入口のowner検証だけで同期公開・Task獲得まで安全とみなしたこと。別のintegrity不足として、UIの固定manifestと返却receiptを照合していなかった。

Fishbone：表示identity、willSet順序、親子寿命、Task獲得／cancel、receipt同一性、同期負例不足。Timeline：a4b28fa/666bb50→7e45408/6029c49→5989dd7/59063fc（20成功）→9628164/5ba58f6（関連50成功）→f0f71a9/98aa36e（関連51成功）。

## 4. 修正

bindingのgetter／setter両方を表示時UUIDへ固定。同期公開中の終了を保留し、公開単位の完了後にcleanupする。transition中の新規操作とstop／cancel再入を拒否。chooser前・保存先選択後・staging後・commit直前に所有権を検証し、Task作成前のcancelも記録する。receiptのstatus／size／SHA-256を固定manifestへ照合。親画面は公開後のlifecycleを確認し、willSetで復元されたworkspaceを失効する。親のclose／stop／resetにも再入guardを設ける。panelは実sheetのwindowに付け、detach時にcancelする。

## 5. 検証・再発防止

workspace22件と既存finding回帰を保持（関連51件）。保留read、表示文字数と別のbyte offset、FEFF／NFD／CJK原文、binary、継承／legacy、古いowner、実保存、既存file保持、別receipt、遅延cleanup、安全なエラー、busy中cancel、親子再入を試験する。英日・明暗の画面外描画はsoftware証拠のみ。全体／build／公開結果と実UI・preview API・picker／更新／永続化・releaseの残条件はfindings-traffic-ui-verification.ja.mdを参照。
