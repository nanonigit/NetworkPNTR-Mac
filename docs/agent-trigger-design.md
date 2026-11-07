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
