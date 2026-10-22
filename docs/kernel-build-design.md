# Source-built guest kernel: requirements, design and tests

## Requirements

K1. A clean developer machine can construct the candidate kernel without reading Docker.app resources. Pin Linux source, base configuration, compiler environment and local overrides; verify hashes before use. Kernel compilation and source build scripts execute only in a Linux container. The app runtime continues to use Virtualization.framework with zero NICs/shares and no Docker invocation.
K2. Keep the working diagnostic profile intact. The new candidate must support direct read-only ext4 root, private ext4 state, virtio console/block/RNG and authenticated vsock with built-in drivers. Begin with one virtual CPU, an explicit tested resource profile, without claiming it fixes the unexplained two-CPU faults.
K3. Generate source/configuration/package/kernel digests, compiler and deterministic build metadata; retain upstream license files and source archive for later distribution review. No claim of byte reproducibility until independently rebuilt hashes agree. No distribution/notarization acceptance from a successful build alone.
K4. Reject corrupt downloads, path/symlink substitution, wrong architecture/driver configuration and mismatched profile artifacts. Source download and dependency acquisition may use HTTPS; actual compilation runs with network disabled. Do not disable TLS validation. Never mount Docker socket or user folders into the runtime guest.

## Chosen experiment

Use upstream Linux 6.12.114 (archive SHA256 7a8589912bd7a8adb07fed074283652cf482a35facef8954554654f0154b4af3 from kernel.org's HTTPS checksum listing), based on the already pinned Alpine guest's kernel series/version. Use LinuxKit's ARM64 configuration at f935f6b18cad69f08c1830b432d7dab90bf67614 (SHA256 53280e08ae286156a31049c90ab8b2077db93c0366a8a9e6bb4b3fa7c02f65fe), adapted by explicit reviewed overrides. This is a new configuration/version experiment, not a byte-for-byte reconstruction of Docker Desktop's 6.12.76 kernel. Keep its earlier comparison evidence separate.

LinuxKit documents kernel configurations, build inputs and custom builds at https://github.com/linuxkit/linuxkit/blob/master/docs/kernels.md. Source archive/checksum origin: https://cdn.kernel.org/pub/linux/kernel/v6.x/sha256sums.asc. HTTPS/hash validation is recorded; do not claim a PGP signature was verified without performing that check.

Use an Alpine 3.22.7 builder image pinned by digest and an exact package inventory. Download source/config bytes into an ignored cache with size and hash checks; no source extraction on macOS. Docker receives a minimal generated build context, uses no host filesystem mounts and compiles offline with bounded jobs. Set deterministic timestamp/user/host/build version and disable local Git-derived version suffixes. Disable module loading and debug symbols; explicitly build required vsock/block/ext4/console/entropy drivers into the kernel. Preserve hardening controls. Validate the resolved configuration before compiling.

Keep kernel artifacts separate from backend/system artifacts. A profile assembler verifies both inputs and emits a direct-root, one-CPU backend manifest with source provenance. Default app build inputs are not silently replaced. Promote only after real VM and native-service tests pass; unresolved runtime failures remain release blockers.

## Test sequence

1. RED → GREEN Python tests for source locks, bounded/mismatched cache downloads, ARM64 Image magic, required resolved config and profile integrity/path/symlink failures.
2. Build in the isolated container; inspect package/config/source provenance, licenses and ARM64 Image. Confirm compilation has no network.
3. Assemble a candidate with the unchanged verified backend system image; run signed VMProbe normal/forced restarts and invalid-disk preservation, then fresh signed native auth/LLM/dashboard diagnostics. Compare existing normalized browser contracts.
4. Rebuild without the compilation cache and compare kernel hashes. Test repeated fresh disks, lifecycle errors, startup cancellation and representative workload; a single successful boot is insufficient.
5. Review source/build boundaries, record failures and corrections in English/Japanese, push and verify CI. Leave source distribution, backend-from-clean-source assembly, final stability and all product/UI gates open until separately proven.

This is infrastructure work; Lazyweb is out of scope. Disk budget: inspect free space before build; keep this experiment below 8 GiB of additional host storage and never prune unrelated Docker images or user data.

## Developer commands (candidate only)

```sh
python3 script/prepare_kernel.py
python3 script/assemble_source_profile.py --backend guest/backend-artifacts --kernel guest/source-kernel-artifacts --output .build-cache/backend-source
ARTEX_MAC_GUEST_BUILD_DIR="$PWD/.build-cache/backend-source" script/build_and_run.sh --build-only
```

Outputs must not exist before construction. Each invocation compiles in a new private container; only dependency-image layers/downloads are cached. `--output .build-cache/kernel-source/rebuild2` selects a separate second compilation. Compare `Image` and `kernel.config` digests after both complete. No claim of successful candidate boot or reproducibility follows from these instructions.
