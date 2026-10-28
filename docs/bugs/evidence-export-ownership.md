# Evidence export receipt ownership regression

## 1. Reproduce

The initial nine authenticated export cases passed (cad90bc). Add a commit validator that synchronously calls the same receipt's discard(), and a receipt with status401 whose VM-lifetime validator throws cancellation. RED232b57f: eleven cases, five failed assertions. The first case published a file despite discard; the second expired current auth and removed its vault entry even though the VM reply was obsolete.

## 2. Evidence

The commit path moved its file to a local reference before calling external validation. discard cleared all stored validators but could not see that local file. Authentication handled401 before checking the receipt's runtime owner. Both failures were real temporary-file/session effects, not assertions against an implementation mock. No live VM/provider credentials or network calls were involved.

## 3. Cause analysis

5 Whys: why could a discarded receipt publish? The local file remained valid; why was ownership accepted? discard cleared the guard list; why was clearing enough? consumed prevented a second commit but did not revoke the already-entered commit; why was revocation missing? initial tests covered cancellation and stale auth but not synchronous reentry; why was the contract incomplete? lifecycle cleanup and publication ownership were modeled as the same state. Root cause: missing independent revocation state.

For401: why did current auth expire? status handling ran first; why was it trusted? the auth revision was current; why was that insufficient? VM and authentication have independent lifetimes. Root cause: validating one owner did not validate all owners before interpreting a reply.

Fishbone: state model (consumed versus revoked), callback reentry (discard clears guards), lifetime ordering (VM before status), test gaps (late reply versus obsolete runtime). Timeline: missing APIs RED234418c -> initial GREENcad90bc -> explicit reentry/runtime401 RED232b57f -> correction1e7e64f -> 27 related cases green -> 36 cases green including129MiB+17 byte fidelity.

## 4. Repair

Maintain a separate revoked flag, set by discard even during a commit. Check revocation before and after ownership callbacks. Check the receipt's runtime lifetime before authentication handles status401; authentication revision still precedes its401 invalidation. On any pre-publication failure discard owned staging; never remove an already-published destination. UI activity validation runs before final runtime/auth validation without an intervening await.

## 5. Verify and prevent recurrence

Keep both RED fixtures, old200/401 after re-login, current401 with vault failure, cancelled uncooperative success, logout after transfer/during UI validation, single-use commit, UI/runtime rejection, stopped concrete client and exact saved-file comparisons. Add actual VM stop/restart and native window ownership tests before declaring end-to-end export complete. Full regression/build/CI results are recorded in evidence-export-connection-verification.md.
