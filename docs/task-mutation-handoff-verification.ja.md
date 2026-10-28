# タスク準備の修正チェックポイント

RED89bda84で、直接5操作と共有取得3種の同期取消/停止を4件・37アサーション失敗で再現した。修正51f3370は取消確認済みTaskService callback、actor内lifetime/activity/ticket照合、直接/外部ticket由来busyを追加する。取得再入防止と公開後の確認で古い/取消済み外部tokenを拒否する。bugs/task-preparation-handoff.ja.md参照。

公開API・本文/status/ID照合・自動再送なし・ローカル拒否・handoff後不明・再取得失敗後の確定・選択・reset終了待ちは維持する。重点31件（handoff4・サービス13・状態14）と独立レビュー成功。実task作成/再開・guest agent・browser変更・通信方針変更は実行せず、注入した合成応答で検証した。backendのみなのでLazyweb対象外。

全Swift647件（646成功・既存外部AX1件明示保留）、Python123件。LLVMはTaskStore229/229・TaskService80/80行。署名build-only・厳密署名・翻訳export・固定構成照合成功。依存追加なし。全体には既存category/archive/bulkのUI workspace試験も含むが、それらの送信境界や実画面受入の証明ではない。

次は取得後の外部workspaceとLLMStoreを監査し、証跡のネイティブ操作、非空の実証跡/本文/競合/保存、解除後の画面/キーボード/VoiceOverへ進む。残るF5/全21/cloud/kernel/別Mac/配布は未完了。実guest/browserのライフサイクル・隔離証拠は別途集め、以前の実測は保持する。
