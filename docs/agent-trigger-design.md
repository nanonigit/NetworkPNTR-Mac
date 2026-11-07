# Agent triggers

## Requirements

Support the pinned browser's custom-agent trigger rules and execution policy.
Rules can combine a schedule, finding, goal completion, task timeout, tool
call and task creation. Each condition has an independent message.
Preserve the tool filter and the existing rule status when editing.

## Design

Use the existing authenticated rule list/create endpoints and the ID-based
update/delete endpoints. Check current membership in the selected agent's
list before ID-based operations. Check receipts and confirm the result
through a fresh list. Do not automatically replay mutations. Represent
IDs as Int64 and accept the legacy null tool list as empty. Send only the
three trigger policy fields through the existing agent config endpoint
and read them back. Defer user interaction and scheduling acceptance to
the native screen phase.

## Verification

Check payload shape and all conditions, wrong owners, wrong receipts,
removed rows and unchanged config fields. Compare a disabled rule's
create/edit/delete sequence on the pinned browser API and the managed
VM. Disabled rules allow storage verification without running an agent.

The pinned API fixture and signed VM probe both accepted a disabled rule
with all six conditions. The VM read back its edit and policy after
reboot, removed the fixture, and restored the original policy. Both
boots stopped cooperatively with no virtual NIC or host shares.
The Swift suite passed 1,096 tests with one existing skip.
[Verification receipt](../evidence/agents/trigger-service.json)

The native sheet follows the pinned browser's policy, condition and existing
rule groups. Lazyweb's Drip and Productboard examples informed separating
rule editing from saved rules. Saving is explicit, deletion is confirmed,
and failed writes require a reload before another mutation. Enablement is
visible in the rule editor, including when adding a disabled rule.

The native build exposes the Trigger tab for custom agents. The rule form
and policy use the same six event kinds and policy values as the frozen
editor. Changing enablement reads the current rule before sending the
full rule required by the pinned API. Swift tests passed 1,097 cases with
one existing skip, including the enablement preservation case.
Interactive native and browser comparison remain open. An interval firing
test should use a synthetic provider to check the generated conversation
and last-fire timestamp. The frozen scheduler includes Chinese in its
generated interval title and message context.

The signed local Release preview now includes the Trigger tab and its English
and Japanese resources. The interval acceptance probe exercised a single
Reporter rule on both the signed managed VM and the disposable pinned
browser backend. The disabled rule remained idle across a scheduler tick.
After enablement, one new Reporter conversation completed with a synthetic
provider, and the rule acquired a last-fire timestamp. The fixture was
removed. The VM retained zero NICs and host shares and stopped cleanly.
The remaining five event kinds and the interactive UI comparison still
require end-to-end tests.
[Interval verification receipt](../evidence/agents/trigger-scheduler-interval.json)

The task-creation probe created a historical task while the rule was
disabled, waited across a scheduler tick, then enabled the rule. Neither
backend replayed the historical event. A new task produced one completed
Reporter conversation associated with its task ID. Task bootstrap used a
separate loopback-only profile, and Reporter used a synthetic provider.
The rule was removed after verification. The signed VM stopped with zero
virtual NICs and host shares.
[Task-creation verification receipt](../evidence/agents/trigger-scheduler-task-creation.json)

The finding-trigger probe inserted two fixed synthetic finding nodes in a
disposable task. The disabled period advanced the scheduler watermark, and
enabling the rule did not replay the historical finding. A new finding
produced one completed Reporter conversation with the owning task ID.
Both the pinned browser backend and the dedicated VM matched this
behavior. The VM restored the original rules and stopped cleanly.
This covers scheduling and model handoff after a finding is recorded.
[Finding verification receipt](../evidence/agents/trigger-scheduler-finding.json)

The goal trigger used the same scoped test harness as the finding trigger.
A synthetic met goal recorded while the rule was disabled did not replay
after enablement. A second synthetic met goal completed one Reporter
conversation and matched the owning task ID, in both the pinned backend
and the dedicated VM. The VM restored the initial rules and shut down
with no virtual NICs or host shares. This checks dispatch after the goal
reaches the met state.
[Goal verification receipt](../evidence/agents/trigger-scheduler-goal.json)

The tool-call trigger matched the pinned browser backend and the dedicated
VM. An older completed call, a completed call for a different tool, and a
matching call without a result produced no conversation. Adding the
matching result produced one completed Reporter conversation with the
owning task ID and the paired input and output. The test used synthetic
activity, removed its rules, and stopped the isolated VM.
[Tool-call verification receipt](../evidence/agents/trigger-scheduler-tool.json)

