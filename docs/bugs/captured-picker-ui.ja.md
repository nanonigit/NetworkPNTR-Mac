# 通信picker画面の回帰

## 1. 再現

不足契約RED9dc8489→ae53eb2のstate10件成功、native view不足RED5505d8b→画面実装。最初の実行14件は、同じfilter task再開でpage1が0へ戻り1assertion失敗。同期observer試験を追加したcd9c347では、子の直接stop後にhost draftが復活し、子closeが公開境界のpreconditionに達してprocessがsignal5で失敗した。compile契約不足と、実行時失敗を区別する。

## 2. 証拠

固定の非network fixture、実core store、byteの異なるUnicode ID、保留read／write、同期Observationを使用。pageは適用cursor、draftはbindingが隠した値だけでなくinactive model内部を確認。closeは入力公開中に捕捉した表示IDで実行。crashしたprocessを受入成功とせず、raw logは非公開。実通信・キー・server stateはGitへ入れない。

## 3. 原因分析

5 Whys：毎回page0を生成／task再開とfilter変更を同一視／query ownerとdraftを分離した際に不変queryを保持していない／変更時resetだけを初期試験。根本原因は再開と新filterの混同。

close／draftは、同期入力通知中の終了／子closeが親の非多重transitionへ再入／直接stopの消去後に外側setterがcommit／公開終了前にcleanup完了と仮定／親終了だけを試験。根本原因は子にも、受理した終了意図のqueueと公開後cleanup境界が必要だったこと。

Fishbone：query再開と編集、同期通知、親子transition、draft寿命、busy前cancel、負例不足。Timeline：9dc8489/ae53eb2→5505d8b→cd9c347（page／draft／crash）→4a313dd（関連100成功）→busy前close・時刻・preview／loading／送信中描画の追加試験。

## 4. 修正

現queryから始め、byteベースのdraft変更時だけpage0へ戻す。cancel／古いticketは無効。捕捉picker UUIDでcloseをqueueし、親終了を優先。busy公開前に受理したcloseはdispatch前の送信獲得も失効する。公開後に終了した子自身のdraftを消去し、再stopはguard付きで、別pickerの共有evidence storeへ作用しない。既存のowner限定終了と結果不明保持を再利用。

## 5. 検証と再発防止

picker20件で選択／filter／page／原文／追加／結果不明／owner／再入、英日・明暗、空履歴／unavailable／loading／安全なerror／送信中を確認。page／draft／closeの正確な負例と既存core／evidence寿命回帰を保持。全Swift824件・Python155件と残る実guest／比較側／永続化／画面条件はcaptured-picker-ui-verification.ja.mdを参照。画面外構築やfixture request成功を実workflow同等性とはしない。
