# 外部タスクhandoffチェックポイント

RED6711a05はcategory閉鎖/live停止、bulk live停止、archive live/cold停止をbusy時に再現し、workspace44件中10アサーション失敗。実装4853bf3はTaskRequestHandoff、現live/cold確認、型付きservice overload、捕捉したcontroller検証を追加した。元の署名/本文/レイアウト/確認フローは維持。bugs/task-external-handoff.ja.md参照。

categoryはbusy前にowner/editor/lifetime/親/入力を捕捉し、送信前の古い文脈を拒否、送信後の既知結果はsuspend後も保持する。bulk連続削除は毎要求別markerとし、最初の確定後に失効した後続項目は未開始で、不明や再送にしない。archiveはretry/batchもmarkerを渡し、202はqueue受入のみ。未送信の取消は未開始、他ローカル不正は拒否、以後は既存status/不明方針を維持する。Core試験はvalidator例外/内部取消でwasDispatchedがfalseのまま、再利用で2回目を送らないことを検証。handoffはtransportが動作し得る境界で到達/保存の証明ではない。

重点83件（workspace45/Core38）と独立設計/実装レビュー成功。全Swift654件（653成功・既存外部AX1件明示保留）、Python123件。LLVMはmarker8/8、category service137/137、archive service98/98、TaskStore234/234、cold162/165、category workspace249/259（96.14%）、bulk196/218（89.91%）、archive163/167（97.60%）行。署名build-only・厳密署名・翻訳export・固定構成照合成功。依存追加/実guest書込/job/agent/browser配備/通信変更/provider認証使用なし。

category/bulk/archiveの取得後handoffをソースと制御試験で確認したが、実画面/実guest/browser受入ではない。次はLLMStore監査、証跡UI、非空の実証跡/本文/競合/保存と解除後の画面/キーボード/VoiceOver。残るF5/全21/cloud/kernel/別Mac/配布も未完了。固定版e75ae371ad777ffd1eecdd28d2781a6519b05591は保持し、以前の実測を今回の証明にしない。今回のcontroller/transport修正でLazywebは対象外だが後のUI作業には必要。
