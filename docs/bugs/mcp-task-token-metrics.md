# MCP task counters used the wrong frozen API projection

Status: reproduced and corrected in the read broker. Unit/transport checks and the real pinned database/API component pass. Signed native selected-task/helper and rendered browser comparison remain pending.

The fixed backend's task-detail route (`server/server.go:1838`, `server/dto.go:104`) builds a DTO without token aggregates. Its task-list route (`server/server.go:1159`) explicitly fills those fields from database metrics. The broker used the detail service, so a real task with usage would report zero. The regression supplies the two different responses and first observed `0` instead of `4294967294`/`13`.

Five whys: counters were zero because the detail DTO did not fill them; the broker used detail because it assumed the two task shapes had equivalent content; tests supplied populated counters for that detail response; the synthetic contract fixture therefore hid a real endpoint distinction; early live MCP checks only covered agent discovery and denied task access. The corrective acceptance fixture must include a permitted populated task, not only empty/denied states.

The broker now checks task permission before the list GET, checks cancellation/account/runtime ownership again afterward, selects the exact authorized ID or fails404, and returns only the existing six-field projection. It does not expose, cache or log the other task rows. Missing IDs never fall back to zero totals. Tests cover selected and unselected rows, absence, in-flight revocation/cancellation and the actual stdio/socket path. No inference route or model configuration is called.

The diagnostic inserts terminal tasks only into a new VM database with zero model profiles/usage. Each activity column is int4; two max-int4 rows produce an Int64 aggregate above signed Int32. Explicit IDs and transactional sequence resets cover every sequence the seed touches. The pinned component forces rollback and checks rows plus all three affected sequences, rejects repeat insertion, restarts the task manager and reads the real API. Above2^53 transport coverage remains synthetic; it is not claimed as a live database counter.

Reference harness failures are retained privately: an overlong temporary password, a manager reload requirement, raw snake_case decoding, and an initially incomplete sequence snapshot. The final harness restricts Docker to the local Desktop Unix context and cached pinned images, publishes no ports, and independently attempts owner-checked cleanup after failures. Docker is used only for the frozen browser reference; it remains unnecessary for the Mac app runtime.

See [component receipt](../../evidence/mcp/task-read-metrics.json). This fix does not close task writes, external-AI execution, native outbound MCP, boot reliability, clean-Mac registration or paired UI acceptance.

Verification orchestration note: the211-case Python run had two SwiftPM path-query timeouts while a Release build held the same build directory. These CLI checks must run after Swift builds finish; do not increase timeouts or restart a live build to manufacture a pass. Preserve the initial errors and recheck only the two failed cases sequentially.
