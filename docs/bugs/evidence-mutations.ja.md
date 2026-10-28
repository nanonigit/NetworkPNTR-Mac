# 証跡更新の統合：時刻と共有storeの所有権

## 1. 再現

時刻REDf72bcabはepoch0／1／-1／1792663200で3assertion失敗。nativeが秒を1000で割っていた。固定traffic.goはnow.Unix()、ブラウザの1000倍はJavaScript Dateがミリ秒のため。GREENbda51bdはworkspace23件成功。

更新不足契約REDb9dd4f6→4eade81（31件）、画面／表示version／cancel不足契約RED5f5542c→6b8d4fb（関連75件）。不足APIのcompile REDを実行時障害とはしない。その後の実行REDa81c4d0はaction14件で9assertion失敗：sheet Aの再stopがBの共有storeを消し、resetと新session更新後のAの遅延cleanupが新ownerを停止して結果不明にしてしまった。

## 2. 証拠

同じ共有storeと保留write continuationで、異なる2session／writeを試験。active／owner／read／unknownと終了結果を確認し、コマンド構築だけで済ませない。時刻は合成画面の見た目でなく、epoch数値と固定sourceで照合。初回実装試験ではfixture不備も修正：継承recordのsource_task_id欠落、Foundation JSONSerializationによるnote先頭BOM消費。fixtureをrecord契約へ合わせ、noteのbyte照合はBackendJSONCodingを使用した。製品の原文を正規化したわけではない。

## 3. 原因分析

5 Whys：時刻誤表示／ミリ秒換算の流用／JavaScriptとFoundation Date単位の混同／fixtureもミリ秒／数値・sourceとの契約試験不足。根本原因は表示境界の時刻単位が不明確だったこと。

終了処理は、保持storeへ無条件に作用／storeが画面より長く生存／stopにowner能力がない／遅延cleanupが現storeと仮定／通常の閉じ直しだけを試験し、遅延消失・session置換を未試験。根本原因は寿命変更時に破棄の所有権をcommandと同じモデルへ結び付けなかったこと。

Fishbone：単位・fixture、共有寿命、遅延continuation、session reset、破棄owner不足。Timeline：f72bcab/bda51bd→b9dd4f6/4eade81→5f5542c/6b8d4fb→a81c4d0/26c540b（関連77成功）。

## 4. 修正

秒を直接使いDTO単位を明記。windowがevidence store／未決着write／回復target・contextを保持し、logoutだけでsession resetする。workspaceはstore ownerを捕捉。owner限定stopは自身の新tokenを返し、遅いscrubもその停止ownerにだけ作用する。新selection／sessionへは作用しない。画面／dialogはworkspace／store／version／membershipを確認。note原文と未知roleを保持し、role明示選択・再送拒否・確認済みreceipt後だけの親metadata更新を維持。

## 5. 検証と再発防止

epoch、古い表示version／membership、dispatch前後の終了／cancel、保留応答、sheet／session置換、note byte、継承、結果不明の明示解除、親metadataを回帰試験に保持。action14件＋workspace23件と既存finding／coreで関連77件。全体試験／buildは英日のfindings-traffic-mutations-verificationを参照。実非空データのguest／比較側更新・永続化、captured picker、解除後の画面／accessibilityは未完で、製品全体受入ではない。
