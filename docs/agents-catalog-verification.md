# Agents catalog verification

The native Agents screen is read-only and requires a live authenticated guest session. It preserves the order of `GET /api/agents`. It shows the built-in/custom and disabled labels, raw agent keys, descriptions and MCP, skill and tool counts. Missing counts are zero. An unsuccessful request has a dedicated error state and a reload control.

The browser comparison used `e75ae371ad777ffd1eecdd28d2781a6519b05591`, the Agents page, its agent localization helper and the list DTO. All 22 shared strings per locale match the frozen browser messages, including the seven seeded names and descriptions. The screen localizes the browser's literal “Skill” label in Japanese. The Lazyweb Superhuman Agents result reinforced the card hierarchy. Custom values remain verbatim.

A signed diagnostic build displayed all eight default records in an authenticated, isolated Linux VM. The order and all 24 binding counts matched the separately authenticated disposable Docker reference. The reference returned HTTP 401 before authentication. The VM screen reloaded after switching English to Japanese and retained all eight cards. Each card had a separate accessibility container. The fixture exposed the Korean reporter seed. Native display now translates its exact default name and description independently, preserving edits, and both locale runs showed the translated card. The browser continues to show the raw seed.

Local results were 1,055 passing Swift tests, one existing skipped test, and 195 passing guest artifact tests. The release build and strict signature verification of the local preview passed. Both diagnostic VMs stopped and removed their temporary Keychain items. Their private guest state was discarded and the reference containers and network were removed.

Run `swift test --filter AgentCatalogTests` for the transport, field, localization and cancellation checks. Run `python3 script/export_localizations.py --check` to verify the generated bundle resources.

Agent creation, deletion, details, prompt editing and settings changes are pending. Paired browser/native GUI comparison, keyboard and accessibility acceptance and hosted CI remain open.
