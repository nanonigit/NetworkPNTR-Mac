# ネイティブ認証付き元blobの一時保存

元blob／21機能／VM／ブラウザ／4社／ハーネス／リリース目標を維持。HTTP／ビルドだけではMacの保存機能ではない。まず有限のmanifest／転送／一時保存を追加する。今回はbackend／transportでLazyweb範囲外、保存画面の前には使用する。

TrafficServiceは固定blob-metadata経路へ、生IDをescapeし要求／応答の側を明示して取得。id／side／hash／Int64 sizeを不変TrafficBlobDownloadへ読み、UTF8の生ID／側一致、小文字64桁、非負長、既存8192バイトの生／エンコード後上限を検証。本文marker、記録URL、backendファイル名や保存先を受け取らない。転送は固定/api/traffic/blob?hash=HEX、Bearer、octet-stream／identityのみ。候補ファイル名も固定語とdigestだけ。

既存証跡の非公開一時保存、長さ／SHA256、FD基準の保存先、上書きしない原子的公開、再読検証、清掃、単回receiptを再利用。内部Sendable protocolの長さ／hashだけを共有し、公開transportは検出結果用とblob用の型を分ける。既存契約を弱めず、本文に添付／JSON上限を流用しない。64KiBずつ転送し、宣言Int64長を検証。不正metadataや欠落／圧縮／不正／超過bodyは公開しない。

AuthenticationSessionの共通非公開経路で認証先行、revision／VM確認後の401処理、失敗receipt清掃、現401での失効（Vault削除失敗を含む）、公開時の認証／UI／VM／中断検証を維持。BackendJSONClientで固定requestを作り、VMControllerのepoch／socket所有権と清掃を使う。DEBUGの検出結果中断証拠は対象種別を維持し、blobに架空のfinding IDを与えない。

TDDはmanifest／経路／生識別／Int64／応答境界、固定request、実バイナリー保存、衝突／完全性／清掃、型付き認証成功／再利用／logout／遅い200・401／失効VM401／現401／事前中断・停止VM。共通化後も既存証跡・socket・file・中断試験を通す。管理ゲスト来歴、実VMの元バイト／中断、UI所有権／保存パネル、英日／実画面／入力の受入は別途未完。通常ゲストを保持し、未動作の保存操作を露出させない。
