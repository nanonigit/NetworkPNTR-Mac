# Independent original-body reference verification

The second isolated reference run at8accf4f exited0. Two backend starts and cooperative stops produced four complete bodies per start:52,5242897,0 and135266321 bytes. All eight exported files matched actual native saved files byte-for-byte and by SHA-256. The native signed binary, private execution receipt and current native source hashes were checked independently. See evidence/findings/evidence-reference-comparison.json; fullGoalComplete remains false.

The reference used the frozen backend e75ae371ad777ffd1eecdd28d2781a6519b05591, cached image IDs, the explicitly named local Docker builder, UID1000, read-only root, no network, no host mounts, no ports, dropped capabilities and no-new-privileges. All owned containers/tags were removed; input images and original containers were preserved. Raw bodies, credentials, database dumps and logs remain private.

The first run exited1 because Docker cp could not read the tmpfs download directory, even though its API exercise passed. This failure is retained in evidence-reference-initial-failure.json. The replacement exports eight fixed files through a guest producer and bounded host stdout/stderr reader with exact-size, timeout, process-exit and exclusive-file checks, then performs independent file comparison. No archive extraction or host share is required.

Verification:18 focused reference/host tests and155 full GuestArtifactTests pass. No Swift/runtime source changed since the previously verified767 Swift cases (766 pass, one existing external accessibility skip), release exclusion and signed app checks; those are previous checkpoint results, not fresh reruns. Hosted CI remains unverified and the publication HEAD uses [skip ci].

Scope: declared HTTP response bodies only. The real HTTP parser clips at Content-Length, so trailing raw-wire bytes are not audited. Detailed native preview text/binary/truncation, nonempty captured-traffic mutations/persistence, full native controls, unlocked visual/keyboard/VoiceOver acceptance, cloud providers and all broader release gates remain open. Metadata reads are insufficient for preview equivalence.
