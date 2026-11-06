# Agent prompt details verification

From the signed-in Agents catalog, select a card to open a native sheet. The Prompt tab shows variables and the literal current prompt, and each saved version expands to show its original text. The Wrap-up tab shows the active normal prompt and effective round limit. The separate task-timeout prompt appears only when the guest reports support. When a custom wrap-up is active, the built-in text remains available for comparison.

The native UI uses the authenticated `GET /api/agents/{key}` contract from browser baseline `e75ae371ad777ffd1eecdd28d2781a6519b05591`. The disposable pinned Docker reference returned 401 before authentication and 200 after authentication for both the built-in Worker and custom Reporter. It returned four and two prompt variables respectively, one saved version each, a default limit of ten rounds, and task-timeout support for Worker only. No agent was executed.

Use `swift test --filter 'AgentPromptDetailsTests|AgentCatalogTests'` to test route validation, response identity, literal text, defaults, seeded label localization, error status, and cancellation. For UI design, the frozen browser drawer provided the content order. Lazyweb's Hygraph and Front audit history references reinforced keeping metadata separate from expanded content.

The signed native review used a fresh isolated Linux VM. In Japanese, Worker displayed four variables, one expandable version, and a task-timeout wrap-up. Escape returned to the catalog. In English, Reporter displayed two variables and one version; its wrap-up showed ten rounds and omitted the task-timeout section. The disposable rendered browser was pinned by its health response and reached the login form, which required terms confirmation for this fresh session. No authenticated browser screen was compared. All disposable services stopped and temporary native authentication was removed.

Local verification passed 1,060 Swift tests with one existing skip, 195 guest artifact tests, the release build, generated localizations and strict signature verification of the updated local preview. Hosted CI was skipped under the quota policy.

English and Japanese localize native controls and known variable descriptions. Stored prompts, version notes, and variable examples are shown verbatim, including the Chinese and Korean text in the pinned seed prompts. Editing, version diff and restore, model and permission settings, and paired rendered browser UI acceptance remain open.
