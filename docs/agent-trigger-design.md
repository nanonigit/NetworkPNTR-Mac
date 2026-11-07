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
