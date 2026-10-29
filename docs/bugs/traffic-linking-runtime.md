# Standalone linking runtime evidence gap

## Reproduction and evidence

Before this checkpoint the native integration passed mock tests and the existing captured VM probe exercised only the finding-side picker. Neither proved that the newly added TrafficStore/candidate service/TrafficBindingStore path worked against the actual backend. The new StandaloneTrafficExerciseTests failed to compile for the intended missing helper (2c495b4), then five cases passed with da7f3ae. This was a verification gap, not a reproduced backend incident. dfb2d7a connects the helper to the existing DEBUG two-boot probe and makes the original picker repeat the same bind idempotently with exactly the same normalized receipt/version.

A fresh private disk and unchanged CPU1 candidate completed both real boots/stops, source/no-agent/isolation audits, original exports, controlled finding-edit uncertainty and persisted state comparison. The standalone path selected25+4 pages, bound fixture ordinals3/4, refused a replayed nonce and cleared only its matching selection. Actual binding version1 remained1 across the subsequent same-source picker bind. The full reference projection stayed equal. Native screen/root/input behavior was not executed.

## Five Whys

1. Why was standalone real behavior unproven? Only the mock transport exercised its new APIs/stores.
2. Why did existing VM success not prove it? It used CapturedTrafficPickerStore instead.
3. Why could both look equivalent? They share the underlying binding endpoint.
4. Why is endpoint reuse insufficient? Page/settings/hosts/candidates, state ownership and body construction still differ.
5. Why use one fixed controlled experiment? It proves the new path while preserving the independent browser projection, repeat-bind idempotence and persisted/no-agent audits. Do not substitute it for actual UI acceptance.

## Fishbone and timeline

Coverage: new Core path versus old picker. Contract:25-row Traffic pages,20-row findings, canonical handle, default refs and nonce. Runtime: disposable persistent disk, CPU1 candidate, zero NIC/shares, source/hash witnesses and two cooperative stops. Oracle: fixed browser API projection, identical normalized idempotent receipt and full original bytes. Timeline: requirements/design→missing-helper RED→five-case GREEN→read-only review→full regression→actual two-boot success→release DEBUG exclusion check and verification record.

## Recurrence prevention

Overall captured success now requires the standalone helper to finish and its receipt to match the existing picker exactly. Unit tests reject wrong fixture shape/order/duplicate IDs, wrong page envelopes, missing/read-only finding9101 and incomplete/failed receipts without automatic retry. Keep actual runtime output/binary/source/profile hashes and report native UI acceptance false. Multi-host deletion, blob extension, actual native/window/input/accessibility, default kernel reliability/promotion, full release/provider/harness goals remain open. The controlled uncertain edit belongs to FindingTrafficStore; new TrafficBindingStore response-loss recovery remains unit-tested only in this checkpoint.

Release-check setup note: the first invocation omitted the required positional argument shape and reached top-level usage, causing an expected-usage assertion failure. Retesting with all three dummy positional arguments reached the release subcommand guard and exited2. This was a check setup correction, not a production guard defect.
