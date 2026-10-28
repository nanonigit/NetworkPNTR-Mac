# Reference export diagnostic regressions

## 1. Reproduction

Descriptor failure injection reproduced two failures in seven cases at2f47a9f. A last-permitted-request test at658efb9 reproduced an off-by-one rejection. Missing named-builder/private-native-receipt contracts were added atd43bc4b. Actual attempt1 then exited1 when Docker cp could not copy the tmpfs response directory. API success did not imply host comparison success.

## 2. Evidence

Retain the failed-run receipt and all cleanup results. Docker documents tmpfs copy limitations at https://docs.docker.com/reference/cli/docker/container/cp/. Missing exporter contracts atc3f7471 produced six errors across three added tests; these were missing-contract errors, not six executed transfer failures.

## 3. Cause analysis

5 Whys: files were in tmpfs; export assumed Docker cp could read them; the assumed filesystem path did not cover mounted storage; unit tests exercised APIs but not real extraction; the acceptance boundary omitted independent host files. Root cause: storage-specific extraction was assumed before actual runtime proof. Descriptor failures separately arose from incomplete ownership transfer; the final request was rejected by applying a dispatch budget to response completion.

Fishbone: filesystem mounts; descriptor ownership; request counting; builder selection; private receipt/source identity; missing actual extraction. Timeline: descriptor RED2f47a9f/GREENc346585; real parser scope c68b3d3; budget RED658efb9/GREEN64d8b05; binding REDd43bc4b/GREEN6a2c7bf; attempt1 failure; exporter REDc3f7471/GREEN5cf3bcd; attempt2 terminal0 at8accf4f.

## 4. Repair

Use ExitStack and explicit created-file ownership, separate dispatch and completion budgets, exact named-builder inspection and independently verified native receipts. Export only fixed guest files through bounded pipes, validate exact length/exit/time and compare actual files independently. Preserve unknown cleanup identities and retain failed receipts.

## 5. Verification and recurrence prevention

18 focused tests and155 full Python cases pass. Actual attempt2 exported all eight files and matched native bytes/hashes; all owned cleanup and original-resource preservation gates pass. Keep short/excess/nonzero/stderr/timeout/existing-file negatives and real HTTP framing scope tests. This closes original-body API comparison only; preview/mutation/UI/full-product gates remain open.
