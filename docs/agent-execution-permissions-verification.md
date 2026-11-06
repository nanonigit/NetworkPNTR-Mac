# Agent Web search and interactive shell preferences

The prompt settings display both switches for the same agents as the frozen browser. The Web search switch reflects the saved agent preference and remains disabled when the guest-wide switch is off or unavailable. Shell uses its own saved preference. The Mac only sends edited, visible fields to the authenticated agent config endpoint. It reads the global switch again before a Web search write. If it closes, the editor restores that field to the saved value and keeps the other edits.

In the disposable Docker reference pinned to `e75ae371ad777ffd1eecdd28d2781a6519b05591`, a partial update stored the Web search preference and disabled the shell. Turning the global switch off retained the agent preference. Limits and the model binding retained their saved values. The fixture tested settings only. The frozen browser defines visibility and gating. Square and Workflowy settings references from Lazyweb informed placing the global status by the switch.

The signed Mac app used a disposable VM with the global Web search switch off. Goals hid both controls. Worker showed Web search disabled and accepted a change from an enabled shell to a disabled shell. After reopening the agent, the shell preference was off and the model and execution limits matched their prior values. The enabled Web search write was checked with the pinned API and Swift transport tests. The Mac System Settings screen is still pending.

Run `swift test --filter AgentExecutionPermissionsTests` for changed-field writes, a gate closing during editing, unavailable settings and hidden fields. Tool bindings, triggers, and authenticated browser GUI comparison remain open.

Local verification passed 1,081 Swift tests with one existing skip and 195 guest artifact tests. The release build and refreshed preview signature passed. Both diagnostic VMs stopped and their temporary state and Keychain items were removed. GitHub Actions was skipped under the quota policy.
