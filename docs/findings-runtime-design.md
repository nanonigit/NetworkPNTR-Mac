# F4 Findings runtime parity

## Requirements

Compare the finite FindingService reads and mutations against clean pinned e75ae371ad777ffd1eecdd28d2781a6519b05591 in a disposable reference and a dedicated VM. Keep browser8787, user data, profiles and the candidate/default kernel unchanged. No createTask/launchTask, agent activity, external targets or cloud connections. No host agent commands, host shares or general guest RPC.

F4a prepares a developer-only one-shot SQL seed and proves it on the complete pinned PostgreSQL16 schema. Require Linux/aarch64/UID1000, explicit ARTEX_FINDINGS_FIXTURE=1 and the exact guest loopback artex role/database/port with a generated64hex password and sslmode=disable; clear inherited PostgreSQL overrides. No command-line path/SQL/identifier input. Refuse a nonempty diagnostic database under transactional locks; bounded lock/statement/child timeouts; SQL failures before COMMIT roll back; timeout or lost commit acknowledgement is unconfirmed and must retain state. Failures emit no proof or credentials and are never automatically retried. No product startup/UI hook.

Use11 done/notqueued/notpaused/profile-null terminal tasks8101..8111 with matching explorations. Create33 findings9101..9133:21 belong to8101, one each to8102..8111, two unassigned. Twelve groups exercise group10 and flat20 pagination. Non-orphan node IDs15101..15131 differ from standalone IDs; legacy node15190 has no standalone handle. Task8111 directly inherits8101. Synthetic company8200 and assets8201..8203 cover root_domain/subdomain/ip, company/ancestor/unassigned-asset scopes and empty/multiple anchors. Use example.test and198.51.100.9 only as data, never connect. Cycle all4 severities/9statuses/3classes, preserve FEFF/NFD/CJK/apostrophes and fixed timestamps. No finding retests, traffic, conversations, profiles, LLM usage or jobs.

## Design

Generate fixed SQL from trusted in-module fixture constants with SQL literal quoting, never environment interpolation. Lock/check all touched and activity tables before insertion; insert tasks/explorations, companies/assets, finding nodes/rows and one read-only relation in one transaction. Require exact post-insert counts before COMMIT. Print fixed IDs/counts only after psql success. Mocked subprocess success proves control flow only; independently read actual PostgreSQL rows/bytes and repeat refusal before accepting F4a. Preserve any failed preparation state/logs as counter-evidence and remove only owned component containers after export.

F4b adds a bounded native exercise/probe plus independent reference client. Compare stats, flat/group pages/filters/sort, asset scopes, standalone/node identity, inherited/legacy read-only context, separate name/class/severity/status patches, validation, delete/cache effects and same-disk restart persistence. Verify no activity/profiles/usage before and after each stage. No automatic mutation retry; compare canonical reports only after both actual runs complete. Keep full stopped VM log audits/cooperative stops and earlier kernel faults visible.

## Ordered tests

F4a: missing seed RED -> fixed dataset/environment/child boundaries GREEN -> Python/static security review -> actual complete-schema PostgreSQL rollback/readback/replay tests -> full regressions/signed build/exact-head CI. F4b then implements service exercise/probe/reference and actual same-disk VM operations. Actual visible native/browser/keyboard/VoiceOver checks still wait for manual unlock. F5 advanced Findings and all21/cloud/reliability/clean-Mac/release gates remain mandatory.

Lazyweb is out of scope for this backend fixture/runtime phase.


## F4b finite experiment

The operation set covers flat/group pagination, whole-table stats,4severity/9status/3class/12task filters, Unicode literal search, every returned asset scope, standalone/per-task/inherited/legacy identities, separate edit/triage, two deletions and persistence. Gate requests to Findings read/PATCH/DELETE routes, fixed IDs and finite query keys; apply a hard count and monotonic deadline with pre/post-await cancellation. No create/resume/chat/retest/deepen or arbitrary scripts belong in the Core runner. The DEBUG-only fixture adapter may invoke only fixed seed/audit source under the guest boundary. Audit terminal tasks, no profiles/agent activity/LLM records/usage/conversations/retests/traffic and no configured notification channels; internal status event records are not agent activity.

Use three boots: authenticate+seed; restart for task hydration and reads/mutations/checkpoint; restart for persisted state and deleted-node validation. A compound status plus NUL-containing name is a candidate actual partial-commit witness: server.go status transaction precedes the name update; the actual PostgreSQL error/status/unchanged-name result must be measured in both environments. No assumptions or fake responses count as that proof. Explicitly acknowledge only the captured uncertainty episode before further deliberate fixture changes. Preserve every failed boot/stage and do not retry mutations or promote the kernel.


F4b native probe implementation checkpoint:100 initial reads,14 mutation requests and2 post-mutation aggregate reads share one128-request outer gate and90sec pre/post lifecycle budget. Restart validation uses100 reads. DEBUG VMProbe --findings refuses existing output, uses a fresh2GiB disk for3boots, audits fresh SQL before seed and seeded SQL before any Core mutation, checks source hashes each boot and retains failure state/logs. Shared boot-log proof types also used by archives introduce no archive operations. Controlled616Swift (615pass/1AXskip) and102Python pass; actual hardware/reference remains a separate gate.


Actual basic API/state checkpoint: native3boots and corrected independent reference3starts match; see findings-runtime-verification.md. Keep the remaining individual-field/boundary/normalization, actual UI, advanced Findings and full-product gates open.

Boundary integration uses checkpoint schema2 with100initial+7boundary+14mutation+2aggregate=123 requests, retaining the128/90sec gate. Audit before initial reads, before boundaries, after restoration and after mutations; after restart remains100reads/twoaudits. Shared boundary proof contains six exact named assertions; native-only local validation proof contains three no-dispatch assertions. Reject schema1 as expanded proof and preserve its historical receipts.8192bytes is the finite diagnostic cap, not an upstream field maximum.
