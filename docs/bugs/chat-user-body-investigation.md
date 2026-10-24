# Persisted user-body investigation

Scope: A6 user text and readonly attachment metadata. Requirements/design/tasks preceded implementation. MUSUBI Bug Hunter workflow: reproduce, gather evidence, analyze, repair, verify.

## Reproduction and evidence

Browser list activity omits Detail; Summary alone drops structured uploaded cards. Fixed transcript.tsx parser SHA c735ebddab7f790f967a42e54fc993b9dd817a44eea5532bb461fb52dfe17952 defines literal user text and ordered duplicates. Missing model/store/readonly controls/fixture each received a RED checkpoint before GREEN implementation.

Correction to a324333 RED label: the apparent BOM parser mismatch was not a Swift hasPrefix defect. Foundation JSONSerialization stripped the leading BOM inside the decoded oracle string; direct construction and typed JSONDecoder retained UTF8 byte239. Switch both user-body and whitespace fixture decoding to typed JSONDecoder; assert the BOM byte. Keep the original commit, but do not count its misleading assertion as valid product reproduction. Explicit first UTF8 byte detection expresses the pinned contract.

Review found fixture cleanup originally deleted conversation rows but left owned session files, and post-seed diagnostic failure could skip cleanup. Controlled tests drove DELETE conversation then the entire owned session directory, attempts across all IDs, plus outer-failure authenticated cleanup. Reference multipart review found closing delimiter bytes excluded from64KiB bound; e9c42bf reproduced it and d287b3a checks the complete body including terminal delimiter.

## Root cause

5 Whys: missing cards -> list summary rendered directly -> persisted detail not fetched -> composer attachment work did not cover transcript -> parity matrix needed an explicit persisted-row gate. BOM false signal: fixture conversion changed the tested bytes -> dynamic Foundation decoder behavior unasserted -> assumed JSON reading was transparent -> no byte sentinel -> misleading RED label.

Fishbone: data boundary (summary/detail, metadata validation), asynchronous lifecycle (owner/generation/cancel/defer), fixtures (BOM conversion and cleanup ownership), protocol bounds (final multipart delimiter), UI (duplicate IDs and removal affordances). Timeline: source inspection/oracle -> model RED/GREEN -> BOM evidence correction -> owned loader RED/GREEN -> readonly UI -> fixture review repairs ->221 Swift/49 Python -> signed VM and browser three-case external comparison -> verified cleanup.

## Verification and limits

user-body-verification.json records three identical persisted contracts plus actual external AX/screenshot checks. Tests:220 Swift pass,1AX skip;49 Python pass. Parser/store line coverage100%; store regions94.3%. UI row line coverage77.1%, error/retry external exercise pending. Strict invalid metadata falls back to literal body, an intentional security boundary difference from permissive browser parsing. No live provider success, full-chat parity, long-history memory/viewport, VoiceOver or kernel reliability claimed.

Recurrence prevention: checksum before oracle evaluation; typed byte-preserving fixture decoding/BOM assertion; controlled stale reply/defer and cleanup-failure tests; whole multipart bound regression; external duplicate-card/no-remove witness distinct from skipped in-process AX test.
