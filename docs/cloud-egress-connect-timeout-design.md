# Cloud broker connection timeout recovery

The broker can choose another vetted address of the same provider before
sending an HTTP request. Treat a TCP or TLS handshake deadline as a
connection failure only while the worker is still before HTTP. Use four
seconds per address and keep the existing cap of four addresses and shared
deadline. Cancellation and failures after dispatch must never trigger another
attempt. Keep the same hostname verification, route, request and address
policy.

Verify the boundary with a stalled handshake and a stalled response on
loopback. Then run the signed VM with a fresh disk and the normal production
broker. Record confirmed provider statuses and timeouts separately.
