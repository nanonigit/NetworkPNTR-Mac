# Source-built kernel verification (2026-10-23)

Status: functional candidate, not release qualification. Two independent same-host builds produce identical kernel/config bytes.

## Inputs and construction

Upstream Linux 6.12.114 and LinuxKit ARM64 configuration commit f935f6b18cad69f08c1830b432d7dab90bf67614 are pinned in guest/kernel/source.lock.json, with the Alpine builder digest, a 73-package exact inventory and explicit overrides. The build resolves to 6.12.114-artex, GCC 14.2.0, one-vCPU runtime, direct ext4 root and built-in virtio/vsock drivers. GCC stackleak remains enabled. Actual compilation uses a fresh private Linux ARM64 container with network=none, no host mounts, all capabilities dropped, no-new-privileges, two CPU compilation jobs, 3 GiB memory and 512 processes. App runtime invokes neither Docker nor host guest executables. Source acquisition is a separate HTTPS step; PGP signatures were not verified.

The source archive, configuration, COPYING, configuration license and LICENSES archive are retained locally in ignored guest/source-kernel-artifacts. Git records hashes and normalized evidence, not the generated binary/source archive. Corresponding-source distribution/legal review remains a release gate.

## Observed results

- 42 Swift tests and 24 Python tests pass. The read-only Python review approved provenance, local builder selection and negative-test fixes. GitHub Actions run 39837058467 passed for ab22995649ee8764cdc2dcdddad6fdc9434d08b0.
- First successful offline source build: kernel SHA256 8e57308787c420cb42e4c4ea80e6def6438a52232692c010dc4609bb9bf21879; resolved configuration f270a97fe4830adda7bf66b2f98c12b5e1c7be36fb8a323a9c36f3b4867d2b49. Recipe and toolchain evidence are in evidence/source-kernel.
- Signed VMProbe completed six boots: fresh setup, normal restart, three forced recoveries, and rejection of a nonblank invalid disk without formatting. Authentication, DB credentials/JWT and an LLM profile survive recovery; unauthenticated transport and protected APIs are rejected. Hardware NICs, active nonloopback interfaces, external routes and host shares are all zero. Five normalized backend contracts match a disposable pinned browser backend.
- The signed .app completed fresh setup, actual Keychain restoration after restart, login/validation, logout cleanup and cooperative stop during startup. Its actual guest LLM CRUD/key preservation/pool/retry checks and populated dashboard diagnostics pass. Eleven LLM contract groups and twelve dashboard scenarios match disposable pinned reference instances and independent browser calculations. User browser data is untouched.
- Previous LinuxKit diagnostic kernel/system hashes still match. The new candidate is assembled separately under .build-cache/backend-source; the standard backend source recipe is not promoted. A retired failed 6.18 cache was removed after preserving its manifest/hash inventory locally; no user data or unrelated Docker storage was pruned.

## Repeated native verification

Three consecutive fresh-disk signed-app diagnostics pass on this source-kernel candidate (nine native boot attempts). Normalized LLM and populated dashboard results agree across all three. Runs 2 and 3 used PATH=/usr/bin:/bin and an unusable DOCKER_HOST Unix socket; they did not require a Docker CLI or that endpoint. Docker Desktop remained running for the preserved browser baseline, so this is not a clean-Mac or Docker-Desktop-stopped installation test. The app was rebuilt/ad-hoc signed after the chat model foundation, and current Swift tests total 49; all 24 Python tests still pass. See repeated-native-summary.json and native2/native3 normalized results in evidence/source-kernel.

## Limits and next gates

The second compilation completed from the same verified source in a new private container, reusing dependency-image layers but no compilation output. Image, resolved configuration and build-report hashes agree. All retained hashes agree except LICENSES.tar.gz: license members/content/file metadata agree, while directory timestamps differ. Builder manifest identities also differ; no byte identity of whole builder images is asserted. The second build log marks all dependency-image instructions cached. Evidence/source-kernel/rebuild-comparison.json records both sets of hashes and limits. This proves same-host kernel/config reproducibility for these two builds, not cross-host or complete-package reproducibility. Repeat fresh native/lifecycle workload tests after a final selected recipe; intermittent earlier two-vCPU faults remain unexplained. These tests establish functionality on successful runs, not long-run reliability.

Internal .app/service diagnostics and diagnostic content snapshots do not replace external click/visual acceptance. Cloud API egress, streaming, interception/capture, remaining features, migration, clean-Mac installation, signing/notarization and whole-product browser parity remain open.


Later counter-evidence: the fresh signed upload-a2-v1 run on this same one-vCPU source candidate panicked before bootstrap in anon_vma_clone/__split_vma/munmap. See bugs/guest-boot-investigation.md and evidence/chat/upload-a2-boot-red.json. Byte reproducibility and earlier passing runtime runs do not imply release reliability; the candidate is not promoted.
