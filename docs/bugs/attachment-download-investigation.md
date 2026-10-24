# Attachment download verification regressions

Scope: bounded full-content hashing for A3; no UI change, so Lazyweb is outside scope. Apply the MUSUBI Bug Hunter investigation flow: reproduce, collect evidence, analyze, repair, verify. The source/reference remain pinned; never print bearer/file content.

## Premature success

Evidence: the socket peer sent HTTP200/Content-Length0 before reading any request. Runtime RED a17b157: one assertion in six tests failed because the exchange returned success with zero outbound bytes. c81b1f6 requires the complete preamble/request before returning HTTP200 on both framed and EOF paths; all six socket tests pass. Early401 remains accepted.

5 Whys: complete response was treated as complete operation -> parser completion returned directly -> request offset was not checked -> receive/send progress were tracked independently -> tests previously waited for the request before responding. Fishbone: bidirectional protocol state, completion guard, fixture ordering. Timeline: initial five passing cases -> independent review -> peer-first runtime RED -> offset guard GREEN -> review confirms both return paths.

## Literal plus in filename

Evidence: URLComponents leaves a literal '+' in query values, while the pinned Go handler uses FormValue decoding where '+' means space. RED5cfdd3a produced two assertions in seven tests. GREEN807912c percent-encodes literal plus as%2B after query construction; all seven authentication/route cases pass. A former test overrequired percent-escaping '?' even though it is legal inside the query; it was corrected to verify the decoded route, not an incidental encoding choice.

5 Whys: a valid selected basename mapped to a different guest name -> literal plus survived percentEncodedQuery -> encoder and form decoder differ -> default URL encoding was assumed identical -> special-character round-trip coverage omitted plus. Fishbone: URL encoding, server parsing, input fixtures. Timeline: route capability -> query inspection -> plus RED -> encoding GREEN -> review.

Prevention: retain peer-first success/error and plus-name regressions. Native diagnostic mismatch regression requires guest/local cleanup and prohibits success artifacts. Keep VM stop, progress, measured process memory, UI controls and guest-kernel reliability as separate open gates. Decoder unit tests verify bounded buffers, not measured process peak memory or file snapshot semantics.

## Upload interruption evidence false positive

The initial live upload-cancel-a3-v1 diagnostic observed partial162-byte multipart headers and successful cleanup but had no active-stop witness. It is retained in upload-cancellation-preliminary.json with accepted_as_live_stop_gate=false. Independent review found that a second upload emitting partial progress then failing HTTP503 before stop could still produce vm_stop.transfer_failed=true. Executed RED80ed15a has three failed assertions; GREENf312d40 records task completion before result delivery, rejects completed transfers before intervention, classifies failures without raw messages, requires cancellation and signals only after1MiB body progress. REDd2b7904 requires an active-owner cancellation count and zero-witness rejection; GREEN6a81f95 passes13socket/4fixture cases. Socket cancel counts open/not-already-cancelled owners under the same lock as shutdown/finish; controller records the count at stop and the diagnostic captures it before restart, requiring exactly one.

5 Whys: an error was accepted as stop evidence -> any eventual failure passed -> no pre-stop completion check -> progress was assumed to imply continued activity -> fixture tests omitted naturally failed transfers. Fishbone: asynchronous completion timing, causal evidence, ownership witness, test doubles. Timeline: initial live observation -> independent finding -> prefailed runtime RED -> completion/classification GREEN -> missing atomic witness RED -> lock-owned count GREEN -> fresh signed runtime verification required. Keep completed-before-stop, zero-witness, unexpected-success and cleanup regressions. A progress callback closure initially exceeded the local Swift type-inference budget; explicit typed optional callback assignment compiled without changing behavior. No guest-kernel fix or source-profile promotion is implied.
