# ネイティブタスク — T1有限API設計

固定参照はARTEX `e75ae371ad777ffd1eecdd28d2781a6519b05591`。server/dto.go、server.goのlist/create/get/control、task_metadata.go、task_control.go、server_mgmt.go、web/src/lib/api.ts、function/tasks/page.tsxを調査しました。

最終目標はtask一覧／詳細の全機能同等です。T1は既存認証transportで一覧／詳細／作成／metadata／pause-resume／batch-control／削除を実装。Tasks UI／runtime／全体合格ではなく、分類／template／archive／添付／LLM chain／graph／goal／constraint／main-agent chat／SSE／詳細tabとnative/browser比較を続けます。作成／resume／active APIはagentを開始するため、ユーザー状態で試験せず、Macでagentを動かしません。active化を読取操作として呼びません。

TaskRecordはTaskDTO全項目・nullable／省略項目・文字列taskID・Int64 ID／counter・未知status／独自文言・source／profile順序を保持。pathは正の10進IDへ正規化し、query／path注入を拒否。一覧重複ID・変更結果の所有者違い・不正envelope／counterを拒否。ローカル検証は型付き日英で、任意server error本文を表示しません。

作成draftは現frontendの全項目（name／category、description／goal、順序付きprofile／source／company、timeout／heartbeat秒、seed、coverage、intercept rule）を保持。ECMAScript trimとdescription／goal必須、source上限8、正／重複なしprofileと正規source、company正IDの先頭順重複除去／32件上限。空rule patternはbrowser同様除外し、非空ruleの構文検証はbackend責務。オプションを黙って落とさず、heartbeat既定600は作成フォームに一致、明示0はbackend既定値sentinelとして保持。暗黙active化や変更後の自動再試行はしません。

metadataはname／pinnedどちらか必須、nameはbrowser trim後1〜200 Unicode scalar/rune。controlはpause／resume列挙。batchは正規IDを先頭順で重複除去し1〜100、結果件数／順序／成功statusを検証。個別失敗はfalse保持し、任意error文字列は保持しません。削除option5項目はすべてfalse既定で全項目送信し、結果のcleanup6指標と警告有無を保持。HTTP200＋cleanup警告は削除済みで、再試行する失敗としません。警告本文は保持／表示せず、応答所有者／counter不整合はエラー。UI／state層も未確認変更を自動再実行してはいけません。

試験は固定schemaの非空一覧／詳細・nullable・大ID・作成全option／省略・metadata rune境界・正規／注入IDと検証失敗時通信なし・部分batch所有者・削除集計／commit後警告・HTTP／不正／重複／別所有者・独自文言保持／error秘密除去。スクリプト応答transportの単体試験をbrowser／VM合格と扱わず、TDD RED/GREEN・全回帰・対象coverage・review・署名を実施。使い捨て参照＋VM fixture、UI／state／cancel／永続化比較は別ゲートです。backendのみのためLazyweb対象外。
