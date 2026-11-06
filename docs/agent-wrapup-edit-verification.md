# Edit agent wrap-up settings

The wrap-up tab edits the normal prompt and round limit and, for supported agents, the task-timeout pair. Empty text and zero rounds select the guest defaults. The Mac form validates nonnegative whole numbers within the database integer range. The two sections retain separate drafts, including when the user saves the main prompt or the other section.

The editor uses authenticated `PUT /api/agents/{key}/wrapup` and `PUT /api/agents/{key}/wrapup/task-timeout`, and each corresponding reset uses POST. The guest stores the normal prompt and round count in separate writes. The Mac checks both persisted fields before reporting success and requires a reload after an uncertain response. A reset asks for confirmation.

The disposable Docker reference at `e75ae371ad777ffd1eecdd28d2781a6519b05591` stored both prompts verbatim at 4 and 6 rounds. Resetting the task-timeout settings restored its empty and zero overrides while the normal values remained set. The normal reset then cleared its own overrides. The frozen editor defines the two sections. Lazyweb settings results informed placing each pair of controls with its own save action.

The signed Mac app used a disposable Linux VM. It blocked a negative round limit, saved normal and task-timeout settings at 4 and 6 rounds, and preserved the unsaved task-timeout draft during the normal save. Resetting task timeout cleared its override and displayed zero while normal still showed the 4-round override. Resetting normal then cleared that override. The native UI behavior matched the pinned API in this fixture.

Run `swift test --filter AgentWrapUpEditorTests` for payload, verification, preservation of other drafts, and partial persistence. Model and tool bindings, trigger settings, and authenticated browser GUI comparison remain open.

Local checks passed 1,075 Swift tests, with one existing skip, and 195 guest artifact tests. The release build and signature verification of the refreshed preview passed. The disposable VM, its temporary Keychain item and state, and the reference Docker services were cleaned up. Hosted CI was skipped under the quota policy.