The task-timeout probe injected three timeout state transitions. Both the
pinned browser backend and the dedicated VM skipped the timeout recorded
while the timeout rule was disabled and an unrelated rule stayed enabled.
A later timeout on an older task was also
missed, while a new higher-ID task produced one completed Reporter
conversation. The fixed scheduler stores `last_timeout_id` and selects
only timed-out tasks with IDs above it. Task IDs follow creation order,
so an older task can time out after the scheduler has advanced past it.
The signed VM removed the fixture rules and stopped cleanly. These tests
cover dispatch after a timeout state is recorded. Elapsed timeout
enforcement and the actual screens still need separate checks.
[Task-timeout verification receipt](../evidence/agents/trigger-scheduler-timeout.json)

A repair must distinguish timeout occurrence from task creation order
and define the rule's disabled-period semantics across restarts.
The fixed scheduler skips polling entirely when no rules are enabled,
so the repair needs a separate test for the all-rules-disabled case.
Before promoting a repaired guest, verify that a late timeout on an
older task is delivered once, that timeouts from the disabled period
are not replayed, and that upgrades do not replay historical timeouts
or discard a still-running older task's future timeout.

### Managed timeout dispatch repair

The managed guest will track consumed timeouts by task ID membership.
A one-time schema migration records tasks already timed out at upgrade,
including archived rows still present in the task table. An active older
task remains eligible when it later becomes timed out. The poll claims
unseen live rows atomically with a unique key and still runs when no rules
are enabled. Other event pollers keep their existing activation rules.
Suppression is evaluated at the poll. Re-enabling a rule before the
next poll can deliver a timeout from the preceding disabled period.
Claims prevent redispatch on routine restart. Conversation delivery
is best effort because shutdown or an unavailable chat agent can
interrupt delivery after a claim. Verify migration replay, out-of-order claims, concurrent
claims, all-disabled polling, and the fixed browser comparison before
promoting the guest.

The signed cloud8 candidate probe used the same trigger sequence as the
fixed baseline through the late timeout. The lower-ID task now completed
one Reporter conversation, with no additional conversation across the
next polling interval. The separate disposable PostgreSQL 16 fixture
ran the migration and claim statements, covering upgrade seed data,
migration rerun and concurrent claims. The first probe used a fresh disk. The upgrade and all-disabled
results are below. The native screen comparison remains a release gate.
[Repair receipt](../evidence/agents/trigger-scheduler-timeout-repair.json)

The upgrade probe creates an owned fixture disk on cloud7 and boots
cloud8 with that same disk after a cooperative stop. It checks that
the existing session and conversation identities survive, and that
the upgraded guest still rejects unauthenticated conversation reads.
The probe marks one synthetic timeout as soft-deleted before shutdown.
Only schema migration can seed that row because the normal scheduler
excludes deleted rows. The upgraded probe checks the migration marker
and all three fixture memberships, audits both isolated boots, and
requires the disk format step to occur only on the first boot.

Run the signed DEBUG probe with the pinned cloud7 and cloud8 artifacts:
`VMProbe --cloud-vsock CLOUD7 NEW_PRIVATE_OUTPUT --timeout-upgrade CLOUD8`.
The output directory must be new. The probe creates its own disk.
The signed upgrade passed on Mac hardware. See the repair receipt
for the two manifest hashes and stopped-VM result.

The all-disabled probe temporarily disables the existing custom-agent
rules and verifies zero enabled rows before injecting the historical
timeout and when observing its first claim. It enables the fixture rule
only after observing that claim. The repaired VM completed only the
later eligible timeout and restored the changed rules. The fixed browser
backend replayed the historical timeout after enablement. The check
observes persisted rule state and does not instrument the scheduler's
in-memory rule snapshot. An earlier VM attempt panicked during guest boot.
The final run passed its isolation and cooperative-stop audits.

### Elapsed task deadline

The elapsed-deadline probe creates a task through the regular task API
with an eight-second budget. Its planner uses the loopback-only profile
with an unavailable endpoint, leaving its synthetic goal unmet. The
engine supplies the start, deadline and terminal status. The probe reads
these values and requires the deadline to be exactly eight seconds after
first run. It allows one second of tolerance for the engine's Unix-second
deadline comparison. Reporter uses the synthetic streaming provider and
must complete one new conversation for that task. This exercises the
error path of the final planner. A successful final planner that decides
the goal was met is a separate case.
