# T9 カテゴリ API 設計・試験計画

比較元は固定 e75ae371ad777ffd1eecdd28d2781a6519b05591 の server/task_categories.go、db/task_categories.go、server/server.go、web/src/lib/api.ts、tasks 画面の管理・即時作成。今回は認証付き有限 API の実装で UI 作業なし、Lazyweb 対象外。カテゴリ管理、作成フォームの即時作成と選択、一覧フィルタ・移動、実 VM/ブラウザ比較は後続の必須条件として残す。

一覧 GET は200、categories:null は空。ID は正のInt64、名前は原文、task_count は非負Int64、作成・更新時刻は文字列。JSONSerialization の再変換は禁止。作成 POST は201、名前変更 PATCH は200。名前は JS 外側 trim 後に送信し、Go TrimSpace 後の文字数を80以下と検証する。サーバーは空白圧縮より前に長さを確認するため圧縮後だけの確認では不足。NFC 正規化や翻訳をしない。重複名はサーバー409に委ねる。削除は200と同一数値 ID を確認し、タスク削除オプションはない。

単独移動 PATCH /api/tasks/{id}/category は正の category_id または明示 null を送信。完全な TaskRecord、同一タスク ID と指定カテゴリを確認。複数移動 POST /api/tasks/category/batch は順序を保ち正規化・重複除去した1〜100件と category_id を送信。応答の各 id/ok は順序・件数一致を確認し、生の失敗本文を保持しない。成功があれば指定カテゴリ行が必須。全件失敗では null を許可する。解除なら必ず null。実行・再開・アクティブ選択・タスク作成は行わない。

送信前後キャンセル、応答4MiB・要求16KiB、厳密な成功ステータス、入力不正は送信ゼロ。応答不一致は結果不明で自動再送しない。画面所有権・セッション管理は次のモデル連携で検証。試験はスキーマ・Unicode・大整数、JS/Go 空白と長さ、単独の解除と所有者、複数の順序・部分失敗・全失敗、異常応答・キャンセルを RED→GREEN で実施し、全体回帰・カバレッジ・レビュー・署名ビルド・翻訳確認を行う。全21機能の受入条件は未完了。
