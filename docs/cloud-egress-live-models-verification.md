# Live model endpoint verification

The signed probe starts the preview DesktopRuntime with the pinned guest and
the production broker. It calls model discovery for each of the four presets
with an intentionally invalid value. It checks the app rejects the result,
then verifies that no profiles or conversations were created and the VM and
listener stop. No valid provider credentials or inference requests are used.

The first run confirmed only Groq's HTTP 401. A repeat had four timeouts
without confirmed provider responses. A host-only transport probe confirmed
OpenAI and Anthropic 401 and received Gemini 400 with data but no terminal
frame. A subsequent signed VM trace confirmed 401 from OpenAI, Anthropic and
Groq. Gemini completed TLS and then reported a read abort.

The broker now finishes a single-use connection at a verified HTTP response
boundary. The Swift test covers fixed, chunked and bodyless responses,
missing final bytes, extra bytes in the received buffer and close-delimited
failure. A loopback TLS test keeps the server open and checks that the client
returns the complete response and closes the connection. The first signed
run after the fix passed all four upstream statuses back to the app.
[RFC 9112, TLS connection closure](https://www.rfc-editor.org/rfc/rfc9112.html#section-9.8)

The recorded status is the provider response, not a successful model list.
A separate test with a valid key, model listing, streaming and local tool use
is still needed for each provider. Native UI and frozen-browser comparisons
remain open. General web access is outside this broker.

The final repeat returned no confirmed upstream status for any provider.
The four-status run therefore proves the path can work but leaves live
connection stability unresolved. Gemini's HTTP 400 was confirmed in the VM.
A separate host request identified an API-key argument error, but the final
VM run did not independently confirm that error category.

[Verification receipt](../evidence/llm/cloud-egress-live-models-verification.json)

## Signed Release preview model-list controls

A prepared disposable disk reached the normal login flow in the signed Release
app launched through Launch Services. After accepting the terms with the
user's authorization, the native New menu opened all four provider presets.
Each model-list action used a deliberately invalid value and showed the
localized Japanese model-list failure. One TCP socket owned by the Release
process was observed within eight seconds of each recorded click. Each
correlated socket showed an initial content-filter verdict with no drop
flag in at least one sample. This is socket evidence. The Release UI does
not expose upstream HTTP statuses.

The pinned browser source invokes the same model-list workflow, showing
failure in a toast. The native sheet keeps its translated failure inline.
The comparison for this run used the pinned source, with no interactive
browser run. The native list remained empty after closing the drafts.
Logout cleared the test Keychain session and the VM stopped cooperatively
with zero virtual NICs and zero shares. Valid-key discovery and generation
remain separate checks.

[Release verification receipt](../evidence/llm/cloud-egress-release-models-verification.json)
