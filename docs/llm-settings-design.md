# Native LLM settings: requirements, design and tasks

## Scope and baseline

Continue the complete app goal. Implement the browser LLM screen at pinned e75ae371ad777ffd1eecdd28d2781a6519b05591, not a subset presented as complete. Reference: web/src/app/(main)/system/llm/page.tsx, its _components/retry.tsx, web/src/lib/api.ts and types.ts, server/dto.go and db/llmretry.go. Live browser inspection confirms two profile cards, New/Rotation settings controls, Model profiles/Retry & backoff tabs, and the full new-profile sheet. Inspection is read-only; existing profiles/keys remain untouched.

Lazyweb search `desktop API key model settings` (desktop, 2026-10-22) returned V7 Labs site 251005 (AI model list with connect-key actions), Knock 252246 (API-key settings with navigation), Aider 218608 (advanced model configuration). These are metadata/description references, not claimed image inspection. Keep list-to-editor navigation, labeled fields, clear active/health status and separated advanced groups; ARTEX's controls and behavior remain authoritative.

## Controls and behavior

- Profile list: name, format, model, masked key hint, limits, proxy, reasoning effort, active badge, health/cooldown, priority/exclusion when rotation enabled. Create/edit/save, activate, delete inactive only. New profiles are not automatically activated. Blank key on edit preserves the stored key. Never fetch/reveal that key or import browser credentials.
- Editor: name/model required; three formats (anthropic/openai/openai-responses); base URL, proxy, custom session-header name, secure API-key field; RPS/RPM; context window K; priority/exclude; streaming; output cap and openai-only cap field; thinking type and reasoning effort independently; three per-profile retry layers with count/interval.
- Model retrieval and connection test use actual backend endpoints and include the saved profile ID when editing, so an empty key uses the stored key. Show loading and success/failure; no fabricated model list/reply. Outbound networking remains a separate pending gate. Tests use isolated fixtures, not paid cloud requests.
- Rotation sheet: enabled/bound-profile fallback switches, actual ordered chain and health, individual/all reset; refresh every ten seconds only while open, enabled and degraded/tripped. Partial settings PUT must not overwrite unrelated settings.
- Global retry tab: connect/empty/stream/breaker/intent count and interval; 0 inherits defaults, -1 disables a layer; match backend clamping [-1,20] and [0,3600000ms]. Preserve unsaved edits until save/reload is explicitly requested.
- Native feedback: inline load/save failures, visible busy state and keyboard access. Keep existing data on transient errors and label it stale; do not show a failed load as an empty account. Never log raw API error bodies or key/proxy credentials.

## Architecture

ArtexCore owns Codable response types, a validated draft encoding every browser field, an authenticated finite-JSON adapter and LLM service/store. Decode snake_case consistently, including string response IDs versus numeric mutation IDs. Response models contain hints only, never api_key. Draft keys are view-local and transmitted only over authenticated vsock; no host plaintext persistence. SwiftUI owns profile cards, editor, rotation and retry views. RootView connects this feature only after actual authentication; all comparison rows remain pending until interaction/visual and end-to-end gates pass.

## Tasks and tests

1. DTO/draft tests: exact wire fields and defaults, three formats, blank-key preservation, response IDs, Unicode/trim and numeric validity, openai-only cap normalization, header injection rejection, retry bounds, no plaintext key in response/log descriptions.
2. Service tests: authenticated calls, list/save/activate/delete; reject active deletion; surface 401/503/malformed JSON; failure preserves editor/list; model/test include saved ID and all applicable parameters; partial rotation settings and retry-policy save/read.
3. Native implementation: render loading/empty/error/profile states, all editor fields, rotation controls and global retry. Compare control inventory against live browser. Do not count placeholder or disabled functionality as passed.
4. Real signed app: same fixture CRUD/activation/key-preservation/retry/pool operations and persistence through the dedicated VM; compare normalized results against a disposable pinned browser backend. Verify negative missing-key/model-test behavior without external calls.
5. External native click/keyboard, screenshot pairs, resizing/dark/light/accessibility, edited-form preservation, cancellation/interrupted requests. Native-control connector is currently unavailable; internal service/rendering diagnostics cannot satisfy this gate.

Gate status: screens and services implemented; thirty Swift tests and the real native fixture pass. Eleven grouped reference contracts match; external CUA confirms create/edit/validation/Return-save/activation. Full workflow acceptance remains open; see docs/llm-settings-verification.md. Runtime reliability and portable kernel/source-license delivery remain independent gates.
