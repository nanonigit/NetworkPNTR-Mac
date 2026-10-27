# Empty-name reference verifier correction

MUSUBI: collect the actual failed isolated reference and retained dump/logs; reproduce with omitted-name wire fixtures; repair only reference decoding; verify RED/GREEN and a new disposable actual run; retain the failure and regression evidence.

The schema2 native three-boot run passed. The first independent reference stopped at the empty-name boundary with `Findings reference raw text`. Its retained synthetic9101 row had an empty SQL name, the expected normalized class and medium severity, before the long-class attempt. Frozen server/dto.go:315 declares FindingDTO.name with omitempty; native FindingModels.swift already decodes an absent name as empty. The reference incorrectly required a present string.

5 Whys: assertion failed because absent JSON name was treated as None; the DTO omits empty strings; unit replies always included name; the fixture used the SQL shape for this optional field; empty-name wire omission lacked its own regression. Fishbone: DTO serialization, fixture shape and verifier assumptions. Timeline: actual native GREEN -> independent actual RED -> two unit errors -> minimal missing-only default ->9focused tests GREEN. Null and omission of a nonempty expected name still fail. Source/backend/seed/audit/network policies are unchanged; no mutation retry within a failed environment.

Failure cleanup exported258823-byte DB dump,4197-byte log bundle and2525-byte executed-line receipt privately; owned container/tag/aliases removed and original inputs/containers preserved. The subsequent actual result is recorded separately in the boundary verification report. No raw state, credentials or logs are committed.
