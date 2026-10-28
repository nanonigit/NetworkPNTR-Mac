# 実通信記録の調査

## 再現・証拠
native initのproxyが空でtraffic APIが利用できなかった。固定ソースでtraffic.Openがproxy指定時のみ動くと確認。実loopback試験では追加で、不完全HTTP headerが処理を塞ぎ停止待ちになる問題を再現。従来timeoutはexchange()内なのでheader解析より後だった。7秒上限の子process試験がRED、handler classでsocket setup時に3秒timeoutを設定し約3秒で停止してGREEN。

## 原因分析
5 Whys：候補なし→index未open→proxy空→隔離bootstrapがlistener無効→offline隔離とloopback記録を混同→seed済みsnapshot／picker単体試験に実recorder起動の受入がなかった。header停止問題は、期限開始が解析後でparserが期限外だったため。

Fishbone：設定＝proxy空、通信＝期限前parser、oracle＝source／filterの照合不足、来歴＝可変入力／削除後だけの元tag確認、受入＝参照process再起動とnative VM／UI試験の違い。

Timeline：fixture RED56e526e→GREEN414db0d、不完全header REDbfff49e→GREENc2c4d9b、参照REDc981fd6→GREEN28c4740、host RED23de817→GREEN67a473c、receipt negative9ce499e→厳密照合11be4dd、入力固定／元tag guard RED929e82f→GREENde795ec。初回成功は別記録として残し、補強後repeatで正規化結果・実行hash・削除前guardを確認。

## 修正・検証
ゲスト内127.0.0.1:8788 listener、guard付き固定29通信、parserを含む3秒timeout、厳密filter／source、配置前に固定したソースとゲスト実行hash、所有alias削除前の元tag確認。新16件／全171件Python試験と反復した隔離実測が成功。限定したcoverage／保持範囲はcaptured-runtime-verification.ja.md参照。

## 再発防止
別source・filter不一致・不完全header・配置前後のソース変更・元tag欠落のnegative試験を維持。既存indexや所有外guest／network／DB、危険なcleanupは拒否。起動source編集だけでnative成果物導入済みとせず、参照containerだけでnative UI受入を閉じない。VM再build／実2boot比較／画面とアクセシビリティは未完。クラウド・第三者target通信は行っていない。
