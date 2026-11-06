# Cloud broker response framing verification

The TLS worker now passes provider bytes through the same bounded framer tested by the Swift fixtures. It emits a normalized status/type, decoded body fragments and a terminal event. The terminal event requires both a valid HTTP boundary and a clean return from the TLS transport. A downstream writer error, transport error or cancellation aborts the response.

The fixtures test every split point and single-byte delivery of a chunked stream with interim metadata, quoted extensions and trailers. They test every incomplete prefix, ambiguous framing, redirects, TLS failure after a complete HTTP message, bodyless and error responses, cumulative limits and a failed writer. Review identified Unicode folding and malformed chunk extensions as ways to accept invalid transfer metadata. Coding values now require ASCII, and extensions require a token name and an optional valid token or quoted value. [HTTP/1.1 framing specification](https://www.rfc-editor.org/rfc/rfc9112.html)

Reproduce with `swift test --filter CloudEgressResponseTests`. The [receipt](../evidence/llm/cloud-egress-response-verification.json) records the inputs and local results. The dedicated vsock protocol, VM lifecycle, signed VM streaming and live provider and browser acceptance remain subsequent gates. This checkpoint has no product UI changes. Hosted CI remains unverified.
