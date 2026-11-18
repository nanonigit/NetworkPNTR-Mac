# Cloud live-model regression: connection ends before upstream status

[English](local-session-cloud-egress.md) | [日本語](local-session-cloud-egress.ja.md)

Status: reproduced, cause unproven, live-cloud acceptance open. [Evidence](../../evidence/local-session/cloud-egress-regression.json).

## Reproduction and controls

Build and sign the DEBUG VMProbe with the virtualization entitlement. Use separate new private output directories. Run `VMProbe --cloud-live-models CLOUD_ARTIFACTS NEW_OUTPUT --local-session` against the corrected, explicitly pinned native-session cloud manifest. Run the two-argument form against the unchanged packaged cloud guest as a control. Requests use a deliberately invalid fixed value and only the four fixed provider model-list routes; no real API key, inference, saved profile or conversation is involved.

The first automatic run failed without upstream status. Observability was then added without changing requests, authentication or transport behavior. Both the unchanged control and automatic candidate report downstream200/ok:false, `unexpected-eof`, and no confirmed upstream status for all four providers. All three runs exited1; their separate outputs are retained. A failed application model query alone cannot prove a live vendor exchange.

System curl reached OpenAI with401, including a TLS1.2-only check, with no proxy environment variables. A separate minimal diagnostic calling the exact production C function made two fixed, DNS-observed IPv4 connection attempts. Both entered nonblocking connect (`EINPROGRESS`) and expired in the four-second connect phase before a TLS handshake or HTTP request. This narrows the investigation, but does not establish a firewall, VPN, OS-policy or transport defect.

## Causal questions

1. Why does the service probe fail? It cannot establish an upstream authentication rejection for any provider.
2. Why is an application rejection insufficient? The backend can return an error for a broken vsock/upstream stream before receiving vendor HTTP headers.
3. Why suspect a shared path? The unchanged backend control fails in the same way as the new automatic-session candidate.
4. Where is there a narrower failure witness? The direct production-C diagnostic expires before TLS, while system curl reaches the vendor.
5. Why do these processes differ? Unproven. Next distinguish process/network-policy admission from connection-phase timing using bounded diagnostics and actual Mac-side observations once unlocked.

Do not raise deadlines, weaken peer/hostname/offline-certificate validation, use a proxy fallback or attribute the failure to local authentication merely to obtain a green run. Preserve control failures. Keep UI and live-cloud acceptance open; the signed local-session data/authentication checks remain separately recorded.

## Prevention

The probe now records only fixed backend-error categories and downstream status, alongside upstream authentication status. A regression ensures unknown/private error text becomes `unclassified` rather than being copied into receipts. Pair every result array with its launch mode, binary/source digest and guest-manifest digest. Retry only with a stated diagnostic change or verified external-state change; retain each attempt.

Provenance limit: the first automatic run did not record the probe binary/source hashes. The later unchanged-control and observed-candidate runs include both. Its guest-manifest identity and failed exit remain recorded; do not retroactively infer a missing executable hash.
