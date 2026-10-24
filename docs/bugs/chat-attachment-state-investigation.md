# Attachment draft identity and recovery investigation

Use the MUSUBI Bug Hunter flow: reproduce, gather evidence, analyze, repair, verify. This is finite service/state work, not native picker/card design; Lazyweb is outside A4.1. UI and upload handoff remain pending.

## Canonical Unicode filename collision

Independent review found that Swift String equality/hash canonical equivalence merges NFC é.txt and NFD e+combining-acute.txt, while pinned chatupload.go uses guest filepath/os.Stat without normalization. The first implementation rejected the valid two-file envelope, shared Identifiable keys, accepted a path/name pair with different bytes, and could collapse restore/removal. Executed RED25c877a produced five failures across model/store tests. GREEN512d9c0 uses Data(path.utf8) identities, byte-exact name/path agreement and custom metadata equality, plus byte-based append/restore/removal. The original display/wire strings are never normalized. Thirty-six scoped tests passed at that checkpoint; review approved the fix.

5 Whys: distinct guest files collided -> Swift equality normalizes canonical equivalents -> native strings were used as filesystem keys -> display equality was assumed identical to Linux path identity -> fixtures lacked composed/decomposed pairs. Fishbone: language semantics, guest filesystem, model identity, collection keys, test fixtures. Timeline: initial nine new core cases -> independent review -> NFC/NFD runtime RED -> byte-identity GREEN -> source-derived oracle includes both names -> followup review.

## Older submitted text and attachment-only workspace guard

Inspection found the older submitted-text comparison had the same canonical-equivalence issue: a newer byte-different draft could be optimistically cleared/restored as the old text. The workspace also required nonempty text even when the store/service supported attachment-only sending. RED31e4daa produced five failed assertions; GREEN5ae3434 compares exact draft UTF8 and permits an existing conversation with attachments through the workspace guard. Thirty-eight scoped tests passed. Pending text revisions prevent an edit-then-clear ABA from reviving old text. Stop restores only unconfirmed snapshots, reset clears them and late acknowledgements cannot revive them. Removing draft cards calls no guest delete route.

The pinned ChatView send handler is executed from a whole-file-checksum-verified source, with exactly one TypeScript error cast erased and bounded state/API stubs injected. Four simple cases compare pending/final state and send metadata with Swift; RED173676c required its missing artifact, GREENe93f575 passes39 scoped tests. This does not prove rendered UI, provider success, all trimming edge cases or native upload/create handoff. Keep source hashes, byte-identity/ABA/selection/reset tests and rejected-source guard. Complete A4.2 ownership/deletion/cancellation and A5 UI comparisons before calling attachment parity achieved.
