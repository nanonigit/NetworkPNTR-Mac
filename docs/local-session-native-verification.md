# Automatic local sessions: signed native service verification

[English](local-session-native-verification.md) | [日本語](local-session-native-verification.ja.md)

The ordinary installed applications and user data remain unchanged. Normal login-free startup is still gated on visible EN/JA acceptance and deployment checks. The following are service diagnostics in separately signed disposable application bundles, not full UI or release acceptance.

Four cases passed on their first recorded attempt: ordinary fresh startup/restart, ordinary legacy-password migration/restart, cloud-variant fresh startup/restart, and cloud-variant legacy migration/restart. There were eight boots total. Each variant retained its original kernel, CPU and 2 GiB memory profile; the ordinary variant used two CPUs and the cloud variant one. No repeated-until-green or alternate-kernel promotion was used.

Each run checks pinned source/artifact identity, ordinary JWT protection (401 without it), automatic internal authentication and restart, existing bcrypt hash, stored synthetic provider keys/profiles, complete seeded terminal task/activity rows and a real Int64 API aggregate. Fresh-local cases additionally reject the previous boot's capability with403. The tool child must not inherit the local-session capability. After cooperative stop, exactly two bounded full guest logs must contain all isolation witnesses, none of either boot's exact provisioning/JWT/test secrets, and no classified fault. No raw secrets, user data or VM disks enter the normalized receipt.

The diagnostic now fails with nonzero exit status on admission, execution or report-write failure. Report publication is checked; a writer-failure regression covers propagation. MCP revocation is also tested through a real local IPC client with a controlled API: a401 revokes its grant before another backend dispatch, and reconnect cannot restore that grant or replay the mutation.

[Native receipt](../evidence/local-session/native-service-verification.json). These eight boots do not close the separately tracked intermittent boot-reliability gate. Native GUI entry, EN/JA and paired browser feature checks remain pending because the Mac is locked.

The cloud composite's original candidate retained stale parent `managedBackend` identity. Its corrected manifest retains that parent separately and identifies the actual new binary and `dev` build version. Kernel, initramfs, system disk and backend bytes are identical. [Corrected manifest](../evidence/local-session/cloud-composite-manifest.json). A regression binds its bytes to the Core whitelist and checks that the composite and parent hashes differ.

Live cloud regression did not pass: four intentionally invalid-key model-list requests produced no confirmed upstream status. The unchanged backend control also failed all four with `unexpected-eof`, as did the instrumented automatic candidate. System curl reached the same OpenAI host with401, includingTLS1.2, while a diagnostic of the production C transport timed out in TCP setup before TLS. The cause remains unproven. Preserve all failures; do not disable peer/certificate checks or mark cloud acceptance green. See [the investigation](bugs/local-session-cloud-egress.md) and [the receipt](../evidence/local-session/cloud-egress-regression.json).

The corrected owned-tag cleanup also passed actual Docker checks for both candidate images: temporary aliases were removed with parent pruning disabled and durable input references survived. Original pre-update bundle artifacts remain available. Initial loss of two dangling image-cache references is retained in the earlier checkpoint; this verification does not pretend those original cache identities were restored.
