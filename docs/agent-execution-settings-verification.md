# Agent model and execution limits

The prompt tab offers model binding or inheritance for every agent. The execution limits appear on the same agents as the frozen browser, with zero meaning unlimited. The form accepts nonnegative integers in the database range. It displays a saved profile ID if its option is unavailable.

The authenticated `PUT /api/agents/{key}/config` sends the changed fields. An inherited model sends explicit null when clearing a binding. Untouched fields are omitted. Readback verifies the requested values and rebases untouched fields on the guest's latest state while retaining other drafts. If the write result is uncertain, the editor requires a read before retry.

The disposable Docker reference at `e75ae371ad777ffd1eecdd28d2781a6519b05591` bound a synthetic profile, saved 12 turns and 45 seconds, then restored inheritance with a null binding. Both limits retained their saved values. A profile without a key was rejected by the guest, so the fixture used an inert placeholder and the reserved example.invalid domain. No live model or agent ran. The frozen editor defines visibility and priority. The Cursor settings reference from Lazyweb informed the model picker layout.

On the signed Mac app and isolated Linux VM, Goals displayed the model picker without limit fields. Worker accepted the fixture model and limits of 12 turns and 45 seconds. After restoring inheritance and reopening the editor, both limits appeared at their saved values. The VM stopped and the temporary Keychain item and state were removed.

Run `swift test --filter AgentExecutionSettingsTests` for request shape, omitted fields, validation, and partial readback. Web search and shell toggles, tool bindings, triggers, and authenticated browser GUI comparison remain open.

Local verification passed 1,078 Swift tests with one existing skip and 195 guest artifact tests. The release build and refreshed preview signature passed. GitHub Actions was skipped under the quota policy.
