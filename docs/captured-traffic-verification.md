# F5c1 captured traffic contracts

This prerequisite adds fixed authenticated GET contracts for the native evidence picker and captured raw preview. It does not implement the picker or full evidence UI. The full inventory and remaining sequence are in findings-traffic-ui-design.md.

Missing API RED e33e7b6 -> GREEN67e9be8 with eight contract tests.29 combined captured/bound-traffic tests pass. Full Swift:705 cases,704 pass, one existing explicit external-AX skip, zero failures. Python guest/tooling:123 pass. Full-suite coverage: CapturedTraffic.swift55/55 and CapturedTrafficService.swift20/20 lines. Independent read-only review found no production blocker; its valid-status-payload test gap was corrected.

Tests cover capture-off history vs no index, malformed/partial/null metadata, exact page/size echoes, non-atomic global/matching counts, opaque byte IDs, FEFF/NFD/CJK preservation, independent percent-byte decoding, literal plus escaping, invalid IDs/queries, exact/one-over8192 encoded targets and4MiB JSON bodies, typed status errors and pre/post-await cancellation. The original failing BOM assertion used Foundation decoded String values; diagnostic wire bytes were correct, and the test oracle was corrected without changing production encoding.

Localization export and frozen source inventory pass:21 navigation features,27 routes,243 handlers; workflow parity remains pending. Fixed source contains Korean fallback download error text and Chinese comments; they are not imported as owned UI strings. Native errors stay typed/localized; raw user/captured request/response content remains unchanged. No new UI text or dependency was added.

No actual guest/provider requests, credentials, data mutation or recorded-URL navigation were used. Evidence downloads are still absent: the current attachment path only verifies digests. Owned picker state, parent/window/detail integration, all native actions, full-byte export, actual isolated guest/browser comparison and unlocked external keyboard/VoiceOver/visual acceptance remain mandatory. Durable uncertainty, F5, all21 workflows, runtime reliability and clean-Mac/release gates remain open.

Signed build-only and strict signature verification pass. Nine inspected baseline files match the exact frozen commit. No external UI acceptance launch occurred.
