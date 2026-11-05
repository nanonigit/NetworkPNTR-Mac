# Managed cloud tool history verification

The managed norma v0.4.3 patch preserves typed tool signatures through Complete/Stream, indexed accumulation, normalized JSON reload and a second request. Decoder-stamped endpoint/model scope limits replay to its original context; unknown/different contexts are stripped on copies. Internal scope never goes upstream. Anthropic requests recursively strip both OpenAI fields without changing history or Anthropic thinking signatures. See cloud-tool-history-design and bugs/cloud-tool-history for contracts/RCA.

Checkpoints: aa2a6bf runtime RED for lost signatures and interleaved inputs; 3fe4c64 GREEN. Independent review added cross-provider scope: a7383ee runtime RED, cb77140 GREEN. The unpatched SDK retry fixture also panics because it calls doStream with no HTTP client; baseline reproduction is recorded separately. Its test-only fix supplies srv.Client(), preserving production retry code. No failing test was disabled. The narrow .gitattributes exception applies only to literal unified-patch context prefixes.

Final network-disabled Linux tests pass: norma/llm77 pass events; managed traffic62,agent74,server314 pass events. These include parent/subtest events, not527 independent scenarios. Existing agent14/server102 skip events remain unverified. In total527 pass/116 skip events,zero fail events. All newly added tool-history cases run. Six new metadata helper functions have100% statement coverage; Accumulator.Add94.7%,Accumulator.Message92.3%,OpenAI conversion97.2%,Anthropic body93.8%. Whole llm package coverage is74.2%; that broader existing coverage is not claimed to reach80%. Python179 artifact tests pass. Native Swift was unchanged; its prior1025-case result is not presented as rerun here.

The final Docker image is sha256:d535a2ede98d928c004fb879e458f025755c0428ab64461b65ba62df460329a2, verified linux/arm64. It builds the managed traffic overlay and the container-local patched dependency into a CGO-disabled ELF/AArch64 backend,29294754bytes,SHA-25694ce92158f608d1b56b2e19a5e8f73e9eb596019f6fc0df96da1bd2891bedb56. Go build-info confirms norma replacement /managed-norma,GOOSlinux,GOARCHarm64,CGO_ENABLED0; the binary contains version artex-mac-e75ae371-cloud1. It was exported to ignored .build-cache/managed-backend-cloud-v1/artex, not executed on the host or staged into the app/default guest. This is compilation/protocol evidence, not a VM runtime test.

Reproduce from the repository root with Docker for development validation only:

```python
from pathlib import Path
import io, shutil, subprocess, tarfile, tempfile
root = Path.cwd()
with tempfile.TemporaryDirectory(prefix='artex-cloud-history-') as temp:
    context = Path(temp)
    (context / 'source').mkdir()
    archive = subprocess.check_output(['git', '-C', '../artex-local/source', 'archive', 'e75ae371ad777ffd1eecdd28d2781a6519b05591'])
    with tarfile.open(fileobj=io.BytesIO(archive)) as tree:
        tree.extractall(context / 'source', filter='data')
    for source, destination in [('traffic', 'traffic-extension'), ('agent', 'agent-extension'), ('server', 'server-extension')]:
        shutil.copytree(root / 'guest/backend-extension' / source, context / destination)
    for name in ['managed.patch', 'norma-tool-history.patch']:
        shutil.copy2(root / 'guest/backend-extension' / name, context / name)
    subprocess.run(['docker', 'build', '--platform', 'linux/arm64', '--progress=plain', '-f', str(root / 'guest/backend-extension/Dockerfile.provider-tests'), str(context)], check=True)
```

Dependency acquisition/verification is a separate online layer; all tests and backend compilation use RUN --network=none. Original module sum: github.com/Autumn-27/norma v0.4.3 h1:DnmOhJPL6OZSMnCVYO5Ujh4yVINuDarEickVi9jx1hI=. The verified module is copied before checked patch application; no module-cache/frozen-source mutation or upstream dependency release is required. No new Go dependency was added.

Default/staged guest manifest remains fa0f1972c04f2a04853de37f4fd163b922ac38c841849c635d29f565fe6115ce; frozen browser stays clean at e75ae371. No app rebuild or native launch was needed for this Go-only change. No real cloud/API-key/tool execution, PostgreSQL/task transcript or compaction/restart, TLS/JWT ingress, egress redirects, usage/error/cancel or real panel/keyboard/AX/browser acceptance is proven. The tests use precomputed fixture tool results. CP2 and full four-provider acceptance remain open, along with the original21 workflows, kernel/default promotion, harness and release gates. Hosted CI remains unverified; publication uses [skip ci].
