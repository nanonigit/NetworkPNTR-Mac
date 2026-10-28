# F5e3 captured traffic picker software checkpoint

The native evidence sheet now opens a captured-traffic picker backed by the authenticated VM client. Host/method/keyword filters use a250ms cancellable byte-based ticket; changed filters reset page0, unchanged task restarts retain the page. It provides25-row paging, byte-exact cross-page selection, page selection/clear/count and already-bound exclusion. Recorded URL/method/status/time and raw request/response previews are plain selectable text; recorded URLs are never fetched or opened. RFC3339/fractional timestamps preserve their instant, with opaque fallback text.

The child presentation, row/draft bindings, query owner and preview identity are scoped separately. Parent actions/export/refresh are gated while the picker is presented. A confirmed current-owner add refreshes parent metadata, clears stale evidence preview and closes the picker. Failed/post-dispatch cancelled adds retain the existing shared unknown-outcome gate without auto replay. Ordinary cancel is disabled during submit; forced workspace departure retains uncertain writes and late cleanup cannot revoke another owner. Accepted close during synchronous publication is queued and can revoke a just-acquired submission before dispatch.

## Evidence

- Missing picker contracts9dc8489 ->ae53eb2(10 GREEN). Missing view contracts5505d8b preceded runtime checks; the14-case run found unchanged filters resetting page1 to0. Runtime REDcd9c347 also reproduced restored inactive draft data and a child-close precondition/process signal5. GREEN4a313dd passed100 related cases. Additional accepted-prebusy-close, timestamp, raw preview/loading/failure/empty/submitting display cases bring the new picker suite to20.
- Full coverage-enabled Swift regression:824 cases,823 pass,one existing external accessibility skip,zero failures (19 probe,248 app,557 core). Full GuestArtifactTests155 pass.
- LLVM whole-file line counts: FindingCapturedPicker141/143(98.60%), Bindings23/23(100%), View325/394(82.49%), FindingTrafficWorkspace333/336(99.11%), Presentation19/19(100%), core CapturedTrafficPickerStore206/208(99.04%). These scoped software counts are not all-product or manual UI coverage.
- Offscreen EN/JA and light/dark construction exercises history, unavailable, safe error and raw-preview states; further offscreen cases cover loading, preview failure, empty history and pending submission without extra requests. Fixtures use distinct NFC/NFD IDs and literal FEFF/CJK text, actual core stores and held continuations; they do not seed a real captured index.
- Frozen e75ae371ad777ffd1eecdd28d2781a6519b05591 inventory remains21 navigation features/27 routes/243 API handlers, with native workflow parity pending. Localization export and shell syntax checks pass. No dependency, key, guest state or network policy change was added. Bilingual RCA: bugs/captured-picker-ui.

script/build_and_run.sh --build-only rebuilt the local app successfully. After the build process terminated, codesign --verify --strict passed for the resulting bundle. This is a local build/signing checkpoint, not installation, notarization, launch or actual guest-backed UI acceptance.

## Open acceptance gates

Actual managed-guest and fixed-reference nonempty captured-index operations are still required: filter/page/selection/raw preview/bind/edit/remove/order; version conflict/unknown-outcome recovery; restart persistence; detailed preview byte-offset/binary/truncation/original-body comparison. Prior original-body transport/native/reference evidence remains a historical checkpoint, not a real run of this new UI. Actual mouse/keyboard/VoiceOver/save-panel/multiwindow/screenshots await the user's deferred manual unlock. Offscreen tests do not substitute for those gates.

Keep every original21-workflow, source-kernel reliability/default promotion, clean installation/signing/notarization/release, four-provider and investigation-harness requirement. The full goal is active. Hosted CI remains unverified under exhausted Actions quota; publication HEAD uses [skip ci], with no dispatch/rerun or billing change.
