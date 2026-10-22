# Phase 2 backend checkpoint

The full product is still in progress. Historical P2 results below describe successful runs, not a stable-runtime acceptance. The app now bundles the real backend and native authentication services. Current Swift/Python test counts are 20/14. Repeated native testing exposed intermittent guest faults; see docs/bugs/guest-boot-investigation.md. Streaming, cloud egress and external native interaction/visual acceptance remain pending. No backend test counts as full native workflow parity.

## Verified locally

- Eight Swift unit tests: disk preservation/permissions/link and size rejection, provisioning validation/redaction, paired manifest integrity, two-disk/one-vsock configuration, and existing core invariants.
- Ten Python tests: bounded credential frames, EOF and wrong-token rejection, a large bidirectional stream with half-close, complete read-only blank-disk scanning, module autoload packaging, and existing boot formats.
- Real Linux VM: pinned ARTEX and PostgreSQL 16 boot on a read-only system disk plus a writable private data disk, with zero NICs and host shares.
- Authenticated vsock HTTP; wrong transport is closed; protected API returns 401; wrong setup returns 403; first setup and saving/reading a non-streaming LLM fixture succeed.
- Normal shutdown/start and forced-stop/start preserve the password, JWT and profile record. A nonblank invalid disk visibly fails without formatting or changing its marker/superblock area.
- Identical fixture operations against a disposable pinned browser backend give equal normalized API contracts. This is five backend contract cases, not all 243 APIs or browser/native UI parity. The existing browser database is untouched.
- No bootstrap secrets appear in guest console output. Logs/state/images are ignored by Git. Only normalized credential-free JSON and pass summaries are evidence artifacts.

Run `script/test_backend.sh /path/to/pinned/artex-global`. Developer image construction/reference comparison uses Docker; the signed VM acceptance runner itself does not call Docker. The developer bootstrap currently reuses the local browser image at a fixed content digest and verifies its ARM64 architecture/source label. A portable source-only release builder remains a distribution requirement.

## Failure investigation and prevention

1. System mount initially failed because the initramfs lacked `/sbin/modprobe`; ext4 could not autoload its CRC32C driver. Add the helper symlink and a packaging regression test. Actual VM mount now succeeds.
2. BusyBox `blkid` did not support the util-linux filtering contract assumed by initialization. Detect the actual ext4 type in its output; otherwise scan the entire disk before permitting a format. Unknown nonblank filesystems are refused.
3. The original zero-disk `head`/`cmp` pipeline triggered guest kernel memory faults during `head` teardown. The underlying kernel issue is not claimed resolved. Replace that scan with a bounded 1 MiB Python reader, verified against a nonzero last byte; the real guest now completes initialization. No broad kernel reliability claim follows from this workload change.
4. Default-input `stty` failed after switching root. Explicitly address `/dev/hvc0` and stop on failure before sending credentials. Verify successful bootstrap without echoed tokens.
5. An unexpected PID 1 exit formerly produced a kernel panic/reboot loop. Keep the guest alive in an explicit error state, use `panic=0`, recognize kernel faults, and continue monitoring the serial error stream after readiness.

These findings used the observed timeline and causal chain, then repair and regression verification. No host-side agent execution was introduced. Persistent disks containing fixture secrets remain local under ignored `evidence/local`; delete only test fixture disks after inspection, never a user's application disk.

## Remaining gates

- App-bundled backend provisioning and first-run native authentication.
- URLSession/SSE/WebSocket integration, cancellation, interrupted stream tests and cloud API egress policy.
- Broader API fixtures, native screen interactions and screenshot comparisons for every feature; external native-control tool acceptance remains pending.
- Backup/migration/restore, portable image builds, source/license delivery, signing/notarization and clean-Mac installation.

Production resource hardening remains open: the console display reads at most 64 KiB, but the underlying serial log file does not yet have a rotation/quota policy. Add bounded logging and real flood/error tests before shipping an untrusted workload.

A coverage percentage has not been measured for this checkpoint; the test counts are not an 80% coverage claim.
