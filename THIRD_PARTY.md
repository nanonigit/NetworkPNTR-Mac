# Third-party inputs

Browser reference and API/navigation metadata: nanonigit/artex-global, pinned e75ae371ad777ffd1eecdd28d2781a6519b05591, AGPL-3.0. The repository uses the same license; upstream LICENSE retained.

Proof guest: Alpine v3.22 aarch64 linux-virt 6.12.114-r0 (GPL-2.0-only) and busybox-static 1.37.0-r20 (GPL-2.0-only), official dl-cdn.alpinelinux.org APKs, pinned SHA-256 in script/prepare_guest.py. Generated binaries are not committed. Package metadata and download URLs are retained in the artifact manifest.

Corresponding Alpine build recipes: https://gitlab.alpinelinux.org/alpine/aports/-/tree/6a0c60d347a1193d1d7ebb41a6e72dc0da1e8137/main/linux-lts and https://gitlab.alpinelinux.org/alpine/aports/-/tree/2e97d754a30d558f15524b8e422303c8a96832df/main/busybox . Required corresponding-source delivery and notices are distribution gates before any guest binary release.

Swift application uses Apple system frameworks only; no third-party Swift, npm or pip dependencies. Apple SDKs/frameworks are not copied into this repository.
