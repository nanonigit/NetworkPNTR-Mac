# ネイティブcapture診断の調査

再現・証拠：従来のSQL-bound snapshot fixtureでは原本保存できてもcapture indexが空だった。新guest moduleの初回6試験は未実装で失敗（08b85d6）、live WALも含む7試験で合格（6655acc）。これらの契約REDで実guestをcrashさせたわけではない。

初期native clientは実行source hashを改変した有効応答を受け入れ、4試験中1失敗（6d3ac92）。実際にcompileしたguest文字列のhash mapを返し厳密比較して修正（7bbb8db、4合格）。レビューでは再取得summary空を配列添字で読むとtrapし、VM停止／失敗記録を迂回する経路も発見。空summary guard試験は初めcompile失敗（22664ed）、membership／order検証後に読む修正で8合格（816b413）。静的に特定したcrash経路とguard回帰であり、実VM crashを観測したとはしない。上限試験も無効な空白だけの応答から、有効JSONに空白を加えた応答へ替え、size guard単独を検証した。

5 Whys：native capture未検証→旧fixtureはsnapshotのみ→recorderが埋まらない→native store向け共通実loopback診断がない→guest scriptへ認証を埋め込むべきでない→readonly index guard／生成と認証付きnative API比較を分離した。hash不備はlocal inventoryを実行入力証明とみなし、改変応答試験がなかったため。添字不備は有効DTOでも空になり得るのに、以前のmembershipが再取得でも維持されると仮定したため。

Fishbone：fixture＝snapshotと実recorderの違い、認証＝credential埋込なし、storage＝live WAL readonly可視性、lifecycle＝不明応答／readback／ack、来歴＝実compile source hash、oracle＝空readbackはtrapせずthrow、受入＝typed native統合とUI／kernel信頼性／releaseの区別。

Timeline：guest RED08b85d6→7GREEN6655acc、client compile RED196c59d→4GREEN8453f36、hash改変RED6d3ac92→GREEN7bbb8db、oracle／gate RED36b4434→GREEN0a6a293、picker初期値参照REDb59c2f7→GREEN43fd2c3、独立参照fd1c70b exit0、空summary RED22664ed→guard／store修正816b413、実native2boot比較exit0・別の計測repeatもexit0。

検証：Swift832件（831合格・既存external AX1skip）、Python179件合格。両native実験で29記録・実page／filter／source・選択store preview・全原本4件・preview5件・追加／編集／順序／削除・古いversion409・保持を確認。実編集の成功応答1件を制御して返さず、不明write gate・明示回復・再実行なしを証明した。物理socket切断の検証ではない。実countを含むnative exercise JSONは独立参照と一致。各実験は別fresh diskと協調停止する実VZ2bootを使用。coverage／hashはcaptured-native-verification／captured-native-comparison.json参照。

再発防止：hash改変・失敗後seed再実行拒否・所有／network／index拒否・live WAL・有効上限超過envelope・cancel・不正phase応答・空summary guardを維持。最終gateは両bootの正常監査・厳密参照一致・実行source証明・明示不明回復が必須。この診断だけで実UI／翻訳／標準kernel／release／製品全体を完了にしない。
