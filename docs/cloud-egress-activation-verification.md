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
signed. Launch it with `open -n "/path/to/ARTEX Mac Cloud Preview.app" --args
--cloud-egress`. The preview uses its own state and Keychain account. Without
the argument, the regular app startup policy applies. The activation probe
made no provider calls. Visual app launch, real API calls, provider controls
and frozen-browser comparison remain open.

See the [verification receipt](../evidence/llm/cloud-egress-activation-verification.json).
