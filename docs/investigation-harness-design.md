# Vulnerability investigation harness extension

Status: proposed roadmap; no scanner installation, execution or network enablement is implemented by this document. Existing browser parity and release gates remain required. This is backend/infra architecture; Lazyweb is out of scope until native screens are designed.

## Goal and acceptance

Operate approved investigations from the native app: define target scope, choose a tool/profile, preview the plan, start, observe progress, cancel, inspect normalized assets/findings, and export original evidence. Agent commands remain inside the managed Linux guest. No host shell, shares, Docker socket or general host RPC. English/Japanese owned UI only; retain exact original evidence bytes and annotate external Chinese/Korean output separately from translated summaries.

## Upstream feasibility review

Official repositories reviewed for this proposal:

| Tool | Role | Upstream license declaration | Integration concern |
| --- | --- | --- | --- |
| [Dirsearch](https://github.com/maurosoria/dirsearch) | HTTP path discovery | GPL version 2 | Python 3.11+ in current README; bound requests, recursion, redirects and wordlists; structured reports/API need pinned-version contract tests. |
| [Fscan](https://github.com/shadow1ng/fscan) | Host/service discovery and vulnerability checks | MIT | Explicit module allowlist; credential guessing and intrusive checks are separate profiles, never implicitly enabled by discovery. |
| [Masscan](https://github.com/robertdavidgraham/masscan) | Fast port discovery | AGPL version 3 | Own TCP/IP stack; raw packet privilege, interface, source address/port and NAT/VPN compatibility require a dedicated experiment. No speed promise on virtual networking. |
| [SoftEther VPN](https://github.com/SoftEtherVPN/SoftEtherVPN) | Access to approved remote test networks | Apache 2.0 | Requested repository is Developer Edition; compare the linked Stable Edition. Treat VPN as transport, not a vulnerability scanner. Review bundled dependencies/assets independently; README notes icon redistribution limits. |

These are upstream declarations, not a completed distribution compliance review. Pin exact commits, dependencies, tool data/wordlists, build recipes and hashes before packaging. Include applicable notices and corresponding source obligations; subprocess separation alone does not settle licensing. Never execute upstream install scripts on macOS or permit unverified tool self-updates.

## Architecture decision

Use versioned guest-side adapters behind typed task manifests instead of exposing arbitrary tool commands to the host. A manifest contains tool build identity, approved target scope, excluded ranges, ports/URLs, module profile, request/packet and concurrency ceilings, duration/output bounds, and network profile. Validate on both application and guest boundaries; execute a fixed binary with an argument vector, never interpolated shell text. Credentials use a separate secret channel and are redacted from logs/results.

A guest supervisor owns process groups, bounded output readers, cancellation and crash recovery. Persist run ID, immutable plan, timestamps, exit state and parser version. Distinguish failed/partial/cancelled from an empty successful result. Normalize observations into assets, services and candidate findings with tool provenance; detection is not automatically a confirmed vulnerability. Store raw output and artifacts with hashes for the existing evidence/export pipeline. Treat output as untrusted data, never agent instructions; constrain markup and paths.

Keep ordinary HTTP/TCP adapters unprivileged. Put raw packet operations and VPN route/interface control in narrow guest components or a separate gateway guest; final topology remains undecided until proof tests. Never grant the general AI process root/network administration capability. Host network/route configuration must not be silently changed. Current zero-NIC VM stays unchanged until the separate network gate passes. HTTP proxy access alone cannot carry Masscan raw traffic or arbitrary VPN protocols.

Network policy enforces the approved destination set at the actual egress boundary, including IPv4/IPv6, DNS changes, redirects and VPN routes. VPN connection does not expand scan authorization. Revalidate routes on reconnect, prevent default-route/DNS leakage, fail closed on tunnel loss, and prove cancellation cannot leave a privileged helper running. VPN credentials, trust verification and ownership of tunnel lifecycle need dedicated design.

## Phases and tests

H0: typed adapter/run/result contracts, pinned license/build inventory and isolated fixture network. Tests: invalid scope, argument injection, bounded output, parser errors, process-group cancellation, stale UI/session ownership and secret redaction.

H1: Dirsearch end to end against owned fixture HTTP services. Tests: known/absent paths, wildcard responses, redirects outside scope, rate limits, authentication secrecy, cancellation, restart persistence and raw artifact hash. Use the browser workflow as baseline where one exists; new workflows require their own native acceptance cases.

H2: Fscan discovery and selected checks against guest lab services. Tests: expected inventory, duplicate normalization, disabled intrusive modules, permission failures, timeouts and false-positive review. Add opt-in intrusive profiles only after separate acceptance.

H3: Masscan experimental adapter in an isolated network. Verify packet capture against configured scope/rate/interface, exclusions, NAT behavior, response accuracy, complete stop and guest capability isolation. Retain a TCP-connect discovery fallback when raw networking is unavailable; never silently substitute and claim equivalent coverage.

H4: SoftEther transport profile using an owned lab VPN. Compare Stable/Developer build capabilities; test certificate failure, split routes, overlaps, DNS/IPv6 leakage, reconnect, kill switch, cancellation and shutdown. Re-run H1-H3 through the tunnel. VPN is a separately enabled transport dependency, not required for direct lab tests.

H5: native en/ja controls, keyboard/accessibility and browser comparisons for shared task/findings/evidence workflows; clean-Mac install, offline tool inventory, signed app, rollback, source/notices and complete artifact exports. Use Lazyweb before product UI design. A CLI wrapper, mock scan or unit suite alone is not delivery.

## Completion evidence

Each phase needs RED/GREEN regression records, actual isolated tool execution, expected-versus-observed fixtures, negative egress/privilege tests, cancellation/persistence proof and explicit remaining gaps. Public networks are not test fixtures. Do not close the original 21-workflow parity goal on the strength of these additions.
