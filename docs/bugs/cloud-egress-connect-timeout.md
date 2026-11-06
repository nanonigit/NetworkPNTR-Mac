# Cloud egress pre-dispatch timeout

A signed VM diagnostic reproduced four provider failures in one boot. The
Mac worker parsed each guest request and reached the TCP connection step.
Each first connection timed out at approximately 10 seconds. The worker
had not entered TLS or sent HTTP. A second boot showed immediate TCP
failures for two providers and the same connection timeout for the others.

## Cause and repair

The VM returned a model-list failure because the broker closed without a
confirmed response. The broker stopped because the TLS worker returned the
same timeout category for pre-dispatch connection deadlines and
post-dispatch deadlines. The broker correctly avoids replaying a request
after dispatch, but could not distinguish a timed-out address from a
possibly delivered request. The remote or network cause of the observed
TCP failures is undetermined.

The C worker now maps deadlines reached before the first HTTP write to the
existing pre-dispatch connection failure category. The Mac broker can try
another vetted address for the same origin, with four seconds per address
and at most four candidates within the existing deadline. Cancellation,
certificate identity, address admission and post-dispatch behavior retain
their existing boundaries.

## Reproduction and regression

The loopback fixture stalls TLS before HTTP. It previously returned result
5, the generic exchange timeout, where the broker requires result 2 for
safe address fallback. With the repair it returns 2 and closes the socket.
The held HTTP response still returns 5, and handshake cancellation still
returns the cancellation result. The signed VM uses the production broker
and a fresh disk to check live statuses, then uses the synthetic fixture
for the four model and streaming routes.

## Verification outcome

All twelve loopback TLS tests passed. The final signed VM passed the four
synthetic model and streaming routes and the in-flight stop check. Two
signed runs against the production provider routes returned no confirmed
upstream status. A separate host TCP-only check connected to all four
hostnames during the verification window, so the investigation has not
established that the provider sites were generally unreachable. Keep the
live stability gate open.

[Verification receipt](../../evidence/llm/cloud-egress-connect-timeout-verification.json)

## Same-address follow-up

TCP-only signed probes stopped before TLS and sent no HTTP. A separate
host process attempted TCP to the exact numeric address at the same time.
It connected on the samples where the signed probe timed out. Substituting
`select` for the connection wait reproduced the difference. The same
signed process also reproduced the failure before creating a VM.

At one pre-VM timeout, the kernel TCP state was established while
`select` reported no writability, the expected peer was unavailable,
and `SO_ERROR` was zero. A read-only sample of the macOS content-filter
socket table during that attempt matched one TCP record by process ID
and address family. It had the connected flag set, initial verdict
unset and drop unset. This establishes a pending filter decision for
that observed probe attempt. The active network extension was Little
Snitch 6.5. Its rule and the Release app's network identity still need
to be checked separately.

A later boot in that same diagnostic run connected at TCP for all four
providers. No provider response was requested in these TCP-only probes.
Keep the live authenticated API and repeatability gates open. The
production socket checks and host filter configuration were preserved.
[Apple XNU socket connection handling](https://raw.githubusercontent.com/apple-oss-distributions/xnu/main/bsd/kern/uipc_socket2.c) ·
[Apple XNU content-filter state](https://raw.githubusercontent.com/apple-oss-distributions/xnu/main/bsd/net/content_filter.c) ·
[Little Snitch pending connections](https://help.obdev.at/littlesnitch6/lsm-managing-rules)

[Paired TCP verification receipt](../../evidence/llm/cloud-egress-tcp-pair-verification.json)

## Retest after the user's firewall change

The same signed diagnostic used two new guest state disks. Both runs
received HTTP 401 from Anthropic and Groq. OpenAI and Gemini had no
confirmed upstream status in either run. Little Snitch's Active Rules
view showed both outgoing allows and provider-domain denies for the
ChatGPT / VMProbe process pair. The presence of overlapping entries
does not establish which rule governed a specific attempt. The
ARTEX Mac Release executable's decision was outside this probe.
[Retest receipt](../../evidence/llm/cloud-egress-firewall-retest.json)
