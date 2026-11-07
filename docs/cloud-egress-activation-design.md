# Cloud egress preview activation

The release app accepts an explicit `--cloud-egress` launch argument outside
native diagnostics. The preview uses a separate state directory and Keychain
account. The default startup uses the existing state and leaves the listener
closed. No settings screen changes are in this runtime phase.

The VM controller admits the preview only when the bundled manifest matches
the exact signed-probe candidate digest. It verifies the guest kernel,
initramfs and disk from that same manifest before VM creation. DesktopRuntime
requests the production broker after guest readiness and before authentication
is exposed. A boot without the preview request cannot open the production
listener. Existing stop and failure paths retire the listener.

Test manifest acceptance and rejection, then exercise normal DesktopRuntime
startup with the production listener both enabled and disabled. Inspect
readiness, authentication availability and listener retirement after stop.
Use a fresh state disk and no provider keys or requests during this test.

The Runtime screen must distinguish a guest with no virtual NIC from an active
provider-only relay. Show the listener's live state in English and Japanese,
including the transition back to inactive when the VM stops.

Read the observable listener state directly from the controller. Keep the
isolation line scoped to virtual NICs and host shares, and place the provider
relay status alongside it.

Check both catalog variants, then start the signed release through Launch
Services. Verify the enabled label after readiness and the disabled label
after stopping the same VM. The default launch policy remains the offline case.
