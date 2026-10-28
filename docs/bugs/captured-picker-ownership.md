# Captured picker ownership: five-stage regression record

## 1. Reproduction

Missing-store RED e1ba09a established the picker contract. Initial implementation b1f4d5f completed14 cases with seven failed assertions: read-loading publication could overwrite synchronous invalidation, invoke the revoked loader and leave the gate busy. Correction fe8d687 passes14. Expanded RED ca191b7 completed21 cases with eight failures for restored selections/preview IDs, recursive or lost lifecycle transitions and a stale child success published during cleanup. Corrected ed3f6b7 passes21;50 combined traffic/read cases pass.

## 2. Evidence and timeline

Controlled synthetic transports provide page/preview replies in reverse order and hold a bind after handoff. Selection spans pages, excludes already-bound byte IDs and distinguishes NFC/NFD identities. Parent/child busy notifications close the picker before dispatch; no POST or uncertainty appears. Stop/resume after handoff retains the gate and discards child UI success while the parent can keep a known receipt. Cancelled dispatched writes keep parent uncertainty. Test callbacks for confirmation cleanup are armed after dispatch, avoiding equal-value preflight notification dependence.

## 3. Root cause

5 Whys: obsolete selections survived because separate collection writes resumed after stop; stop cleared state before the original setter committed; lifecycle transitions were not guarded; result cleanup was not followed by ownership revalidation; missing integration tests did not exercise synchronous observers. The shared read path similarly published busy before checking whether that publication invalidated its own generation. Fishbone: state—separate selection collections; lifecycle—resume/reentry; transport—post-grant handoff; identity—parent/query/preview ownership; tests—callback phase and reverse replies. Timeline: acquire -> synchronous stop -> original setter continues -> residue or stale receipt. These are local state defects, not evidence of backend failure.

## 4. Repair

Use private acquisition/lifecycle guards, pending stop during resume, cleared selection on resume and post-publication owner checks. Capture parent owner and invoke the child validator at the parent's service handoff. Keep parent version/unknown gates intact. Shared FindingReadState rechecks generation after busy publication, before the first await, and checks cancellation before invoking the loader. Queued newer reads do not inherit an invalid old busy gate. No retries, automatic binding/acknowledgement, new host capability or actual guest write is introduced.

## 5. Verification and recurrence prevention

Keep cross-page/bound/byte-ID, stale and reverse reads, read-only targets, valid bind/conflict, pre/post-handoff stop/cancel and synchronous observer regressions. Independent review found selection restoration and verified its fix; shared-helper and lifecycle corrections were also reviewed. Native controls, window/detail integration, full-byte export, actual nonempty guest/browser persistence and external keyboard/VoiceOver/visual acceptance remain pending. CI account payment/spending-limit constraints are a separate open gate.
