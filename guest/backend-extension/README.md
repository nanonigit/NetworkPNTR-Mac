# Managed backend extensions

[English](README.md) | [日本語](README.ja.md)

The frozen browser baseline is commit `e75ae371ad777ffd1eecdd28d2781a6519b05591`. Its source checkout is preserved. Managed extensions are tested on a separate copy and built inside a pinned Linux container; the backend never runs directly on macOS.

See [the reproducible developer build recipe](../../docs/managed-backend-build.md) for compatibility paths, patch application, dependency verification and offline package checks. See [the original-blob design](../../docs/traffic-blob-design.md) for deployment and UI acceptance gates. Compilation alone does not establish VM or UI acceptance.

The extension keeps existing JWT authentication, descriptor-relative file access and explicit data ownership. It adds no host share, Docker socket, existing data mount, external scan or cloud model call.
