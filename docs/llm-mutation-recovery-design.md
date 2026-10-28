# LLM mutation ownership and recovery

## Requirements

Prevent duplicate profile creation and ambiguous repeats after any of six LLM mutation families fails after transport handoff. Preserve local validation and existing wire contracts. Before handoff, cancellation or departing the screen must send nothing and must not claim uncertain server effects. After handoff, an unconfirmed response pauses all writes. Reloading is read-only and does not resolve uncertainty. Require a successful full reload after the uncertain write settles, then explicit acknowledgement with the displayed revision before allowing new writes. Leaving/reentering must not release an unsettled write gate or accept stale reads. A confirmed response remains confirmed when only its subsequent reload fails. No live provider keys, automatic retry or agent host commands.

## Design and UI evidence

Use internal service onDispatch overloads for six mutations; original public methods retain their contracts. An actor-owned write ticket records activity, handoff and confirmed response; a private acquisition guard prevents Observation reentry during ticket assignment. Shared read tickets own full reload/pool refresh and revoke intermediate/late responses on stop. Unknown revision changes only for a newly uncertain ticket; full reload must start after that ticket terminates. A captured acknowledgement revision must match both unknown and reviewed revisions.

Use one bilingual recovery panel in settings, editor and rotation sheet, outside disabled mutation forms. It explains possible server-side completion, offers Reload, then a separate “I reviewed the current settings — resume changes” action. Read access remains available; acknowledgement never resends. Preserve editor contents and existing profile/list/retry controls; profile/new/edit navigation remains accessible. Block writes at the store as well as visible controls. Settings disappearance calls stop; its task resumes and reloads. Probe/editor view-task ownership is a separate pending checkpoint, not claimed by this repair.

Lazyweb searches `settings save error recovery` and `error banner` (desktop, 2026-10-28) returned weak adjacent metadata: DuckDuckGo11407 settings save/load, Ring5165 inline error banner, VaynerX159802 error with explicit recovery actions. These are metadata, not inspected screenshots or acceptance evidence. Use only the inline feedback/action distinction; do not copy dismiss-only or blind retry behavior. Primary baseline remains pinned e75ae371ad777ffd1eecdd28d2781a6519b05591 LLM page and existing native control inventory.

## Tasks and acceptance

1. RED for new ownership/recovery API and controlled pre/post-handoff, stop/resume, stale read, local-invalid and acknowledgement cases.
2. Implement service callbacks and store tickets; exercise all six mutation families, Observation reentry, busy retention, known-save/reload failure, full reload vs pool-only review.
3. Add recovery panel to all three surfaces and exact en/ja matrix; preserve arbitrary CJK/custom values.
4. Independent review, full regression, coverage, signed build and exact-head CI. Actual native/browser clicks, keyboard, resizing and accessibility remain pending manual unlock; software checks cannot close that gate.

## Navigation ownership addendum

RootView's conditional destination previously constructed a new LLMStore inside each LLMSettingsView. Store stop/resume unit tests alone cannot prove real navigation ownership. Introduce a window-owned LLMWorkspace holding one store per authentication-session object. Same-owner navigation reuses the exact store and unknown revision; a different session or auth loss stops and releases it. The view receives the retained store. Add coordinator tests before implementation. This is in-memory ownership, not persistence across app termination; crash/restart uncertainty recovery remains unproven.
