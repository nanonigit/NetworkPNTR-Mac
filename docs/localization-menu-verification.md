# Native menu title boundary — L9 (partial integration)

## Reproduce and collect

Root's SwiftUI locale did not provide a boundary for existing AppKit menu titles. The app only removed New Item commands; standard menus retained their own titles/actions. The installed AppKit interop skill recommends a narrow hook with SwiftUI owning language state. Local SDK headers confirm NSMenu.didBeginTrackingNotification and NSApplication's registered window/help/services menu properties. Lazyweb `desktop application menu bar` returned weak adjacent Cluely download-page metadata(.340), not inspected menu evidence.

`8d65447` is intended compile-time RED for missing menu keys/adapter; `bab27b4` passes the first5tests (4synthetic AppKit cases +1catalog). During the first GREEN attempt, a test incorrectly expected title=Copy after setting attributedTitle; AppKit itself had already changed title. The oracle was corrected to snapshot the pre-apply title, not counted as a product bug. `b97a197` adds action/header coverage and executes a real RED with one Close Window title failure; `b757992` adds only the three close-title aliases and passes7focused cases.

## Analyze

5 Whys: menus do not follow language → existing AppKit objects are outside the view environment → no title adapter observes app language → rebuilding commands risks responder/shortcut changes → require a title-only boundary with known identity/aliases. Fishbone: native action identity, static versus dynamic titles, registered submenu identity, unknown/custom/attributed content, observer lifecycle, SwiftUI menu replacement, native validation ordering. Timeline: source/SDK/skill/Lazyweb → requirements/design/tasks → intended RED → adapter/resources/AppDelegate hooks → oracle correction/GREEN5 → all22actions/header/Close alias RED1 → minimal alias fix/GREEN7 → reviewer/full tests/coverage/signed resources.

## Repair and invariants

The adapter retitles recognized native selector+known static-title pairs in place. Root headers additionally require a known label and native anchor; registered window/help/services submenu identities are authoritative. Existing menus/items/targets/actions/key equivalents/modifiers/enablement/state/identifiers/represented objects/tooltips are retained. Unknown selectors/custom labels, attributed/custom-view items, dynamic window/service names are preserved. Chinese/Korean strings in the alias table are recognition inputs, not supported output languages or blanket text translation.

One selector-based tracking observer resolves the current mainMenu each time. Language changes apply immediately; repeated start does not add observers; stop removes the observer idempotently. AppDelegate owns the bridge, forwards the shared preference on appearance/change, refreshes after launch, and stops on termination. No menu is rebuilt and no command is invoked by localization. No timer, global language override, new persistence, VM request or view identity is added. applicationShouldTerminate is byte-exactly unchanged; language preferences, RootView and both runtime source files are unchanged in this phase.

## Verification and limits

275Swift cases:274pass, one existing AXskip;52Python pass. AppMenuLocalizer/bridge file line coverage100%, regions96%, exported from the Mac test executable because SwiftPM's final default JSON contained Core coverage only. The reviewer approved metadata preservation, observer ownership, all22supported selector mappings and header guards. Final signed build/strict signature/exporter pass; all28menu strings per locale match the matrix, including opaque application-name formatting. Evidence: `evidence/localization/menu-*`.

These are undisplayed synthetic NSMenu tests, not inspection or control of the user's app. No new runtime/VM fixture, native UI interaction, screenshot or cloud request occurred while unlock is deferred. Actual first-opening/tracking order, SwiftUI-owned selector shapes, responder validation, shortcuts/undo/copy/quit dispatch and menu updates after framework regeneration remain unverified. Dynamic Undo operation text, Exit Full Screen and stateful Show/Hide titles are outside this static alias set and remain unchanged. Existing OS titles may therefore remain in another language; OS menu localization is not complete. This boundary must be extended only with evidence and verified after unlock. Backend/provenance, remaining18screens and full21feature/runtime/distribution/language acceptance remain open.
