# Typed binary display investigation

## Reproduction and evidence
The real captured-index reference/native comparison preserves the pinned server's Chinese binary placeholder as protocol data. Source inspection showed FindingTrafficView rendered that raw content below its existing localized binary notice. New display-contract tests failed compilation at6d547c4 because no text-only representation existed. This is wire/source evidence and test-contract RED, not an observed unlocked-screen failure.

## Root cause
5 Whys: Chinese owned help remained because the server placeholder was rendered as body; the body used raw cumulative content; binary type was used only to add a notice/block paging; no display-only aggregation separated typed placeholder pages from ordinary text; localization tests did not exercise this typed case. Root cause is presentation treating a typed server notice as ordinary packet text, not missing translations.

Fishbone: protocol—binary flag plus placeholder; presentation—raw content concatenation; localization—duplicate localized notice; data integrity—CJK regex replacement would corrupt legitimate text; tests—binary paging existed but display separation was untested. Timeline: actual wire proof148e59c → display RED6d547c4 → source repair77f0a7c → workspace/offscreen28 GREEN78ef8d2.

## Repair
Retain raw content; assemble textContent from nonbinary pages only; render it under the existing localized notice. Preserve earlier text and all raw headers/DTOs/downloads. Never infer binary from a marker string or rewrite untyped raw capture previews.

## Verification
Four new pure and one integration case; full837 Swift (836 pass,one existing AX skip),179 Python; changed-source combined LLVM line86.43%, with all8 initializer/append regions executed. Local staged bundle rebuilt/signed, previous guest hashes preserved. See evidence-binary-localization-verification.md. Actual visible UI and full product remain open.

## Recurrence prevention
Keep initial/later binary, exact-marker ordinary text, FEFF/NFD/CJK, rejected-append immutability, both wire sides and locale/no-request tests. Review display-source boundaries before translating server output. Do not blanket-remove CJK or treat offscreen rendering as visual/keyboard/AX acceptance.
