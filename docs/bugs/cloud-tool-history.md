# Managed tool history loss and signature context

## Reproduction and timeline

CP1b verified model discovery/text but not tool history. The new actual-provider fixture uses two synthetic tool calls, Complete or seven-byte-flushed SSE, normalized JSON save/reload and a second HTTP request with harmless precomputed results. aa2a6bf records runtime RED: signatures lost in both modes and interleaved streamed arguments misassigned. 3fe4c64 retains typed signature metadata and indexes, passing those fixtures and all llm tests after a pre-existing upstream test fixture was corrected. Independent review then found cross-endpoint replay; a7383ee reproduces unbound signatures forwarded to OpenAI/Groq/custom endpoints. cb77140 adds decoder-stamped endpoint/model context, copied request filtering, negative endpoint/path/model tests and Anthropic stripping, then passes the same suites. No tool was executed and no real API key/cloud endpoint was used.

The baseline upstream TestDoStreamHonorsConfiguredRetries directly called internal doStream with a nil HTTP client. The unpatched module reproduces its panic. A test-only change supplies srv.Client(); production retry logic is unchanged. This setup issue is not the signature RED and is not hidden by skipping the test.

## Five Whys

1. Why did a second tool round lose state? OpenAI decoding dropped Google tool metadata and streaming inputs went to the latest tool.
2. Why was metadata lost? The normalized tool block had no typed signature field and frame events lacked tool indexes.
3. Why did JSON history not restore it? The missing data never entered the normalized message.
4. Why could an initial fix send metadata to another provider? The original request converter had no provenance for an added signature.
5. Why did CP1b not catch this? It validated discovery/text and request encoding, while complete tool history and destination changes were explicitly later gates.

## Fishbone

Protocol: known signature field only; no bypass or arbitrary vendor extra replay. State: indexed argument/signature association plus early metadata handling. Persistence: normalized typed JSON survives reload. Destination: signature scope binds runtime endpoint/model; mismatched/unknown scopes are removed on copies. Isolation: recursive Anthropic stripping preserves its own thinking signature and source history. Testing: real pinned provider+HTTP fixtures and full SDK/package tests in network-disabled Linux; synthetic results never execute tools. Supply chain: verify pinned original dependencies, copy the module, check/apply reviewed patch, use a container-local replacement; preserve browser/default guest.

## Prevention and remaining gates

Keep signed/unsigned stream/non-stream cases, interleaved arguments, early/late signatures, normalized JSON, same-context positive, changed endpoint/path/model negative, no internal scope on wire, immutable history and recursive Anthropic isolation. Full test/coverage/build receipts are in cloud-tool-history-verification. Scope hashes are context identifiers, not authorization; same-origin credential rotation, actual task DB transcripts, compaction/restart, egress redirects, usage/errors/cancel and real four-provider/UI/browser acceptance remain required. Do not promote the experimental backend because these fixtures pass.
