# Evidence export staging checkpoint

Software-only checkpoint: destination/manifest, bounded disk sink, independent file hash, exclusive publication and socket staging are implemented. This is not an authenticated app download feature yet. VM/authentication ownership, Save Panel/UI, actual guest/browser full-byte comparison, >128MiB execution and full release acceptance remain pending.

Validation: 16 focused tests passed; full Swift coverage run: 742 tests, 741 passed and one existing UI/accessibility test skipped. Python GuestArtifactTests: 123 passed. Localization export and fixed browser inventory checks passed (21 navigation features, 27 page routes, 243 handlers; workflow parity remains pending). Socket tests use local socket pairs and actual 6MiB binary data, not a live guest/provider. Actual disk export test covers 5MiB+17 bytes. Coverage: staging worker 29/29 lines, filesystem 164/176, manifest 19/24. Read-only review found no blocking issue. Build/signature receipt follows after completion; remote CI remains a separate gate.

## Cleanup regression investigation

Reproduction/evidence: moved staging directory, replacement staging directory and replacement body tests initially failed four assertions (RED d4c3b97). Timeline: initial primitive 87ec7de -> reviewer cleanup finding -> failing inode fixtures -> correction a26dbdd, all 11 filesystem tests passed -> socket missing-worker RED a89e0ff -> five socket cases passed with destination recheck before transmission.

5 Whys: cleanup could claim success despite residue because missing original directory name was treated as removal; that name could instead have moved; the code checked path absence rather than pinned inode ownership; the cleanup result conflated absence with successful owned deletion; initial fixtures covered simple discard but not namespace replacement. Root cause: incomplete cleanup ownership model.

Fishbone: filesystem namespace changes; lifecycle error/commit cleanup paths; missing moved/replaced fixtures; ambiguous cleanup receipt. Repair: compare pinned inode/device before unlinking, preserve foreign replacements, report cleanupRequired or a saved receipt with stagingCleanupComplete=false. Prevention: retain all three adversarial inode tests plus pre-transfer destination race, error-body exclusion, corruption, cancellation and timeout socket cases. Destructor cleanup is only a fallback; it cannot establish successful explicit cleanup.

Signed build completed; codesign --verify --strict passed for dist/ARTEX Mac.app. Remote CI is not yet verified for this checkpoint.
