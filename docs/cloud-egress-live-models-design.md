# Live model endpoint authentication check

Use the signed DEBUG probe and normal DesktopRuntime with the pinned guest,
a new private state disk and the production HTTPS broker. Set up a disposable
guest login. For each built-in preset, invoke the usual model-list API once
with the same hard-coded invalid value. The broker sends only its fixed GET
for that route. The probe neither accepts a real provider key nor requests
generation. Save no profile or chat.

Distinguish an actual provider rejection from a guest or transport failure.
Observe the authenticated guest API response before the app maps it to a
localized generic error. Record only the provider and a fixed classification
or HTTP status. A provider rejection, the model-list error presented by the
app, and a clean shutdown are separate checks. A failed exchange without a
verified provider response stays unresolved. Never record response text,
request headers or credentials. This diagnostic has no settings screen.

A single-use HTTPS connection can finish as soon as the parser consumes a
complete fixed-length, chunked or bodyless response. Finish only after the
entire received buffer has passed framing checks. The TLS worker closes the
session and never reuses the connection. A close-delimited response still
requires a valid TLS closure. Reset, timeout, cancellation and malformed
responses before the HTTP boundary remain failures.
[RFC 9112, TLS connection closure](https://www.rfc-editor.org/rfc/rfc9112.html#section-9.8)
