# Error localization investigation — L4a foundation

## 1. Reproduce

Existing services construct static Japanese `BackendAPIError.validation(String)` values. Stores render `.localizedDescription` at failure time. Unlike Chat controls, those strings cannot respond to the explicit application language. This source evidence establishes the architectural gap; this stage does not claim a new live English error reproduction.

## 2. Gather evidence

`ea39007` is the compile-time RED: three tests newly reference the missing `AppErrorText` presenter and `BackendValidation` reasons. `a3f7681` is GREEN for the same three tests. All16 production validation constructors retain their guard conditions and now carry a native reason. Generic/known HTTP statuses, Keychain codes, upload errors, and unknown failures are tested. Unknown errors containing a private path/secret description produce only a fixed generic message.

## 3. Analyze

5 Whys: errors stay Japanese → services supply rendered text → errors carry a String payload → there was no shared explicit-language presentation boundary → initial feature ports preceded the global language requirement. Fishbone: service payload identity, eager store rendering, catalog packaging, explicit locale ownership, arbitrary backend text safety. Timeline: inspect strings/consumers → requirements/design/tasks → intended missing-API RED → typed reasons/presenter GREEN → reviewer → full regression/coverage → signed resources.

## 4. Repair

Replace native validation strings with a closed16-case `BackendValidation`; add explicit-language `AppErrorText`. Catalog owns29 new bilingual entries (16validation +13status/upload/fallback). Legacy `LocalizedError.errorDescription` explicitly renders Japanese to preserve existing consumers while stores migrate. Only integer HTTP/Keychain codes are interpolated. No arbitrary body, path, error description, or user content is translated/displayed. Backend missing-provider recognition remains its exact pinned multilingual allowlist; no match broadening or new network capability.

## 5. Verify and prevent recurrence

243 Swift cases:242pass, one existing AX skip.52 Python regression tests pass. AppErrorText line/region coverage26/26 and21/21. Final signed application build/strict signature pass;29error entries in each bundled language exactly match the authoritative catalog. Read-only reviewer found no concrete defect. Core resources use the existing portable exporter and drift gate.

Store/UI error values remain eagerly rendered Japanese. Live error language switching, actual native/browser error comparison, runtime errors, and full R8 acceptance remain open. Next: preserve error identity in observable stores, resolve at view locale, verify switching while an error is visible without replacing form/draft/attachment state. No UI/browser or VM runtime test is claimed for this foundation change.
