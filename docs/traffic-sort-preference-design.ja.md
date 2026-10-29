# 通信履歴のソート保存（TR3）

固定useStoredSortPreferenceのtraffic-sortに合わせ、ts/status/resp_lenとasc/desc、初期ts/descを保存する。検索文・packet・host・page/size・選択・確認・秘密情報は保存しない。配置変更のない状態／設定処理なのでLazywebは対象外。Traffic紐付け／blob／VM／ブラウザ／画面／release／4社／harnessの全条件を維持する。

独立したnative UserDefaults key traffic.sort.preference.v1へ、field/directionだけの上限付きJSON Dataを保存する。任意注入にし、nilなら保存なしで既存呼出／試験を維持する。形式は元hookと同じで、whitelistと4096bytes以下を検証し、不正／欠落／旧形式ならts/descへ戻す。復元が受理された後だけ2項目へ正規化し、無関係な入力項目を除く。ブラウザや他設定は読み書きしない。rootは標準アプリ設定、試験は使い捨てsuiteを使う。

表示ごとに最初の読取より前に復元する。stop/resetはquery／下書きを消すが、非公開データを含まない保存済みの順序は残す。前の送信済み書込みが画面往復後もコアを占有している場合、結果確定まで復元を待つ。復元前に初期順の読取や操作許可をしない。ゲート解除で取得済み設定を復元してから現在の読取を要求する。結果不明は維持し、自動再送／承認しない。現在query／lease、独立タイマー、reset優先を保つ。

受理されたsort操作だけを保存し、method/status/sizeや検索欄は保存しない。query通知中にstop/resetが入った場合、放棄した復元／操作で保存値を上書きしない。保存通知もモデルのガード付き更新内で行い、再入操作を拒否してresetを優先する。表示開始時に共有設定を取得し、元hookと同様に他窓の変更をリアルタイム反映しない。

先に全6組、不正／上限／余分な項目と正規化、begin前の書込なし、初期値／保存なし、受理後の保存と再表示／ログアウト時の原文消去、禁止／古い操作、通知中のstop/reset、保留書込み後の遅延復元と再送／承認なしを試験する。その後レビュー、限定／全試験とcoverage、署名ビルド、remote確認。設定の権限エラー、root起動／実画面／keyboard／AXと全体受入は別途残す。
