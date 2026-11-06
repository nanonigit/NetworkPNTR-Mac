# Cloud broker response framing

Convert one provider HTTP response into typed head, decoded body and end events. Publish the end event only after validated framing and a clean TLS completion. A partial stream can deliver body bytes before the end, so the future guest adapter must surface a read error when the terminal event is absent.

Support explicit length, HTTP/1.1 chunked framing and authenticated close-delimited bodies. Accept bounded interim responses without forwarding them. Reject redirects and protocol upgrades, ambiguous lengths, unsupported compression, truncated frames and trailing bytes. Forward a status and a normalized JSON or event-stream type. Drop arbitrary upstream headers and trailers. Cap head sections at 32 KiB, trailers at 8 KiB, chunk lines at 1 KiB, and decoded body bytes at 16 MiB. The existing transport independently caps wire bytes at 16 MiB. Keep body chunks opaque and retain no accumulated body in the host parser.

Exercise every single split point in a synthetic chunked stream, incomplete responses, malformed metadata, byte limits and sink failures. Run the tests through the same parser entry point that the TLS worker uses. The vsock transport will encode these typed events and own the VM lifetime. [HTTP/1.1 framing specification](https://www.rfc-editor.org/rfc/rfc9112.html)
