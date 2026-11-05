# Direct transport for cloud egress

Use macOS system libcurl in connect-only mode on an admitted numeric destination. Disable proxying and redirects. Pin DNS for the fixed HTTPS hostname and port. The open-socket callback allows only the exact TCP peer in the validated address. After TLS and hostname verification, compare the active socket peer again before sending any provider bytes. Use a fresh connection per request.

The Swift entry point pairs a generated CloudEgressRequest with a destination admitted for the same hostname. A worker owns each transfer and its libcurl handles. The caller can cancel from another thread. Bound TLS setup and the entire exchange with monotonic time, check cancellation while waiting on sockets, and close handles on every exit. Deliver raw response chunks to a bounded sink without buffering the whole response. The vsock layer will validate HTTP response framing and own listener admission, a combined DNS and exchange deadline, and VM lifetime.

Exercise a real loopback TLS server with generated test trust, mismatched and untrusted certificates, a held response, a streaming response, cap enforcement and a configured proxy sentinel. Verify the production Swift entry rejects mismatched routes before starting any socket. Keep the default guest listener disabled pending the signed-VM acceptance phase.

The socket allowlist covers libcurl connection attempts. macOS certificate evaluation has its own intermediate-fetch policy. The production listener requires a TLS backend with explicit certificate-fetch control, along with an off-target issuer fixture and a valid complete-chain control.
