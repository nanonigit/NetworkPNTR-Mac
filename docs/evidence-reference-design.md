# F5d independent reference comparison

Requirements: retain native9b41048 evidence; run the exact pinned backend in an owned disposable Linux/arm64 container, nonroot1000, network-none, readonly root, no bind/volume/ports/capabilities. Preserve original containers/images/tags. No agent/provider/external targets. Infrastructure/API work; Lazyweb and product UI are out of scope here.

BR1: independent Python http.client with fixed loopback API routes, bounded JSON and streaming octet responses, identity/length/framing/status checks, deadline and full byte comparison against the guest's deterministic source blob. Save complete response files exclusively0600 in fixed body/boot locations. Test partial reads, corrupt/truncated/extra/encoded responses and route/header guards.

BR2: fresh auth, fixed fixture.prepare(), all4 bodies and preview metadata, cooperative backend stop/restart, persisted auth/metadata/body data, fixture audits before/after. Hash pinned executable and all source inputs. Audit bounded logs for generated credentials and observe network isolation at both ends. Main entry rejects host execution before file/process operations.

BR3: controlled Docker orchestration uses cached image IDs only, no network build. Copy fixed reference downloads out into a new private diagnostic folder (no host mount into container). Independently compare all8 copied files byte-for-byte to the corresponding native boot files and expected full hashes; validate no symlinks or extra paths. Observe process exit0, isolation, source/binary/native bindings, database/log export and owner-scoped cleanup. Keep failures; never silently retry them away. Only sanitized summaries enter Git.

BR4 remains open: actual browser/native UI, detailed preview display/binary/truncation parity, nonempty captured picker and bind/edit/remove/order/conflict behavior, and full product acceptance. Body API equality does not close those gates. All pushes obey exhausted Actions quota policy.
