# B1 — finite backend boot preflight and blank-check diagnosis

The source-kernel candidate's intermittent memory faults remain unresolved. Earlier upload/handoff counter-evidence shows kernel memory-accounting faults and checker SIGSEGV on a truly zero2GiB disk, while init labeled every nonzero checker exit nonblank-state-disk. No formatting happened. Do not infer a host/hardware/Python/kernel cause or erase negative outcomes. This phase improves diagnosis and collects bounded real VM evidence; it does not qualify the kernel.

Keep full constant-memory disk scanning and formatting only on checker exit0. Checker CLI must return0only for a verified block device whose full read is zero,2only for observed nonzero data,3for invalid device/stat/read failures; unexpected exits/signals also map to execution failure. backend-init captures the exit under set-e, sends2to existing nonblank-state-disk and every other nonzero to state-blank-check-failed, then remains failed before mkfs. Preserve existing ext4 branch, mount options, DB readiness, bootstrap/secrets, users, permissions and all isolation. Unit tests execute only the isolated format-decision fragment with fake python/mkfs commands, never the real init or a real formatter on the host. Mock device checks for sample-file CLI tests; full-scan read-only regular-file tests remain.

VMProbe --backend-preflight artifacts NEW_PRIVATE_OUTPUT is one boot only. Reject existing output atomically and never touch application-support/browser/user disks. Create one private sparse2GiB state disk, reuse verified artifact loading and provisioning, wait bounded120seconds for ready, require four exact zero-isolation witnesses and absent provisioning secrets, GET auth/status and protected profiles only, require fresh auth contract/401, then cooperative stop. No account setup, profile mutation, task/agent command, cloud request, host folder or NIC. On failure force-stop this owned VM once and export only fixed report fields/categories; never raw errors/log/token/path strings. Fresh private raw logs/state remain ignored. Existing full backend probe defaults remain unchanged.

Core normalized report is independently testable without hardware: only fixed booleans/statuses and enum diagnostics, plus observed formatting stage. PASS requires readiness/auth/isolation/credential evidence, cooperative shutdown and no retained machine or diagnostic fault. Known nonblank and checker-failure categories stay distinct; old signal+nonblank evidence is retained as both observations. This diagnoses observations, not causes or disk integrity by log text alone. Full logs stay private. No secret parameters enter the serialized report.

First inspect authoritative processes/hash inputs. Perform at most one fresh unchanged source-profile preflight, preserve its outcome. Build the changed init in a separate offline Linux container/candidate with exact package inventory and unchanged source kernel; do not replace old/default artifacts or browser containers. Run one fresh new-profile preflight; no repeat-until-green, no promotion/reliability acceptance from success. Build process may use Docker, runtime CLI must not invoke it. Record hashes/recipes/normalized outcome and private local fixture location separately. If compilation/boot cannot progress, preserve exact blocking evidence and continue independent authorized work.

Requirements→design→tests RED/GREEN→review→full regression→signed probe/build→controlled hardware evidence and bilingual verification. No Lazyweb because no product UI change. New guest error marker flows through the existing generic fail-safe VMController path; this phase adds no localized UI behavior. Reliable repeated boot/recovery, actual native click/browser equality, all21features, native cloud egress and distribution remain open.

Complete-log evidence correction: controller.guestLog is only a64KiB display tail. After this VM has stopped, inspect one complete bounded8MiB owned log snapshot for diagnostics, isolation witnesses and provisioning-token absence together. Invalid/missing/ambiguous/oversized/changing input makes audit unavailable and PASS impossible. Report accepts a normalized complete audit, never the display-tail string. Test an early memory/signal fault followed by100KiB clean output, with all other readiness/API/stop evidence valid. No-Fault means no recognized fault in this complete snapshot, not proof of kernel reliability.

### Rebuild the static checker candidate

The static checker experiment is a developer-only Linux ARM64 build. It requires the reviewed Cloud Preview guest artifacts and the cached pinned runtime and compiler images on the local Docker Desktop builder. The checker and its ten syscall fixtures compile inside the container. The build command verifies the control artifacts, extracts the rebuilt disk, confirms the original checker binary digest, and publishes a fresh private diagnostic manifest. The release packager still requires the exact reviewed Cloud Preview manifest.

```sh
python3 script/build_static_blank_checker.py \
  --control 'dist/NetworkPNTR Mac Cloud Preview.app/Contents/Resources/Guest' \
  --output .build-cache/new-static-checker-guest
```

The compiled checker is reproducible against the experiment digest. The image and ext4 filesystem can differ because the builder records timestamps and the formatter assigns fresh filesystem metadata. With the signed VMProbe binary, run `--backend-preflight` against the candidate and an unused private output directory. It uses an isolated VM and a new disk. See [current boot observations](bugs/guest-boot-investigation.md).

### Isolate system disk caching

A Debug VMProbe can compare explicit `cached` and `uncached` attachments with the exact same guest. Apple exposes these modes on the [disk image attachment API](https://developer.apple.com/documentation/virtualization/vzdiskimagecachingmode). Only the system attachment changes its cache setting. It remains read-only and retains full synchronization. The writable state disk uses the original attachment, with a fresh private file for every attempt. The probe uses the existing read-only API and isolation checks. Cloud egress and Release builds reject the diagnostic override.

```sh
VMProbe --system-disk-cache-preflight uncached /path/to/verified/guest /path/to/new-private-output
```

Use an ordered comparison with a fixed number of runs. A successful boot does not establish that the cache mode fixes a prior fault. Use the normalized stopped-log audit and retain all outcomes.

### Preserve the observed kernel failure in the app

Treat the existing panic and Oops log markers as a typed guest kernel fault. Preserve the first observed kernel failure for that VM through later log reads and stop errors, and clear it when a new boot begins. The connection failure screen shows the same localized kernel message as Runtime and keeps its Runtime navigation action. Runtime keeps the existing stop and retry controls. Lazyweb's Rarible initialization-error example informed putting the explanation and next action together. The app reports the observed failure category and does not diagnose the underlying kernel cause.
