# Traffic finite boundary investigation

Reproduce/evidence:506f52f missed the new typed contracts and failed compilation. Ateddd908 the compiled first run had three assertions fail across two new tests: the leading FEFF disappeared through Foundation test decoders. This reproduced the earlier captured-service/query and finding-note oracle problem, not packet normalization in production. Actual percent bytes and typed decoded JSON preserve FEFF/NFD/plus values. The corrected3790a5e run has18 focused pass; full849 Swift (848pass/oneexistingAXskip) pass.

5 Whys: test reported a missing byte because its decoded value omitted FEFF; Foundation URL/JSON bridging consumed the BOM; the test used a convenient decoded String as the wire oracle; byte-identity evidence had not been reused from earlier traffic tests; the new suite needed the same independent byte boundary. Root cause: lossy test oracle. No production encoder change was needed.

Fishbone: source contract—substring/exact/purge distinctions; input—Go versus ECMAScript whitespace and opaque bytes; decoding—BOM-consuming Foundation helpers; precision—Int64 versus JavaScript numbers; mutation—logical dispatch/cancel/unknown scope; acceptance—finite mocks are not actual VM effects or UI.

Timeline: requirements/design and compileRED506f52f → implementation/runtime oracleREDeddd908 → independent byte/typed-JSON correction plus request-size and post-dispatch cancellation guards GREEN3790a5e. Code review confirmed fixed routes, deletion semantics, partial settings, bounds and no retry. Source files cover172/172 LLVM lines, not all branches or product workflows.

Repair/recurrence: compare percent bytes without Foundation-decoded query values; inspect JSON strings with typed decoding and UTF8 byte comparison. Retain leading FEFF/NFD/CJK, plus/query delimiter, duplicate/null hosts, exact large integers, all-empty versus FEFF host deletion, valid oversized payloads, purge receipt shape, settings mismatch and pre/post-dispatch cancellation cases. Keep actual multi-host fixture/store/UI/blob/evidence preservation gates open and never infer rollback or expose destructive scope without later explicit UI confirmation.
