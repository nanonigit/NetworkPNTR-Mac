# Cloud egress preview startup verification

The signed VMProbe uses the same DesktopRuntime startup and stop methods as
the Mac app. It checks that a modified manifest is rejected before VM
creation. With the unchanged candidate it boots once in each mode. Both
reach the unauthenticated setup state, and only the explicitly enabled boot
registers the production provider listener. The disabled boot also rejects
a direct request to register that listener. Both stops remove the VM and
listener and satisfy the zero-NIC and no-share audit. The four-provider
synthetic transport regression then runs on a separate state disk.

The local ARM64 Release preview bundles the pinned guest and is ad-hoc
signed. Launch it with `open -n "/path/to/NetworkPNTR Mac Cloud Preview.app" --args
--cloud-egress`. The preview uses its own state and Keychain account. Without
the argument, the regular app startup policy applies. The activation probe
made no provider calls. Visual app launch, real API calls, provider controls
and frozen-browser comparison remain open.

See the [verification receipt](../evidence/llm/cloud-egress-activation-verification.json).

## Runtime screen status regression

The signed Release bundle, launched with `--cloud-egress` through Launch
Services, reached the native runtime-ready state with no virtual NIC or
host share. The Runtime screen still claimed cloud networking was off.
The Account screen reached local initial setup. This run did not create an
administrator credential or exercise the model list.

The static help string mixed isolation and provider access, and the
listener property was excluded from observation. The fix keeps isolation
visible and separately reports the listener's current state. This indicator
covers local relay availability. Provider reachability requires a model API
request. The pinned browser has no dedicated VM lifecycle screen, so the
native status is checked against the actual VM lifecycle.

The Swift regression run passed 1,084 tests, with one existing accessibility
test skipped. The signed VM activation probe passed the active and inactive
modes with separate fresh disks, and rejected a modified manifest before boot.

On the updated signed Release bundle, the native accessibility tree showed
the relay inactive while starting, active for supported providers after
readiness, and inactive again after a cooperative stop. The ready screen
still reported no host shares or virtual NIC, and the guest log independently
reported both counts as zero. The preview's dedicated test state was archived
outside the app's normal state location. No preview Keychain session existed.
The bundled guest manifest hash remained
`5bc88b952a14bfe695d091e384e666a2fa24a68a4eb97cea40e77dac18b6b290`.
