# Automatic local sessions: signed native service verification

[English](local-session-native-verification.md) | [日本語](local-session-native-verification.ja.md)

The initial checkpoint predates deployment to the ordinary and Cloud Preview bundles. See the November 19 update below for current status. The following are service diagnostics in separately signed disposable application bundles, not full UI or release acceptance.

Four cases passed on their first recorded attempt: ordinary fresh startup/restart, ordinary legacy-password migration/restart, cloud-variant fresh startup/restart, and cloud-variant legacy migration/restart. There were eight boots total. Each variant retained its original kernel, CPU and 2 GiB memory profile; the ordinary variant used two CPUs and the cloud variant one. No repeated-until-green or alternate-kernel promotion was used.

Each run checks pinned source/artifact identity, ordinary JWT protection (401 without it), automatic internal authentication and restart, existing bcrypt hash, stored synthetic provider keys/profiles, complete seeded terminal task/activity rows and a real Int64 API aggregate. Fresh-local cases additionally reject the previous boot's capability with403. The tool child must not inherit the local-session capability. After cooperative stop, exactly two bounded full guest logs must contain all isolation witnesses, none of either boot's exact provisioning/JWT/test secrets, and no classified fault. No raw secrets, user data or VM disks enter the normalized receipt.

The diagnostic now fails with nonzero exit status on admission, execution or report-write failure. Report publication is checked; a writer-failure regression covers propagation. MCP revocation is also tested through a real local IPC client with a controlled API: a401 revokes its grant before another backend dispatch, and reconnect cannot restore that grant or replay the mutation.

[Native receipt](../evidence/local-session/native-service-verification.json). These eight boots do not close the separately tracked intermittent boot-reliability gate. Native GUI entry, EN/JA and paired browser feature checks remain pending because the Mac is locked.

The cloud composite's original candidate retained stale parent `managedBackend` identity. Its corrected manifest retains that parent separately and identifies the actual new binary and `dev` build version. Kernel, initramfs, system disk and backend bytes are identical. [Corrected manifest](../evidence/local-session/cloud-composite-manifest.json). A regression binds its bytes to the Core whitelist and checks that the composite and parent hashes differ.

Live cloud regression did not pass: four intentionally invalid-key model-list requests produced no confirmed upstream status. The unchanged backend control also failed all four with `unexpected-eof`, as did the instrumented automatic candidate. System curl reached the same OpenAI host with401, includingTLS1.2, while a diagnostic of the production C transport timed out in TCP setup before TLS. The cause remains unproven. Preserve all failures; do not disable peer/certificate checks or mark cloud acceptance green. See [the investigation](bugs/local-session-cloud-egress.md) and [the receipt](../evidence/local-session/cloud-egress-regression.json).

The corrected owned-tag cleanup also passed actual Docker checks for both candidate images: temporary aliases were removed with parent pruning disabled and durable input references survived. Original pre-update bundle artifacts remain available. Initial loss of two dangling image-cache references is retained in the earlier checkpoint; this verification does not pretend those original cache identities were restored.

## November 19, 2026 deployment

Both locally signed build 3 bundles reached the dashboard on direct launch and after a cooperative stop and restart. The ordinary build reused its existing private state disk. Cloud Preview selected its dedicated disk and allowlisted provider route from its bundle metadata without command-line arguments. An account row and password prompt were absent. The disposable native app switched Japanese → English → Japanese through the visible picker. The English dashboard's Source label still wraps at the tested window width.

After the user changed Little Snitch to Allow, the signed VM diagnostic confirmed OpenAI, Anthropic and Groq returned HTTP 401 and Gemini returned HTTP 400 with an invalid-key error. The previous failures remain recorded above. Authenticated model listing, inference and repeat network reliability remain open.

The local suites recorded 1,227 Swift cases with one skip and 222 Python cases, with no failures. Browser inventory matched the pinned baseline (21 navigation features, 27 routes and 243 handlers). Full workflow and UI parity remain open. See the [deployment receipt](../evidence/local-session/deployment-verification.json).

## November 25 local Release candidate

`./script/build_and_run.sh --release-build-only` built the ordinary and Cloud Preview candidates with the Docker Desktop socket absent. Both candidates passed app and bundled-helper signature checks, and their guest bytes matched the reviewed packaging inputs. A mismatched guest variant was rejected without changing the development executable. The builds use local ad-hoc signing.

On Apple M2 with macOS 27.2.1, the ordinary Release app used a new private test application-support directory. Its automatic first boot reported a kernel Oops at the blank-state disk check. After stopping that failed VM, starting from the runtime screen on the same private disk reached the dashboard without prompting for credentials. Quitting stopped the guest cooperatively. Opening the app again reached the dashboard on the existing formatted disk and stopped cooperatively on Quit. Both successful boots recorded zero NICs and host shares. The fault is still open. Cloud Preview packaging was verified, and its Release runtime, clean-Mac installation and distribution signing remain open. [Verification record](../evidence/native-runtime/local-release-packaging.json)
