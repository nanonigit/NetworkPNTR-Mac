# LLM transport cancellation regression

## 1. Identify and reproduce

Synthetic transport tests reproduce calls made by already-cancelled tasks, late successful replies escaping cancellation, and valid JSON accepted above 4 MiB. RED08456c8: six tests, 39 assertion failures. No live keys, cloud requests or guest mutations.

## 2. Evidence and timeline

Existing LLM service tests covered routes and DTOs but not task cancellation with an uncooperative transport. First fixture compilation failed because BackendAPIError is not Equatable; pattern matching repaired the test harness before the recorded behavioral RED. Then the six compiled tests failed against unchanged production code. Shared raw checks made all six pass; all 22 LLM-filtered tests pass. GREEN21e540a's commit subject mistakenly says 37; the actual focused count is **22**, not 37.

## 3. Root cause

5 Whys: cancelled operations dispatched because raw called send unconditionally; late replies escaped because raw checked only status; injected transports need not honor cancellation; the feature relied on lower transport behavior; route/shape tests did not include cancellation ownership. Fishbone: code—no checks around await; transport—cooperative cancellation not guaranteed; tests—no adversarial return; process—finite-JSON assumptions were not enforced locally. UI and provider behavior were not causes established by this experiment.

## 4. Repair

Check cancellation before send and after await, before reading status/body. Reject request/response byte counts above 4 MiB. Existing public signatures, routes and payload validation remain unchanged. Exactly 4 MiB is covered in both directions. No retry is introduced.

## 5. Verification and recurrence prevention

Keep pre-cancel cases for all eleven request families, post-handoff cancellation before malformed/status errors, late valid success, oversized draft/model/test requests and exact/one-over byte boundaries. This proves a service contract only. LLMStore ownership, uncertain mutation acknowledgement/replay gating and dismissed editor task ownership require separate adversarial tests and recovery UI. A cancelled dispatched mutation may already have committed. Browser/native visual interaction and actual VM acceptance remain open.
