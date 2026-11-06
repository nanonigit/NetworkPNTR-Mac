# Restore a built-in agent prompt

The Agents prompt editor offers Restore default for built-in agents. The confirmation describes the new saved version and explains when an unsaved draft will be replaced. The editor sends an authenticated `POST /api/agents/{key}/prompt/reset` with an empty JSON object and shows the version acknowledged by the guest. It adopts the current saved prompt after the acknowledged version appears in history. If acknowledgement is missing or the history is stale, the draft stays available and the editor requires a history reload before another mutation.

The browser reference is fixed at `e75ae371ad777ffd1eecdd28d2781a6519b05591`. In the disposable reference, saving a modified Worker prompt created v2 and restoring created v3 with the original template. Versions v1 and v2 stayed in history. Reporter returned HTTP 400 and kept its history. The native button uses the browser's wording. The Productboard restoration dialog returned by Lazyweb informed the confirmation layout.

The signed native build used a disposable Linux VM. Reporter had no restore control. After saving the modified Worker template as v2, cancelling the restore kept the unsaved draft and the two saved versions. Confirming restored the initial template prefix and made v3 current. The history displayed v3, v2 and v1. The fixture VM stopped and its temporary Keychain item and VM state were removed. This compared the native UI with the pinned API.

Run `swift test --filter AgentPromptEditorTests` for request shape, history retention, stale history recovery, and rejected restore. Markdown presentation, agent settings and bindings, and authenticated browser GUI comparison remain open.

Local checks passed 1,072 Swift tests, with one existing skip, and 195 guest artifact tests. The release build and signature verification of the refreshed preview passed. Hosted CI was skipped under the quota policy.
