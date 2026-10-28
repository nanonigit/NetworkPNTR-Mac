# F5c2 captured picker state verification

Owned picker state is implemented; native controls/window/detail wiring and full-byte export are still pending. Cross-page selection and captured preview now share a parent owner, and binding revalidates the child at transport handoff. Public parent mutation routes retain their contract.

- Missing-owner RED e1ba09a -> behavioral RED b1f4d5f:14 cases/seven failed assertions exposing the shared read-acquisition gate. GREENfe8d687 passes14.
- Publication/lifecycle RED ca191b7:21 cases/eight failed assertions. GREENed3f6b7 passes21 (18 picker/three shared-read cases).
- Combined captured/bound traffic/read regression:50 pass.
- Full Swift:726 cases,725 pass, one existing explicit external-AX skip, zero failures.
- Python guest/tooling:123 pass.
- Full-suite line coverage: CapturedTrafficPickerStore206/208 (99.04%), FindingReadState56/56 (100%), FindingTrafficStore168/170 (98.82%). These are software-state results, not actual UI/VM acceptance.
- Independent read-only review found restored selections after synchronous close. The regression, preview/lifecycle counterparts and shared-read fix were reproduced and reviewed; no unresolved reported blocker remains in this scope.

Synthetic tests exercise byte-exact NFC/NFD identities, already-bound rows, page/filter selection retention, stale/read failure, reverse catalog and preview replies, inherited/legacy read-only targets, bind receipts/conflicts, cancellation and stop/resume gates. Parent/child busy callbacks cause zero-dispatch departure. A confirmed parent receipt can remain known while a departed child returns discarded; a cancelled dispatched write remains uncertain. Reads/acknowledgement never replay a bind. Callbacks for cleanup tests are armed after dispatch to avoid equal-value preflight notification differences.

No actual provider, backend, keys, guest writes or host agent commands were used. This phase adds no product layout or strings. Localization export and frozen inventory checks pass:21 navigation features/27 routes/243 handlers; native workflow parity remains pending. Prior CI40637957743 was account-blocked before testing by payment/spending-limit annotation; new-code CI remains a required unverified gate until a successful current run exists. Native picker/viewer/editor controls, full-byte download/export, actual nonempty isolated guest/browser persistence, unlocked keyboard/VoiceOver/screenshots, durable uncertainty and all broader F5/full-product/release gates remain open.

Signed build-only and strict signature verification pass; this build was not launched for external acceptance.

Current changed-code CI40640261823 at e34c325 also stopped before any test step with the same GitHub account payment/spending-limit annotation. No unchanged run is retried. Remote code verification is not passed; account-owner Billing & plans action is needed. This documentation-only receipt uses skip-ci to avoid a duplicate account-blocked run and does not waive the code gate.
