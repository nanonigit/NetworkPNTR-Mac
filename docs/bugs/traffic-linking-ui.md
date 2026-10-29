# Traffic linking integration regression record

## Evidence and reproduction

New integration contract first failed to compile because TrafficLinkWorkspace and its parent/service APIs did not exist (b35de82). Async XCTest autoclosure syntax in the draft was corrected before retaining this intended missing-implementation RED; that draft issue is not a production bug. Minimal integration6a8acaa passed12 cases. Additional tests9e04cb9 exposed a real omission: a1000-character CJK query fits the raw8192-byte input bound but expands beyond8192 bytes after URL encoding; the request reached the fake transport instead of failing locally.7777446 adds the encoded path boundary;17 cases passed. No real network/server incident is claimed.

Independent read-only review found a known severity token displayed raw in Japanese.429f62c records the missing presentation contract;41cf720 reuses DashboardLabels, translates only recognized protocol values and preserves custom UTF8 literals.18 cases passed. Rechecking the frozen browser selector exposed missing finding ID/name fallback in the first native rendering. ae94b77→60017f0 verifies and restores `#finding_id · (name || vulnclass)` in both candidate and selected labels;19 cases passed. Candidate raw names, evidence and user CJK are not translated.

## Five Whys

1. Why could an oversized URL leave the selector? The new method reused a raw text limit only.
2. Why was the raw bound insufficient? Percent encoding expands non-ASCII bytes.
3. Why did initial tests miss it? They covered literal Unicode round trips but not encoded expansion.
4. Why could Japanese display retain English severity tokens? The first row used the backend string directly.
5. Why did visual details differ from the reference? Initial state-focused coverage did not assert finding handle/fallback presentation. Add boundary and closed-domain presentation assertions alongside lifecycle tests; do not infer visual parity from successful rendering.

## Fishbone

Input: raw/encoded lengths and literal normalization differ. Contract: vendor data and owned protocol labels need separate handling. Lifecycle: parent lease, query owner, flow revision, dialog/search generation and write nonce can expire independently. Testing: normal render alone excludes error/recovery states. Environment: an offscreen NSHostingView cannot prove actual keyboard/VoiceOver/layout acceptance on the locked Mac.

## Timeline and repair

Requirements/design and pinned selector research preceded implementation. Missing-API RED→12-case GREEN established parent retention and scoped binding. Runtime encoded-limit RED→17-case GREEN repaired a real boundary omission. Review/localization RED→18-case GREEN and browser-title RED→19-case GREEN repaired presentation. Added passive loading/error/empty/unknown/recovery rendering regressions for the remaining branches. Full-suite/build/evidence results are recorded in traffic-linking-ui-verification.md, not inferred here.

## Recurrence prevention

Keep tests for percent expansion before transport, literal FEFF/NFD identity, read-only candidates, canonical mutation handle, cross-page selection, debounce/cancel/late replies, reentrant publication teardown, pre-dispatch parent-scope loss, post-dispatch selection changes, stale submits/dismissals/acks and retained uncertainty. Loading/empty/error/recovery rendering must never fetch, retry, acknowledge or mutate. Explicit reload and acknowledgment remain separate user actions. Root runtime/real VM/browser/keyboard/VoiceOver/multiwindow and blob acceptance stay open. This is a volatile window-local ledger, not a durable cross-process operation journal.
