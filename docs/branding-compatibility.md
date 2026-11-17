# NetworkPNTR Mac naming and compatibility

The product and repository use NetworkPNTR Mac and `networkpntr-mac`. PNTR means penetration testing. Swift modules, executable names, native UI copy and the new MCP tool names use the new identity.

Existing application data, Keychain service and bundle identifier intentionally retain their original identifiers. This preserves existing login sessions, provider keys and private VM disks without copying or resetting them. Those internal identifiers are not the product display name.

Frozen guest protocol markers, authentication username, backend paths/environment variables, reviewed build-version strings, artifact hashes, upstream legal texts and historical evidence retain their original bytes. Renaming them without rebuilding and re-verifying both sides would break boot, authentication or artifact verification. Upstream attribution and license terms remain intact.

The existing browser repository and its pinned baseline are independent of this Mac repository rename. Git history and repository visibility are preserved. New user-facing copy uses NetworkPNTR.
