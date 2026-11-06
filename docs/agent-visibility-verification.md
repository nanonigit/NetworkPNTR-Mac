# Agent MCP and skill visibility

The native editor has separate MCP and Skill tabs. It reads catalog entries and the current agent's memberships. Every checkbox writes one assignment through the fixed guest's resource-specific API using the agent ID from its detail. The editor reads the membership back before reflecting the result. On a failed or uncertain change, it requires a reload. Closing the sheet after a change reloads the catalog counts.

The frozen browser editor replaces both lists through its agent-level API. The Mac uses the same pinned guest's single-item endpoints, which the browser uses in the resource settings, to avoid overwriting unrelated memberships. The Conduktor, Square and Hygraph results from Lazyweb informed grouping rows and status together.

The disposable pinned Docker reference at `e75ae371ad777ffd1eecdd28d2781a6519b05591` verified adding and removing a disabled MCP fixture, removing the `api-recon` skill, and preserving the other assignments. After restarting the reference backend against the same database, the removed `api-recon` membership was visible again. The pinned toggle deletes the row, and startup inserts the default row when absent. Restart persistence for removal of seeded defaults therefore remains open. No agent or MCP process was started by the exercise.

The signed Mac app ran against a disposable Linux VM. Worker showed the Browser MCP and ScopeSentry rows. Assigning and clearing the disabled Browser row left the ScopeSentry checkbox clear. Removing api-recon cleared its checkbox and closing the detail refreshed the Worker card to zero MCP and skill assignments. The Mac VM was tested through readback and sheet dismissal. The restart finding was reproduced on the frozen Docker backend. The shipped api-recon description is displayed in Chinese and is a remaining localization item.

Run `swift test --filter AgentVisibilityEditorTests` for payload, readback, and error behavior. The built-in tool and trigger bindings, standalone MCP and Skill configuration, restart persistence, and authenticated browser GUI comparison remain open.

Local checks passed 1,084 Swift tests with one existing skip and 195 guest artifact tests. The release build and refreshed preview signature passed. The diagnostic VM stopped and its temporary state and Keychain item were removed. GitHub Actions was skipped under the quota policy.
