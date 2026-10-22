# LLM settings comparison checkpoint

Status: implemented, partial native acceptance; not feature-complete or release accepted. The full 21-feature app goal is unchanged.

## Evidence

- Thirty Swift tests pass, including wire fields, empty-key edits, format-dependent output cap, retry bounds, credential redaction, malformed/error responses, authenticated-service request construction, partial settings updates and retention of previous data after load failure. A confirmed create remains successful if only its subsequent refresh fails, preventing accidental duplicate retries. Fourteen Python tests also pass; a coverage percentage is not claimed.
- The real ad-hoc-signed .app uses the selected one-vCPU direct-root diagnostic VM, actual ARTEX/PostgreSQL, authenticated vsock and actual Keychain. `evidence/llm/native-service-results.json` records three-format CRUD, blank-key preservation, active deletion protection, rotation/exclusion/reset, retry roundtrip and persistence after VM restart. The harness itself does not click controls; its false UI-click field is not an aggregate verdict about separate CUA tests.
- `api-contract-comparison.json` reports eleven grouped contracts equal to the disposable pinned browser backend. No published ports, host mounts, browser DB mutation, real API key or paid cloud requests are used. `script/compare_backend.py <vm-contract> <output> --kind llm` runs the separate `llm_contract_fixture.py` only inside that reference container.
- External CUA really opened the sidebar's LLM screen, inspected every profile editor control, rejected invalid numeric text, corrected it, changed Anthropic to OpenAI and observed the cap-field picker enable, received a real missing-key model error, created a profile, edited its name/rate/streaming, saved with Return, activated it and saw deletion disabled, then restored the previous active profile. See `external-ui-results.json` for the bounded scope.
- Independent CUA screenshots are `native-profile-cards.png` and `browser-profile-cards.png`. They compare navigation, card fields/actions and layout, using different fixture records and different viewport/pixel scales. They are not a pixel-equality or identical-data visual acceptance. The existing browser tab was returned to its original dashboard, and a later temporary reference tab was closed.

## Differences and open gates

The native client uses SwiftUI split navigation, system forms, secure inputs, segmented tabs and an editor sheet instead of browser drawers. It retains all profile parameters and exposes loading/failure feedback; transient fetch failures do not masquerade as an empty account. Native list cards say that a proxy is configured instead of exposing possible credentials in its URL. Provider-test errors are shown generically to avoid reflecting credentials in raw error bodies. Numeric validation is explicit, while empty numeric fields preserve the browser's zero/default semantics.

The CUA native pipe closed while switching to global retry. The app was verified alive; another state read and a fresh CUA session still failed. Do not count that click as successful. Rotation/global-retry external interactions, final delete confirmation, resize/light mode/accessibility audit, positive model-list and real provider-reply UI, controlled egress, request interruption and full visual comparison remain pending. Internal rendering captures or API tests do not waive them.

The one-vCPU LinuxKit kernel is still a local diagnostic input; portable source build/licensing, long-run reliability, bounded serial logging and release packaging remain independent gates. Two-vCPU intermittent guest kernel faults have not been explained or declared fixed.

## Reproduce the native fixture

Prepare the pinned backend guest with the developer builder. The diagnostic kernel profile is not a release input and must be prepared separately as documented in the boot investigation. Build with `ARTEX_MAC_GUEST_BUILD_DIR=/path/to/verified/profile script/build_and_run.sh --build-only`. Run the generated executable with `--native-diagnostics /private/fresh/fixture-directory`; it creates its own disk and temporary Keychain account, then cleans the account and stops its VM. `--native-review` holds that authenticated fixture for at most fifteen minutes. Creating the fixed `native-review-finish` marker in that fixture directory resumes cleanup; it accepts no commands or guest payload and exists only in DEBUG builds. Never reuse a real user's state directory for fixtures.
