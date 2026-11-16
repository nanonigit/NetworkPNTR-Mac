# Inbound MCP capability contract

Status: core read broker under test; no registered stdio server, IPC endpoint or GUI approval flow yet.

| Tool | Arguments | Authorization | Shared native service | Execution owner |
| --- | --- | --- | --- | --- |
| `artex_agents_list` | Empty object, no additional properties | Agent discovery | `AgentCatalogService.list`, GET `/api/agents` | External AI; no internal inference |
| `artex_task_status` | Required `id`, canonical positive decimal string, no additional properties | Task status plus exact task ID allowlist | `TaskService.detail`, GET `/api/tasks/{id}` | Read existing task; no inference is started |

Both future tool descriptors must set read-only and idempotent annotations. These annotations are hints; the app broker enforces the actual route, scope and account/runtime ownership. Account credentials stay inside `AuthenticatedBackendClient`; they are never MCP arguments or output.

Agent responses contain only key, localized name and enabled state. Task responses contain decimal-string ID, status, paused/queued flags and exact Int64 input/output token counters. The protocol adapter must preserve these integers without JavaScript-number coercion. Prompt content, command output, provider secrets and raw task content are excluded from these projections. Tokens describe existing task usage, not a new model call.

The app issues opaque in-memory grants after client authorization. Grants expire on app restart and are bound to both the authenticated account epoch and current VM epoch. A revoked or changed epoch rejects dispatch and suppresses an in-flight response. The IPC server must authenticate a per-client connection, retain its own grant mapping, and never expose `authorize` as an MCP tool. The initial broker bounds grants to 128 and explicitly allowed tasks to 1,000 per grant. IPC framing, pending-call limits, authenticated helper identity and request deadline enforcement remain implementation gates.

Task creation, start, resume, stop, skill instructions, findings and isolated tool execution remain unimplemented in MCP. In particular, the existing task creation and resume routes can schedule internal agent inference. External-AI mode must add and verify execution ownership through the backend lifecycle before exposing these writes. ARTEX-agent delegation will use separately named tools with explicit model configuration and separate usage. Destructive actions, recording sensitive values, mock/session substitution and target-domain expansion must retain the API Recon consent requirements; a generic MCP connection grant does not authorize them.

Core checks use the fixed browser task-contract fixture `e75ae371ad777ffd1eecdd28d2781a6519b05591` and existing typed native services. This is a wire-contract comparison only. Browser/native/MCP rendered workflows, real stdio client interaction, packaged installation and persistence remain open.

Use the [official Swift SDK](https://github.com/modelcontextprotocol/swift-sdk/tree/0.12.1) for the protocol adapter; review and lock its dependency graph before integration. The [official transport specification](https://modelcontextprotocol.io/specification/latest/basic/transports) defines stdio as the local helper transport.
