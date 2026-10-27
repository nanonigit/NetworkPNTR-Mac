# F5b 通信証跡の状態管理チェックポイント

FindingTrafficStoreがfinding/task/binding、一覧/詳細/本文の世代、sideとバイトページ、準備した書込、確定・不明回を所有する。ネイティブ操作にはまだ接続せず、空でない実guest証跡の証明でもない。固定版・browser配備・guestデータ・通信/隔離は変更せず、agentやhostコマンド能力を追加しない。backend状態のみなのでLazywebは対象外。

未実装REDdedfcb2を実行後に実装した。初期7件と追加2件が通ったが、独立レビューで送信前取消を不明扱いする点を発見。同期Observationの2回帰ケースで11件中5アサーションが21439beのREDとなった。実装ee62d39は取消確認済みtransport引渡し、ticketから算出するobservable busy、直前のowner再照合、古い読取を無効化する確定一覧setterを追加した。bugs/findings-traffic-handoff.ja.md参照。修正再レビューで追加の阻害問題なし。合成応答試験から実通信成功とは主張しない。

状態11件は一覧/詳細/本文の逆順、finding/binding/side/offset/snapshot/total対応、同queryの古い値保持、一覧成功時だけの所属照合、不正入力の送信ゼロ、書込1件、再取得失敗後の確定保持、409不明と再送禁止、読取では確認しない、選択をまたぐowner/revision確認、停止/再開の終了待ちと遅い成功破棄、reset後の新書込を古いcleanupから保護、継承/旧形式、handoff前後の取消を検証する。停止中の読取/選択は送信しない。型付き読書込も成功し重点計21件。書込開始時に詳細/本文の読取が実行中の場合もあるが、世代を無効化して古い結果を採用しない。全通信を巻き戻せるとは扱わない。

全Swift641件（640成功・既存外部AX1件明示保留）、Python123件成功。LLVM行カバレッジは状態161/163（98.77%）、共通読取50/50、サービス93/93。署名build-only・厳密署名・翻訳export・固定構成照合成功。ソース試験と実環境の受入は区別する。npm/pip依存追加なし。

次は同じ準備/handoff境界を既存の変更状態で追跡監査し、Lazywebと固定browserを使うネイティブ証跡操作へ接続する。その後に空でない実証跡/本文/競合/再起動比較と解除後の画面/キーボード/VoiceOverを確認する。lineage/retest/deepen/高度report/実bytes出力、全21機能、native cloud通信、以前のkernel障害/昇格、別Mac導入/配布は未完了。F5や全体ゴールの完了とはしない。
