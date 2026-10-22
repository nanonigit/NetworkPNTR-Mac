# Dashboard implementation and comparison checkpoint

Status: **in progress**. The dashboard is connected to actual VM services; whole-screen and whole-product acceptance remain open.

## Verified scope

The native screen includes the five summary cards, old/ledger sources, all/per-profile selections, all five day ranges, raw three-series chart, precise date selector and accessible data table, activity/findings/tasks, asset distribution, sampled traffic and system/approval sections. It polls tasks, fast sources and slow sources independently, retains last successful data on failure, and rejects malformed/overflowing responses. Task/findings/approval links lead to explicit pending destinations; those features are not accepted through this dashboard.

42 Swift tests pass, including 12 dashboard tests (seven metrics and five service/store tests). They cover default/missing/duplicate profiles, conversations versus task counts, old/ledger semantics, local-calendar DST cutoff, empty data, limits, numeric overflow/nonfinite/fractional counts, all 11 visible API routes, null versus missing/wrong shape, HTTP failures, retained data, no task-request overlap, cancellation and old-generation responses. 14 existing Python guest tests pass. These counts do not establish an 80% coverage claim.

The signed DEBUG app's isolated diagnostic fixture creates a fresh private disk and temporary Keychain item. Only when `--dashboard-diagnostics` is explicitly present does it read the developer's fixed `script/dashboard_seed_guest.py` and send it through ARTEX's existing authenticated custom-tool test API. The script requires Linux/aarch64/UID 1000 and a loopback artex database, passes the database password through child environment only, and refuses nonempty tables. It inserts terminal tasks, local history, two findings, three assets, a conversation, usage rows and four pending approvals. No AI task or external target is launched. No new guest-to-host command bridge or production fixture UI exists. The seed hook is excluded from release compilation.

After normal VM restart, the production native service reads all 11 endpoints. The fixture verifies 12 token scenarios (old/ledger × all/two profiles × 7/30 days), sorting, severity/assets, approvals and system flags. `evidence/dashboard/comparison.json` records equality with both an independent JavaScript translation of the pinned browser calculations and a disposable pinned browser backend using the same SQL. The development reference has an internal network, no published ports/host mounts and is removed afterwards. The user's existing browser database is untouched.

External CUA interaction verified source switching (215 old versus 1171 ledger tokens), 7-day range, secondary-profile selection (70 tokens), rendered lower panels, task-ID routing and Escape dismissal, Command-R preserving selection, and the approval link. Date-picker/table interaction exposed the hover issue below; the rebuilt app confirms October 20 displays input 50/output 10/cache 5, and its data table agrees. The restored activity link also reaches Tasks. Native PNGs are actual external screenshots. The live browser PNG/control inventory are layout references with its existing empty data; they are **not an identical-data visual comparison**. API equality does not establish final UI/UX parity.

## Investigation and recurrence prevention

Timeline: write failing metrics tests → implement/green → failing service/store tests → implement/green → real guest seed/restart → independent/reference comparison → native interactions → UI corrections/recheck.

The first reference comparison showed empty tasks/activity despite seeded PostgreSQL rows. Cause: manager task state is loaded at startup. Profile deletion only synchronizes already loaded tasks; it does not load missing ones. Repair: restart only the disposable reference application after seeding and log in again, preserving its separate PostgreSQL container. The repeated comparison passes; fixtures now require nonempty endpoint results.

The date picker selected October 20 while the detail text still showed October 21. Five Whys: the hover date won over explicit selection; the mouse/selection paths maintained separate state; popup interaction did not reliably clear hover state; earlier tests covered arithmetic but not this interaction; therefore UI acceptance must exercise both pointer and explicit keyboard-accessible selectors. Repair: explicit selected date takes precedence over hover; clearing selection restores hover behavior. Source review also corrected the `mainagent` color mapping and restored the browser's activity-to-tasks link. Fishbone: data/API (manager cache), UI state (hover precedence), test method (unit versus external UI), environment (intermittent CUA and diagnostic kernel). Do not attribute these failures to a cloud provider or VM kernel.

## Reproduction

1. Prepare the verified diagnostic guest profile described in `bugs/guest-boot-investigation.md`.
2. Build with `ARTEX_MAC_GUEST_BUILD_DIR=/path/to/profile script/build_and_run.sh --build-only`.
3. Run `dist/ARTEX Mac.app/Contents/MacOS/ArtexMac --native-diagnostics /private/fresh/fixture --dashboard-diagnostics --native-review`.
4. Run `python3 script/compare_dashboard.py /private/fresh/fixture evidence/dashboard` after the contract JSON exists. Node.js and Docker are developer comparison dependencies only.
5. Use the native UI for review. Create the fixed `native-review-finish` marker in the fixture directory to resume logout/Keychain cleanup/shutdown. Retain raw state/logs only in ignored `evidence/local/`.

The final UI review hold reached its fixed 15-minute timeout after the interrupted review; its terminal result is recorded separately and is not counted as a full diagnostic pass. Two earlier fixture runs completed normal cleanup. A subsequent noninteractive run passed on the current build, including temporary Keychain deletion, normal VM shutdown and stop during boot. Release compilation passes and its symbol table contains neither diagnostic harness. External captures still contain a floating macOS “Passwords…” suggestion absent from the app AX tree; clearing auth focus on transition/disappearance did not remove it from the capture. Its ownership/capture behavior remains unresolved and visual acceptance stays open.

## Open gates

The runtime still uses a one-vCPU diagnostic kernel profile, not a reproducible licensed release artifact. Traffic capture is disabled by both fixture runtimes, so populated traffic is covered by unit fixtures only. Controlled cloud egress/positive LLM calls, real streaming, exact populated browser/native visual pairs, live UI stale/error/empty cases, resize/light mode and full keyboard/accessibility tests remain open. The detail/task/chat and remaining product features remain unimplemented. The dashboard catalog row stays `in_progress`; no feature is marked accepted.
