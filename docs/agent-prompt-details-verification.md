# Agent prompt details verification

From the signed-in Agents catalog, select a card to open a native sheet. The Prompt tab shows variables and the literal current prompt, and each saved version expands to show its original text. The Wrap-up tab shows the active normal prompt and effective round limit. The separate task-timeout prompt appears only when the guest reports support. When a custom wrap-up is active, the built-in text remains available for comparison.

The native UI uses the authenticated `GET /api/agents/{key}` contract from browser baseline `e75ae371ad777ffd1eecdd28d2781a6519b05591`. The disposable pinned Docker reference returned 401 before authentication and 200 after authentication for both the built-in Worker and custom Reporter. It returned four and two prompt variables respectively, one saved version each, a default limit of ten rounds, and task-timeout support for Worker only. No agent was executed.

Use `swift test --filter 'AgentPromptDetailsTests|AgentCatalogTests'` to test route validation, response identity, literal text, defaults, seeded label localization, error status, and cancellation. For UI design, the frozen browser drawer provided the content order. Lazyweb's Hygraph and Front audit history references reinforced keeping metadata separate from expanded content.

The signed native review used a fresh isolated Linux VM. In Japanese, Worker displayed four variables, one expandable version, and a task-timeout wrap-up. Escape returned to the catalog. In English, Reporter displayed two variables and one version; its wrap-up showed ten rounds and omitted the task-timeout section. The disposable rendered browser was pinned by its health response and reached the login form, which required terms confirmation for this fresh session. No authenticated browser screen was compared. All disposable services stopped and temporary native authentication was removed.

Local verification passed 1,060 Swift tests with one existing skip, 195 guest artifact tests, the release build, generated localizations and strict signature verification of the updated local preview. Hosted CI was skipped under the quota policy.

English and Japanese localize native controls and known variable descriptions. Stored prompts, version notes, and variable examples are shown verbatim, including the Chinese and Korean text in the pinned seed prompts. Editing, version diff and restore, model and permission settings, and paired rendered browser UI acceptance remain open.

The managed backend now includes optional version authorship from the
existing `agent_prompts.updated_by` column. The app translates the two
known default and restore notes only when their stored author is
`system`. The original note and prompt body remain literal for editing
and inspection. Missing authorship, arbitrary system notes and identical
user-authored notes retain the original display. The fixed browser
source remains the comparison baseline. Lazyweb's adjacent Notion
history example supported keeping the revision note next to the current
revision marker. The new guest and updated native screen still require
paired runtime verification.

On the signed cloud9 review app (guest manifest SHA256
`9c38d268d350e7ab4e265ca32d686c529d8e09e5facfc2c69581f31589b768d8`),
Worker displayed the localized built-in note. Restoring the default
created v2 with the localized restoration note and retained v1.
Switching to English showed both English labels, with the visible
prompt value unchanged. The disposable pinned browser showed the
Chinese notes for Worker v1 and restored v2 in Japanese mode.
The native test completed setup, restart and Keychain cleanup. Its
separate stop-during-startup check timed out before guest initialization
on a third boot. This run therefore records the live UI comparison
without passing the full native diagnostic suite.
