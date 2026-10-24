# Unicode chat send investigation

Requirement and design: requirements.md and chat-advanced-design.md. This is finite core behavior; Lazyweb is outside this change. UI comparison remains A5.

## Reproduction and evidence

The checksum-pinned browser handler calls input.trim() before the guard, request and error restoration. Foundation whitespace differs: BOM passes as content while NEL and zero-width space are discarded. Padded native messages were also sent/restored untrimmed. Extended the existing bounded source-handler oracle from four to nine cases without changing the pinned source. Three executed regression tests produced 13 failing assertions at RED54a1e26; GREENcc3e64b passes the same target. The five added oracle cases cover BOM guard, NEL, zero-width space, padded text with attachment, and BOM with attachment. This is source execution with controlled API/state, not rendered UI or provider evidence.

## Cause analysis

5 Whys: send behavior diverged because guards used Foundation whitespace; that set differs from ECMAScript; a platform convenience was used instead of the reference semantics; send text lacked the mention-search compatibility helper; earlier send fixtures covered ordinary text and empty strings but not Unicode/padding.

Fishbone: language semantics (Unicode sets), duplicated validation (service/store/workspace), state recovery (raw versus submitted text), fixtures (missing edge cases). Timeline: inspect remaining parity gate -> execute pinned Unicode fixtures -> RED checkpoint -> shared scalar helper and trimmed snapshot -> GREEN -> independent review -> complete suites, coverage and signed bundle.

## Repair and prevention

ChatText extracts the existing mention-search ECMAScript scalar trim unchanged. Workspace checks before lazy creation. Store compares original UTF8 bytes before clearing, sends/restores the trimmed snapshot and retains revision ownership protections. Service uses the shared empty guard but preserves explicitly supplied wire bytes. Mention search retains start-only/full trim behavior. No host execution/network boundary changed.

193 Swift tests (179 core, 5 AppKit, 9 diagnostic) and45 Python pass. Helper coverage:16/16 lines,10/10 regions,4/4 functions; LLVM reports no branch coverage. Oracle regeneration is identical; modified source is rejected before handler execution. Read-only reviewer found no concrete defects. Signed app rebuilt fromcc3e64b and strict signature verified, without launching it. See evidence/chat/unicode-send-verification.json.

Pending: native ChatView still has the prior Foundation/attachment-only send-button guard; replace it as part of A5 controls with UI-specific tests and Lazyweb evidence. Real provider turns, native picker/cards/cancel/accessibility and source-kernel reliability remain open. Core passing results do not close these gates.
