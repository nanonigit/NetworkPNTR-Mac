# Attachment download verification regressions

Scope: bounded full-content hashing for A3; no UI change, so Lazyweb is outside scope. Apply the MUSUBI Bug Hunter investigation flow: reproduce, collect evidence, analyze, repair, verify. The source/reference remain pinned; never print bearer/file content.

## Premature success

Evidence: the socket peer sent HTTP200/Content-Length0 before reading any request. Runtime RED a17b157: one assertion in six tests failed because the exchange returned success with zero outbound bytes. c81b1f6 requires the complete preamble/request before returning HTTP200 on both framed and EOF paths; all six socket tests pass. Early401 remains accepted.

5 Whys: complete response was treated as complete operation -> parser completion returned directly -> request offset was not checked -> receive/send progress were tracked independently -> tests previously waited for the request before responding. Fishbone: bidirectional protocol state, completion guard, fixture ordering. Timeline: initial five passing cases -> independent review -> peer-first runtime RED -> offset guard GREEN -> review confirms both return paths.

## Literal plus in filename

Evidence: URLComponents leaves a literal '+' in query values, while the pinned Go handler uses FormValue decoding where '+' means space. RED5cfdd3a produced two assertions in seven tests. GREEN807912c percent-encodes literal plus as%2B after query construction; all seven authentication/route cases pass. A former test overrequired percent-escaping '?' even though it is legal inside the query; it was corrected to verify the decoded route, not an incidental encoding choice.

5 Whys: a valid selected basename mapped to a different guest name -> literal plus survived percentEncodedQuery -> encoder and form decoder differ -> default URL encoding was assumed identical -> special-character round-trip coverage omitted plus. Fishbone: URL encoding, server parsing, input fixtures. Timeline: route capability -> query inspection -> plus RED -> encoding GREEN -> review.

Prevention: retain peer-first success/error and plus-name regressions. Native diagnostic mismatch regression requires guest/local cleanup and prohibits success artifacts. Keep VM stop, progress, measured process memory, UI controls and guest-kernel reliability as separate open gates. Decoder unit tests verify bounded buffers, not measured process peak memory or file snapshot semantics.
