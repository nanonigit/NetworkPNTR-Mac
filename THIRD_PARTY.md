# Third-party inputs

Browser reference and API/navigation metadata: nanonigit/artex-global, pinned e75ae371ad777ffd1eecdd28d2781a6519b05591, AGPL-3.0. The repository uses the same license; upstream LICENSE retained.

Proof guest: Alpine v3.22 aarch64 linux-virt 6.12.114-r0 (GPL-2.0-only) and busybox-static 1.37.0-r20 (GPL-2.0-only), official dl-cdn.alpinelinux.org APKs, pinned SHA-256 in script/prepare_guest.py. Generated binaries are not committed. Package metadata and download URLs are retained in the artifact manifest.

Corresponding Alpine build recipes: https://gitlab.alpinelinux.org/alpine/aports/-/tree/6a0c60d347a1193d1d7ebb41a6e72dc0da1e8137/main/linux-lts and https://gitlab.alpinelinux.org/alpine/aports/-/tree/2e97d754a30d558f15524b8e422303c8a96832df/main/busybox . Required corresponding-source delivery and notices are distribution gates before any guest binary release.

Swift application uses Apple system frameworks only; no third-party Swift, npm or pip dependencies. Apple SDKs/frameworks are not copied into this repository.

Backend acceptance guest adds Alpine PostgreSQL 16, Python 3, Node.js and CLI packages listed by exact installed version in guest/backend-packages.lock. The builder refuses a different installed package set. This lock records versions, not a full source archive or a complete legal notice bundle. No generated backend/system/state image is committed or distributed by Git. Before binary distribution, retain the installed package copyright/license notices and supply all corresponding sources required by their individual licenses. The pinned backend binary is a local artifact of the reviewed browser-source build, identified by digest and source commit in script/prepare_backend.py and generated manifests. Rebuilding a portable source-only release remains pending. Python guest helper code uses the standard library only; there is no pip requirements set or npm project in this native repository to audit.

A private local experiment uses the already-installed Docker Desktop GPL LinuxKit kernel 6.12.76, SHA-256 `35dc83e45a0cbf9a292469e902fd6a5f4db58c9ead47e69233b4197661795fc8`. Neither that binary nor its generated VM image is committed or distributed. This diagnostic does not invoke Docker at app runtime. It must not become a release input until its reproducible source build, exact configuration, notices and corresponding-source delivery are reviewed. The application source supports direct-root boot independently of this diagnostic input.
