# F5e2 evidence edit, remove, order and recovery checkpoint

Historical F5e2 checkpoint at6c2eba9. The picker UI described as pending here is implemented as software in captured-picker-ui-verification.md; its real runtime/visual gates remain open.

The native evidence list now provides role/note editing, confirmed removal and adjacent up/down ordering with captured version/membership. Dialogs and draft bindings carry their own UUIDs. Unknown roles require explicit supported-role selection. Note FEFF/NFD/CJK bytes remain intact. Inherited evidence cannot mutate. Confirmed updates re-read parent finding/report metadata. Conflicts, post-dispatch cancellation and lost ownership remain uncertain; refresh does not acknowledge or replay them.

The authenticated window retains the evidence store and recovery target/context across sheet closes. Ordinary finding writes share its pending/unknown gate. A parent recovery action can reopen the exact affected finding after filters changed. A fresh summary and explicit acknowledgment are required to allow further writes. Delayed old-sheet disappearance and old-session mutation cleanup cannot stop a replacement owner. Raw evidence is cleared on departure; logout resets session state.

Capture timestamps now use the same Unix-second semantics as frozen traffic.go/browser code. The numeric epoch regression failed three assertions before the fix; earlier millisecond-shaped test data was corrected. This is source-contract parity, not screenshot/date-locale acceptance.

## Verification

- Missing action contracts b9dd4f6 ->4eade81(31 cases). Missing UI/captured-render-version/cancellation contracts5f5542c ->6b8d4fb(75 related). Actual shared-owner regression a81c4d0 failed nine assertions across two cases in14 action tests ->26c540b(77 related GREEN). Timestamp REDf72bcab ->bda51bd(23 workspace cases). Bilingual RCA is in bugs/evidence-mutations.
- Full coverage-enabled Swift suite:804 cases,803 pass,one existing external accessibility skip,zero failures (19 probe,228 app,557 core). Full GuestArtifactTests155 pass.
- Full-run LLVM whole-file line coverage: FindingTrafficActions121/134(90.30%), ActionBindings24/24(100%), ActionView84/103(81.55%), Workspace302/305(99.02%), Presentation13/13(100%), ScreenModel206/215(95.81%), TrafficStore173/175(98.86%). These scoped counts are not all-product or real UI coverage.
- Offscreen action dialogs render in en/ja; current list/viewer regressions also cover light/dark. Fixed fake HTTP transport and held continuations prove request fields, version/order, cancellation, stale identities, uncertainty and metadata-read ownership. They do not prove backend mutation effects or persistence with real captured data.
- Localization generation, shell syntax and frozen baseline inventory21 navigation/27 page routes/243 handlers are checked. Native workflow parity remains pending. No dependency was added; the project has no external SwiftPM package dependency requiring a package audit for this change.

The local NetworkPNTR Mac bundle was rebuilt successfully with script/build_and_run.sh --build-only; codesign --verify --strict passed after the build process terminated. This verifies the packaged local bundle, not installation, notarization, launch or guest-backed UI acceptance.

## Remaining acceptance

The captured-traffic picker UI/add operation remains unimplemented; existing typed picker state/contracts are prerequisites. Exercise actual nonempty captured traffic with edit/remove/reorder/bind, conflicts/unknown outcomes and restart persistence in both the managed guest and frozen reference. Compare detailed previews/raw-byte offsets/binary/truncation and original downloads. Actual save panel, keyboard/VoiceOver, multiwindow and native/browser screenshots remain unverified pending the deferred manual unlock. Keep the full21 workflows, isolated VM, source-kernel reliability/default promotion, clean installation/signing/notarization/release, four cloud providers and investigation harness goals intact.

Hosted CI remains unverified under the exhausted Actions quota. All our publication HEADs contain [skip ci]; no dispatch/rerun, billing or network policy change was made for this checkpoint. Local bundle build/signing results are recorded with publication; neither that nor offscreen tests implies installation or a completed app.
