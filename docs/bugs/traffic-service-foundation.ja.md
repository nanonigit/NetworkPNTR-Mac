# Traffic finite境界の調査

再現・証拠：506f52fは新typed契約がなくcompile失敗。eddd908の初回compile済み実行では新2試験で3assertion失敗し、Foundation試験decoderを通すと先頭FEFFが消えた。既存captured-service query／finding noteのoracle問題の再現で、productionのpacket正規化ではない。実percent byteとtyped JSON decodeはFEFF／NFD／plusを保持。修正3790a5eは対象18合格、全Swift849（848合格・既存AX1skip）合格。

5 Whys：試験がbyte欠落を報告→復号valueからFEFFが消える→Foundation URL／JSON bridgeがBOMを消費→便利な復号Stringをwire oracleに使用→既存traffic試験のbyte証拠を再利用しなかった→新suiteにも同じ独立byte境界が必要。原因は損失のある試験oracleでproduction encoder修正は不要。

Fishbone：source＝部分一致／厳密／purge区別、input＝Go対ECMAScript空白とopaque byte、decode＝Foundation BOM消費、精度＝Int64対JavaScript number、変更＝論理dispatch／cancel／結果不明、受入＝finite mockは実VM作用やUIを証明しない。

Timeline：要件／設計・compileRED506f52f→実装／oracle runtimeREDeddd908→独立byte／typed JSON修正・request上限／dispatch後cancelを含むGREEN3790a5e。reviewで固定route／削除意味／partial setting／上限／再送なしを確認。対象source172／172 LLVM行だが全branch／製品workflowではない。

修正・再発防止：Foundation復号queryでなくpercent byteを比較し、JSONはtyped decodeとUTF8 byteを照合。先頭FEFF／NFD／CJK、plus／query区切り、重複／null host、厳密巨大整数、全空host対FEFF host、有効上限超過payload、purge receipt、setting不一致、dispatch前後cancelを維持。実multi-host fixture／store／UI／blob／証跡保持は未完とし、rollback推測や後続UI確認なしの破壊scope公開をしない。
