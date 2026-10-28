# Four cloud-provider goal

User-requested extension: support OpenAI, Anthropic, Gemini and Groq as recognizable provider identities, with model selection, streaming and local tool use. Status: planned; Gemini/Groq have not been implemented or live-tested. Existing fixed-browser parity, custom endpoints, VM isolation and release gates remain required. This document covers provider contracts/network architecture, not UI layout; use Lazyweb before changing provider screens.

Current code: LLMFormat has anthropic, openai and openai-responses wire formats; LLMService sends that value as the backend provider field. Frozen agent/provider.go accepts Anthropic/OpenAI-format endpoints. A vendor is not a new wire format: do not simply add gemini/groq enum cases to that field and send unsupported backend values. Keep existing profiles and user endpoints unchanged.

| Identity | Initial route to evaluate | Requirements |
| --- | --- | --- |
| OpenAI | Existing Chat Completions / Responses | Preserve both formats and current behavior. |
| Anthropic | Existing Messages | Preserve current behavior and stream/tool contracts. |
| Gemini | Developer API, initially evaluate documented OpenAI compatibility | Preserve thought signatures/opaque tool history across full tool rounds; assess native API adapter if the pinned provider library loses necessary metadata. Vertex AI is separate future scope. |
| Groq | Documented OpenAI-compatible endpoint | Filter unsupported parameters and apply model-specific tool/parallel/reasoning capabilities. Do not assume all OpenAI options work. |

Official sources reviewed for the proposal: [Gemini compatibility](https://ai.google.dev/gemini-api/docs/openai), [Gemini function calling](https://ai.google.dev/gemini-api/docs/function-calling), [Groq compatibility](https://console.groq.com/docs/openai), [Groq tool use](https://console.groq.com/docs/tool-use/overview). Candidate base URLs are https://generativelanguage.googleapis.com/v1beta/openai/ and https://api.groq.com/openai/v1. Verify final request paths with the pinned client; never double-append v1 or send provider-specific fields blindly. Model IDs and availability are fetched/validated, not hardcoded as a promise that a particular model will remain offered.

Design: provider identity, wire format and model capabilities are separate. Built-in presets supply default URLs/capabilities while retaining explicit custom profiles. Exact recognized origins may help migrate old profiles; a custom gateway must not be relabeled automatically. Decide and test identity persistence/import/rollback rather than silently overloading the existing backend provider field. Keep the browser reference frozen; any necessary managed-backend extension is versioned independently with source/image hashes.

Network: all model requests and agent tools stay in the guest. The current zero-NIC proof does not provide cloud connectivity. Extend the separately designed egress gate for the exact provider HTTPS origins, including generativelanguage.googleapis.com and api.groq.com. Avoid wildcard Google domains and cross-origin key forwarding/redirects. Follow existing secret lifecycle/storage controls; no keys in chat, logs, Git or receipts, and scrub drafts after close/logout. Provider-hosted code execution, browser tools and remote MCP are not implicitly enabled by adding local function calling.

Phases:

- CP1: identity/format/capability and persistence contracts; backwards-compatible profile fixtures, exact URL/header/payload fixtures and endpoint-key isolation. No cloud calls.
- CP2: managed guest adapters and model discovery; provider-scoped mock SSE split frames, usage/error/cancel handling, tool calls and complete result round trips. Gemini signature preservation is an explicit gate. Disable unsupported fields and avoid silent fallback to another provider or automatic replay of tool actions.
- CP3: isolated egress negative tests, then minimal real model-list, text, stream and guest-only tool round trip for each provider using keys entered through the app. Test missing/wrong keys, 429/5xx, timeouts, cancel/VM-stop, retry/unknown outcomes and persistence. Record any live-test gaps; a mock greeting is not acceptance.
- CP4: en/ja provider controls, capability-aware validation, keyboard/VoiceOver and actual browser comparisons for shared workflows. Label added-provider workflows as extensions where no browser counterpart exists. Final acceptance requires four usable providers, not just four names in a menu.
