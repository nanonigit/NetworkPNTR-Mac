# Phase 2 design and acceptance

Continue the full authorized goal. Phase 1's external native-control automation gate remains open; independent guest/backend work can proceed, but neither that gate nor browser workflow parity is waived.

## User journeys

- Start the Mac application and reach the real pinned ARTEX backend and PostgreSQL inside its VM without Docker at runtime.
- Stop/start the VM and retain admin authentication, LLM profiles and fixture assets on a dedicated guest-owned disk.
- Reject altered system artifacts, unexpected existing disks and unauthenticated VM transport. A bad disk must never be silently reformatted.

## Architecture

Use the same pinned ARM64 Alpine kernel, small module-loading initramfs, a read-only ext4 system image, and a separate writable ext4 state image. Attach no NIC or shared directory. PostgreSQL 16 matches the browser reference major version. ARTEX runs as UID 1000 with a read-only executable, using loopback guest PostgreSQL; its JWT lives outside the browsable workspace. Guest initialization and transport have separate non-agent identities.

A dedicated virtio-vsock listener forwards only to the guest's fixed 127.0.0.1:8787 backend. It accepts only host CID and a fresh 256-bit per-boot transport secret delivered through a fixed serial bootstrap protocol with echo disabled. Never print the secret. The Mac side optionally exposes an app-owned 127.0.0.1 ephemeral ingress for URLSession/SSE/WebSocket compatibility; the ingress has no filesystem/shell/RPC endpoint and forwards only to this VM. ARTEX's setup token and login authentication remain enforced; no API auth bypass. This internal listener is started by the app, never manually, and is not a browser-based UI.

Developer guest-image construction may use a pinned disposable Linux build container; compiled Linux binaries run only there or in the VM. The shipped app and runtime must not call Docker. All image recipes, package versions, hashes and the backend source commit are recorded. First image preparation is a developer build step, not an application startup download.

## Acceptance cases

T2.1 dedicated disk creation is exclusive, owner-only, preserves existing correct disks, rejects symlinks/size mismatch without mutation.
T2.2 backend configuration has exactly one vsock and two disks (system read-only), zero NICs/shares; proof configuration stays unchanged.
T2.3 serial credentials reject malformed/newline data and have redacted descriptions.
T2.4 real guest initializes PostgreSQL and ARTEX; host reaches health over vsock; wrong transport authentication is rejected; unauthenticated protected ARTEX API stays rejected.
T2.5 same fixture operations through browser/reference and VM yield equivalent normalized API responses; existing browser data is never mutated for testing.
T2.6 shutdown/start and forced stop preserve DB/auth/JWT/fixture records; malformed nonblank data disk fails closed instead of reformatting.
T2.7 artifact and disk validation errors are visible; no secret appears in guest logs/evidence. Real native control parity remains a separate pending gate.
