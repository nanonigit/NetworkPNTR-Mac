# Traffic presentation boundary investigation

## Reproduction and evidence
Initial b4d931f is an intentional missing-model compile RED, not a runtime bug.3d89699 passes12 controlled-clock cases. Boundary tests ada08e1 then reproduce six failures/errors in15 cases: matured text is lost while a confirmation blocks application; reset requested during stop retains the unknown operation scope; reset during begin's retirement permits the new presentation to reopen. These are deterministic model/core fixtures, not installed UI or VM observations.

## Root cause
Five Whys: the debounce callback discarded its task after apply returned false; false conflated invalid/stale inputs with a temporary modal/write gate; the model had no retained matured-ticket queue; thus no gate-release event could retry only the local unapplied query. Retain per-field matured tickets and observe the read-only gate instead. This is not a retry of a server mutation.

Reset was dropped because tearingDown was treated as a blanket reason to ignore lifecycle requests; ordinary stop and reset teardown were conflated; recursive-publication prevention therefore overrode authentication privacy priority. Queue reset during ordinary retirement, suppress only recursive reset during actual reset teardown and prevent begin from resuming when reset is queued.

Fishbone: scheduling—300ms ticket versus temporary gate; identity—field revision/presentation versus query owner; lifecycle—stop versus auth reset; concurrency—willSet publication and callback generation; transport—cancel-ignoring held reads versus new query generation; acceptance—controlled clock/API versus real timing/UI/VM.

## Repair and verification sequence
b4d931f missing-type RED →3d89699 twelve-case GREEN →ada08e1 actual boundary RED →e5fc56f fifteen-case GREEN →expanded18 cases. Matured tickets survive confirmation/write gates and merge into the current query after release, without repeating writes or acknowledging uncertainty. Advanced reset/new edit/teardown revoke relevant tickets and watches. Reset wins over stop/begin, raw drafts are scrubbed and teardown observers cannot restart the presentation. Read-only review of the fixes found no new blocker.

## Recurrence and scope
Keep exact boundary regressions and held-write503/recovery tests. A new root/screen must retain this model per window/session, pass immutable presentation leases to bindings/tasks/teardown and call reset on auth departure. Tests use an injected clock; they do not prove elapsed300ms/5s accuracy, a visible screen, browser parity or real backend mutation. Original TR3–TR5/kernel/provider/harness/release gates remain open; see traffic-screen-model-verification in both languages for the final finite receipt.
