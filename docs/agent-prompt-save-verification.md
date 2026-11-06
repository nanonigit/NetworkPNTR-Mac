# Agent prompt version saving

The Mac editor sends the draft as an authenticated `PUT /api/agents/{key}/prompt` with the literal template and an empty note, matching the frozen browser editor. Each successful save appends a version. The guest validates the Go template and allowed variable names. A rejected draft remains editable. Loading a historical version only changes the draft. Closing or replacing a dirty draft requests confirmation.

The editor serializes a save and its history refresh. A positive response shows the version number even if the immediate history read is stale. An uncertain write requires an explicit history reload before another save. The editor never retries a write automatically, and does not report an unacknowledged write as its own success. An explicit save requires a changed draft to avoid creating redundant versions.

In a disposable Docker reference pinned to `e75ae371ad777ffd1eecdd28d2781a6519b05591`, Reporter rejected an unknown variable with HTTP 400 and kept its history. It accepted the edited template as v2, preserved leading spaces and line endings, and retained the original version. No agent was executed. The browser source provided the edit and history flow. Lazyweb's Notion and Canva references informed keeping past versions reachable from the editor.

In the signed Mac review build, an isolated Linux VM rejected the same invalid fixture while retaining the draft and v1. The corrected draft created v2. Both versions appeared in history. Loading v1 replaced only the draft. Closing showed a discard prompt. After discarding and reopening, the UI showed v2 as current and displayed the saved text with its leading spaces. This compared a native GUI workflow with the pinned browser API, while the authenticated rendered browser GUI comparison remains open.

Run `swift test --filter AgentPromptEditorTests` for byte preservation, rejection, interrupted writes, stale history, and overlapping actions. Render preview, version diffs, default reset, editor settings and bindings, and paired authenticated browser GUI acceptance remain separate gates.

Local verification passed 1,065 Swift tests with one existing skip, 195 guest artifact tests, the release build, the localization resource check, and strict signature verification of the refreshed preview. The disposable VM was stopped, its temporary Keychain item and state were removed, and the reference Docker services were removed. GitHub Actions was skipped under the quota policy.
