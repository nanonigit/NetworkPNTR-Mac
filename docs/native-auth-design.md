# Native backend and authentication integration

This continues P2/P3 without relaxing final parity. Previous goal turn made authoritative progress: real guest/backend persistence and five reference contracts passed and commit f524c0d was published with green CI. Native workflow gates remain open.

## Requirements and UI baseline

Bundle the real pinned backend guest in the app and automatically start it; no Docker, Python, browser or shell command is called by application runtime. Keep state in a private application-support directory, separate from browser data. Provide actual first-run setup, login, backend-unavailable/retry and logout flows. Use secure password inputs, confirmation, fixed ARTEX username, inline errors and a visible busy state. Preserve backend authentication; never turn a 503 or transport failure into an uninitialized database.

Browser sources: web/src/app/(auth)/setup/page.tsx and login/page.tsx at the pinned baseline. Setup checks status, accepts a setup token, requires matching passwords of at least eight UTF-16 code units in the browser (server requires eight Unicode scalars), and enforces the server's 72 UTF-8 byte limit. Login includes a terms checkbox and a viewable eight-section terms dialog. Native Unicode validation uses server semantics and documents this difference. The managed app passes its per-boot setup credential internally rather than requiring a console copy; no credential is displayed or logged. No browser password/session is imported.

Lazyweb secondary search `desktop login password settings` (desktop, 2026-10-22) returned Canva siteId 242519, Frontegg 251323, Notion 241065. Returned descriptions support stable left navigation, explicit password labels and a focused form/modal; these are metadata references, not claimed screenshot inspection. SwiftUI macOS patterns govern native split views, semantic colors, keyboard submission and scene state. Upstream ARTEX controls and errors remain authoritative. No hosted report or approval workflow is required to implement the authorized work.

## Boundaries and ownership

NetworkPNTRCore: bounded HTTP response/request framing, typed JSON auth client, observable authentication session, secure-session vault, app-managed runtime paths and coordinator. VMController remains responsible only for VM lifecycle and vsock transport. Auth state is distinct from Linux readiness. RootView owns sidebar selection; the app owns its runtime and auth session. Passwords are view-local and cleared when authentication changes or the form leaves view; failed validation preserves input to match the browser. Store only the JWT in macOS Keychain, scoped to this app's dedicated guest; credentials remain out of UserDefaults/files/logs.

First integrate bounded JSON exchanges over the already authenticated vsock stream. Support Content-Length, connection-close and chunked JSON responses, with strict size/framing limits. This client is for finite JSON APIs; SSE/WebSocket, binary exports and cancellation need their own transport gates and are not counted as complete here. The full goal still includes all browser workflows.

## Test plan

A1: parse real HTTP framing, chunked bodies/trailers, truncated/ambiguous/oversized responses; reject request header/path injection.
A2: status failure stays unavailable; first run needs setup; missing/invalid saved JWT goes to login; database errors preserve saved session material.
A3: password mismatch/length/UTF-8 limit and terms validation prevent network calls; setup/login use real endpoints and fixed username; password is never persisted; logout clears the token.
A4: Keychain errors are visible, not success. Restore a valid saved token only after a protected endpoint verifies it. Use injected in-memory vaults and deterministic fake API responses for state-machine tests; real signed app harness separately tests actual guest/auth and a unique temporary Keychain item.
A5: signed .app auto-boots bundled guest without Docker calls, performs setup/auth/persistence through production services, shows native status/form/error content. A developer harness is programmatic evidence only; external native clicks and screenshot comparison remain a separate pending gate if the native connector is unavailable.

## Direct-root diagnostic profile and network evidence

Optional manifest `bootMode: rootDisk` selects a built-in-driver kernel with a read-only root disk and no initial RAM disk. Unknown modes or missing system disks fail validation. The default portable Alpine build recipe remains unchanged while instability is investigated. An installed LinuxKit kernel is used only as a private local diagnostic input; it is not a distributed dependency. Check zero hardware NICs, zero UP non-loopback devices and zero non-loopback routes inside the guest before starting services and again at readiness. Inactive fallback virtual devices are recorded, not mistaken for external connectivity. Keep framework zero-NIC/share assertions.

Task order: implement boot-mode invariants and negative tests; collect real boot/persistence/error evidence; repeat native setup/Keychain/login/shutdown diagnostics; compare normalized API fixtures with the pinned browser; retain pending native interaction/visual and portable/source-license gates. Backend failure diagnostics emit a fixed category whitelist and exit code, never raw log lines.

Manifest `cpuCount` accepts only 1 or 2 and defaults to 2; both manifest loading and VM configuration enforce the budget. Diagnostics record the actual configured value. This supports controlled scheduling experiments without changing source or permitting arbitrary resource exhaustion.
