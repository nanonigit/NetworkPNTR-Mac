# LLM transport cancellation checkpoint

## Requirements

A cancelled LLM operation must not start a transport request. If cancellation occurs while an uncooperative transport returns, the service must not expose that reply as current success. Reject request and response bodies above the existing finite JSON limit of 4 MiB. Preserve pinned e75ae371ad777ffd1eecdd28d2781a6519b05591 endpoint, method, partial-patch, active-delete, ID and response contracts. Never use actual credentials or cloud calls in regression tests.

## Design

Apply cancellation and byte checks at LLMService.raw, shared by all eleven request families. Check cancellation before transport handoff and immediately after awaiting it, before status/decode. An empty rotation patch remains a no-op. Bounds are measured in bytes; exactly 4 MiB remains allowed. This is a service boundary checkpoint, not store ownership or mutation-outcome recovery. A cancelled dispatched write may already have committed; no automatic retry is added. Store acknowledgement/replay gating and editor lifecycle ownership remain pending. No product UI changes; Lazyweb is out of scope.

## Tasks

1. RED: exercise all eleven request families with pre-cancelled tasks, cancellation at transport return, over-limit request/response bodies and exact-limit success.
2. GREEN: add shared checks without altering public signatures or wire contracts.
3. Review, targeted and full regression, coverage, signed build and CI. Preserve pending browser/native comparison until manual unlock; synthetic tests are not actual guest acceptance.
