# Cloud egress on Apple Virtualization

The signed DEBUG probe booted the cloud5 Linux ARM64 candidate with a fresh
2 GiB state disk. It checked the live backend version and a 401 response to an
unauthenticated request, then used the normal authenticated LLM and Chat APIs.
OpenAI, Gemini and Groq each returned exactly one fixture model and saved the
expected final chat activity. The host observed the three model routes and
three chat routes in order. A fourth chat emitted part of an SSE response
without a terminal frame. Cooperative stop cancelled that exchange and
released the VM. The guest audit verified fresh formatting, loopback-only
networking, no shared mounts and no credential markers.

The candidate was built from the bound cloud profile image, the cloud5
backend and the existing guest Dockerfile with build networking disabled.
The only change to the inherited init was setting
`ARTEX_MAC_CLOUD_EGRESS=vsock-v1` on the backend invocation. The boot used
Apple Virtualization with the retained kernel and initramfs. The manifest
binds the actual kernel, initramfs and system disk. See the
[verification receipt](../evidence/llm/cloud-egress-vm-verification.json).

To rerun with the retained candidate, build `swift build --product VMProbe`,
copy and ad-hoc sign it with `guest/entitlements.plist`, then invoke
`VMProbe --cloud-vsock ARTIFACTS NEW_PRIVATE_OUTPUT`. The altered-manifest and
existing-output probes fail before boot. Release refuses the fixture flag.
The probe exercises live virtio delivery against synthetic provider responses
without contacting provider servers. Anthropic's actual VM transport, live
provider requests, normal app activation and the browser comparison remain
open.
