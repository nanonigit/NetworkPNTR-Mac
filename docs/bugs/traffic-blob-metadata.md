# Managed original-blob metadata: marker ambiguity and blocking-file regression

## Evidence and reproduction

The frozen exchange API returns rendered req/resp strings, which may include an outer blob marker but can also contain literal user-controlled marker text. The original-blob export extension therefore requires a new structured association primitive; no existing native save feature is claimed broken. c937d64 records the intended missing BlobManifest compileRED, a4e95b9 the initial container GREEN. No source checkout was altered and no Go command ran on macOS.

Read-only review found that reusing the inherited Traffic.Blob helper invoked blocking os.Open without requiring a regular file.9856893 adds a real bounded child-process FIFO regression and same-size symlink rejection. The container failed after5.01s with metadata lookup blocked on FIFO; symlink metadata was also accepted. Directory rejection already passed through size mismatch, so it is not falsely reported as an observed accepted directory. This was an undeployed overlay defect; it did not change or expose the running guest.

c40ec74 replaces that call with openManagedBlob: root/each path component anchored through openat, O_NOFOLLOW/O_NONBLOCK/O_CLOEXEC, directory-only intermediates and regular-file stat. Every acquired descriptor is closed or transferred to a returned file that the metadata method closes. Only missing paths fall back to the documented legacy layout. The same regressions pass. bbe7072 adds Unicode/NFD exact identity, legacy location, corrupt hash/NULL/negative length/missing joined row and linked-parent tests; the complete traffic package passes.

## Five Whys

1. Why could metadata wait forever? Inherited Blob opened a FIFO synchronously.
2. Why could a FIFO reach that helper? It validated hash/path existence, not file type.
3. Why was the first implementation vulnerable? It reused a streaming opener for a metadata-only operation.
4. Why did ordinary body tests miss it? They created regular content-addressed files only.
5. Why change the descriptor strategy? Nonblocking/no-follow component opens plus regular stat make the metadata operation bounded and keep path ownership explicit. Apply the same opener to the managed streaming path before deployment.

## Fishbone and timeline

Data: inline marker spoof versus structural SQLite association; literal ID versus Unicode normalization. Filesystem: FIFO, leaf/parent symlink, directory and legacy layout. Runtime: private Linux container, pinned compiler, offline tests; default guest unchanged. Process: missing-method RED→ordinary GREEN→independent review→bounded FIFO/symlink runtime RED→hardened GREEN→full package/coverage. Source controls: exact Git archive, no credentials/state/host socket mounts and no production route/UI yet.

## Prevention and limits

Seven new top-level tests produce18 pass events including subtests; full traffic package produces61 test/subtest pass events. Overlay statement coverage54/59(91.53%); full package coverage66.3% is separately disclosed. This is not branch or whole-product coverage. Preserve the reproduced timeout, source/recipe/compiler/image/profile hashes and generic errors. Handler/auth, streaming handoff, native manifest/storage/cancellation/save UI, actual guest bytes and deployment provenance remain mandatory. The frozen Blob implementation and installed guest are unchanged; no claim is made that this primitive hardens their existing download route yet.
