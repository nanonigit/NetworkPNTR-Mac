# F5 runtime：実通信indexと更新比較

実装更新：下記native診断契約は、独立した実VM2boot比較を2回通過した。captured-native-verification.ja.md参照。UI／翻訳／製品全体の条件は別途未完。

変更前のnative/backend起動は-proxy空文字のためtraffic.Openが呼ばれず、通信APIは利用不可となる。固定ブラウザと同じ127.0.0.1:8788の記録listenerをゲスト内で使う。外部NIC／route・ホスト共有／公開port／socketなし、UID1000、system読取専用、guest内private stateを維持。CAをMacへ登録せず、外部／クラウドegressも有効化しない。backend-init編集と実native artifact再build／bootは別gateで、編集だけで既存bundleは更新されない。

SQLiteへの偽record投入でなく、記録proxyを通して固定loopback HTTP fixtureへ実通信し29件を生成する。25行paging、GET／POST、FEFF／NFD／英日／CJK、空、複数page text、inline／spill binaryを持つ。listener・method・path・byte長・headerは固定。Linux／aarch64／UID1000、明示診断flag、正確なloopback DB、NICなし証明後だけ書込／listen。既存indexが非空なら拒否し、profile／agent／scheduleのない終了済みtask／findingだけseed。実websiteは対象にしない。

まず所有するoffline containerの固定backendへ、独立Python HTTPで非空candidate／filter／page／原文、追加／編集／順序／削除、古いversion409、readback、2起動の永続化を確認。長さ／hash／上限付きpreviewを比較し、実行ごとに異なる生成ID／時刻を同一とみなさない。固定URL ordinalと不変本文で独立実行を対応付ける。失敗とprivate DB／logを保持し、本文・キー・runtime stateはGitへ入れない。

次にcapture有効のfresh native artifactを再buildし、検証済みsource kernel候補を標準昇格せず使用、認証vsockからtyped native service／storeで同じfixtureを試験。独立した正規化結果と原本、再起動状態を比較。fixture／API実証で新UIのmouse／keyboard／VoiceOver／browser画面受入を代替しない。以前のSQL snapshot紐づけだけのfixtureを非空capture更新試験の代用にしない。21workflow、VM／kernel／release、4社、調査roadmapを維持。今回はguest／基盤作業でLazyweb対象外。

## 次のnative診断契約

capture設定候補は既存の原本保存回帰試験を通過したが、実記録indexは未検証。別のDEBUG限定captured fixture／probeを実装する。seed／listen前にLinux／aarch64／UID1000・明示flag・正確なloopback PostgreSQL DSN・外部接続なし・freshな終了済みfixture活動・既存capture index空を確認。診断sourceを固定しhash照合し、bearer／passwordをscriptへ埋め込まない。ゲスト側の独立guardには/state/app/data/traffic/_index/index.sqliteへの固定read-only queryを使ってよいが、capture行は挿入しない。native認証とcapture API照合は認証付きvsock上のtyped serviceで行う。

参照環境と同じ29通信manifest／URL ordinalで対応付け、page／filter／detailの実byte、CapturedTrafficPickerStore／FindingTrafficStoreからの追加、厳密sourceID・role／note／order／version・古いversion conflict・原本／分割previewを確認する。boot2は同じprivate diskを再利用しseed／通信再生成せず、index29／binding1／snapshot2／最終versionを確認。結果不明回復は期限付きtransport故障と実readback／明示ackで証明し、mockだけで完了扱いにせず未確定writeを再実行しない。両bootで協調停止・private認証値監査・NIC／shareなしを確認する。新UIの画面／keyboard／AXは解除後の別gate。
