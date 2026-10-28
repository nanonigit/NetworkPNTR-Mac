# Captured traffic prerequisites: five-stage verification record

## 1. Identify and reproduce

The complete F5 UI inventory needs captured candidate paging and raw previews, but neither typed API existed. RED e33e7b6 failed at missing CapturedTrafficService/Query types. A separate UI prerequisite audit found full-byte evidence export also absent; it remains an explicit later gate rather than being replaced by a preview.

## 2. Evidence and timeline

Pinned server.go getTraffic/getTrafficExchange, dto.go TrafficExchangeDTO, traffic.Page, browser api/types and picker/viewer components define the wire contract. The first seven compiled cases had one failure: Foundation's decoded query string consumed a leading UTF8 BOM. A diagnostic showed the actual request still contained `host=%EF%BB%BFe%CC%81...`. Production encoding was correct. An independent percent-byte decoder now checks the wire exactly, including FEFF and plus signs; it does not use the lossy decoded String as the oracle. Eight corrected contract tests and29 combined traffic tests pass (67e9be8).

## 3. Root cause and prevention analysis

5 Whys: the picker could not fetch because no native candidate service existed; prior work covered already-bound evidence; the browser picker adds global capture lookup; finite authenticated routes had not been modeled for it; completeness was tracked as a later UI gate. Fishbone: coverage—bound vs unbound APIs, state—capture off vs no index, identity—String canonical equality vs opaque byte IDs, validation—optional/null/partial metadata, verification—Foundation query decoding can alter a BOM. No runtime provider/network defect is established by these fixture tests.

## 4. Repair

Add GET-only finite typed discovery and raw preview, exact query/ID encoding, byte identity and explicit disabled-index shape. Capture-off history remains available. Require exact requested page/size, nonnegative counts/lengths and unique byte IDs without assuming separately-read global/matching counts are atomic. Enforce8192 encoded target and4MiB response bounds, cancellation before/after await, strict200 and safe errors. Never open captured URLs or treat raw preview/blob markers as full bytes.

## 5. Verification and recurrence prevention

Retain malformed/null/partial/disabled-history, independent byte decoding, canonical-equivalent IDs, exact/one-over target/body sizes, valid-payload status classification and pre/post-cancel cases. Independent review's status-test gap was corrected with valid raw payloads and typed errors. No live backend, provider, keys or guest writes used. Picker ownership, all native evidence controls, full-byte export and actual guest/browser/UI acceptance remain mandatory and incomplete.
