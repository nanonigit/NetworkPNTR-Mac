# F5 runtime：実通信indexと更新比較

変更前のnative/backend起動は-proxy空文字のためtraffic.Openが呼ばれず、通信APIは利用不可となる。固定ブラウザと同じ127.0.0.1:8788の記録listenerをゲスト内で使う。外部NIC／route・ホスト共有／公開port／socketなし、UID1000、system読取専用、guest内private stateを維持。CAをMacへ登録せず、外部／クラウドegressも有効化しない。backend-init編集と実native artifact再build／bootは別gateで、編集だけで既存bundleは更新されない。

SQLiteへの偽record投入でなく、記録proxyを通して固定loopback HTTP fixtureへ実通信し29件を生成する。25行paging、GET／POST、FEFF／NFD／英日／CJK、空、複数page text、inline／spill binaryを持つ。listener・method・path・byte長・headerは固定。Linux／aarch64／UID1000、明示診断flag、正確なloopback DB、NICなし証明後だけ書込／listen。既存indexが非空なら拒否し、profile／agent／scheduleのない終了済みtask／findingだけseed。実websiteは対象にしない。

まず所有するoffline containerの固定backendへ、独立Python HTTPで非空candidate／filter／page／原文、追加／編集／順序／削除、古いversion409、readback、2起動の永続化を確認。長さ／hash／上限付きpreviewを比較し、実行ごとに異なる生成ID／時刻を同一とみなさない。固定URL ordinalと不変本文で独立実行を対応付ける。失敗とprivate DB／logを保持し、本文・キー・runtime stateはGitへ入れない。

次にcapture有効のfresh native artifactを再buildし、検証済みsource kernel候補を標準昇格せず使用、認証vsockからtyped native service／storeで同じfixtureを試験。独立した正規化結果と原本、再起動状態を比較。fixture／API実証で新UIのmouse／keyboard／VoiceOver／browser画面受入を代替しない。以前のSQL snapshot紐づけだけのfixtureを非空capture更新試験の代用にしない。21workflow、VM／kernel／release、4社、調査roadmapを維持。今回はguest／基盤作業でLazyweb対象外。
