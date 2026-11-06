# Provider menu verification

Reviewed the frozen browser source at
`e75ae371ad777ffd1eecdd28d2781a6519b05591`, the earlier browser control
inventory, and the captured browser settings image. The browser places New
next to Rotation above the profile cards. The Mac keeps that placement and
adds the provider choices to New.

| Workflow | Frozen browser | Mac |
| --- | --- | --- |
| New manual configuration | New opens the blank editor | New → Custom Configuration opens the blank editor |
| Start from a provider | Choose format and enter the endpoint in the editor | New offers four provider presets as a Mac extension |
| Enter credentials, retrieve models, test, save | Explicit editor actions | Existing explicit editor actions |
| Edit a saved configuration | Open the existing profile | Existing edit action and key hint |

The focused tests constructed all five editor choices offscreen in English
and Japanese, checked fresh IDs and empty credentials, and recorded zero
requests on construction. The provider contract tests exercised explicit
model discovery and save through a controlled transport. The bilingual
catalog matrix includes the custom menu item. The ARM64 preview was rebuilt
and strictly signature-verified with the same guest manifest.

Interactive menu selection, keyboard navigation, VoiceOver, live APIs and
the current native/browser visual comparison remain open.
