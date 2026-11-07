# Agent tool assignments

## Requirements

Match the pinned browser's tool membership toggle and preserve its traffic
capture gate for `traffic_search` and `traffic_get`. A toggle changes only
one agent's assignment. Tool description, schema, execution definition,
enabled state and other agents' assignments retain their independent owners.

## Design

The browser's full-row PUT is unsuitable for a membership-only edit. Register
an authenticated managed guest PUT at `/api/agents/{key}/tool-bindings/{tool}`.
The bounded body is a JSON boolean representing the desired state. A committed
response names both keys and the saved state. Use the pinned catalog for
readback. The transaction locks the agent key against deletion, reads and
locks the persisted traffic gate when relevant, then locks the tool row.
An already-matching membership succeeds without an update. A legacy JSON
null represents an empty list. Reject unknown keys or malformed storage.
The transaction does not change the pinned browser's full-row PUT contract.

## Tests and integration

Check invalid input before database access. Exercise the actual PostgreSQL
transaction on a fresh isolated database, including simultaneous updates to
different agent memberships, repeated writes, malformed stored data and the
traffic gate. A later phase promotes the guest image, wires the SwiftUI
control, and compares the app with the pinned browser workflow.

The overlay applied to the frozen source, and the Linux arm64 build passed
the traffic and server test suites with build-step networking disabled.
The dedicated PostgreSQL 16 fixture passed both boundary and transaction
tests. The transaction checks cover simultaneous adds, idempotent add
and removal, unknown rows, legacy null, malformed elements, protection of
other tool fields, and traffic capture disabled before and after a binding.
The fixture had no published port and was removed after verification.
The installed preview still uses its current guest.

The SwiftUI detail sheet adds a Tools tab beside MCP and Skills. The pinned
browser is the reference for assignment, enabled status, and the recording
dependency. Lazyweb's Krea AI access dialog and Cresta agent editor informed
the per-row control and nearby status. Use localized status and dependency
labels. This tab displays stable keys, while catalog descriptions are a
separate localization task. Confirm each save against a fresh catalog and
offer explicit reload on an ambiguous result. Refresh the agent card count.

The signed native review showed the Worker card count change from 12 to 11
when removing `record_fact`, kept the change when reopening details, and
restored 12 after adding it back. Both traffic tool rows were disabled.
The separate API exercise used two boots of one disk and retained the change
across restart. The isolated pinned browser API produced the same membership
change. Interactive browser UI comparison remains open.

The first native fixture boot hit a guest kernel panic before setup.
The retry on a fresh disk completed and stopped with its temporary session
removed. The signed Release preview now bundles cloud7. The synthetic cloud
probe passed four model lists, four streaming sessions, and cancellation.
The broader boot reliability gate remains open.
[Verification receipt](../evidence/agents/tool-binding-cloud7.json)
