# Source blob proof causality regressions

## Reproduction and timeline

The pending DEBUG captured-blob wiring inherited the legacy backend SHA gate before managed validation, so the new candidate could never boot. Review also found that accepting any CancellationError after stop could count an authentication loss as VM ownership rejection. The receipt deliberately has both authentication and VM validators; the proof failed to distinguish them.

2f919e8 adds a missing mode-specific preflight contract (compile RED). 855f131 adds the explicit branch; the same six-test run then executed and reproduced four assertions from logout and logout/relogin while the fake VM remained active. a42c40a preserves that runtime RED and fixes causality; seven tests pass, including session retention and caller cancellation. One additional test draft needed `try await` for a throwing Task value before the GREEN run; this was test setup correction, not a product failure.

## Five Whys

1. Why could the managed candidate not boot? An unconditional old backend hash rejected it.
2. Why could authentication cancellation satisfy VM stop? The probe caught an undifferentiated cancellation.
3. Why was cancellation ambiguous? Publication validates multiple independent ownership boundaries.
4. Why was phase alone insufficient? Relogin restores the authenticated phase but changes its revision.
5. Why retain a separate witness? The proof must independently preserve and verify the exact original authentication revision and task state to isolate VM ownership rejection.

## Fishbone and repair

Artifact routing: common CPU/listener checks plus explicit legacy or managed validation. Lifetime: retain the original session until after the stopped-VM check. Authentication: DEBUG package witness captures the exact revision, exposes no token and validates before/after receipt rejection. Caller: check task cancellation outside and inside the accepted cancellation branch. VM: the call site requires the real controller to be stopped with no machine before asking for proof. Cleanup: only a successful causal check marks stopped; failure still discards pending files through the outer cleanup path.

## Verification and prevention

Seven focused tests pass. A real disposable Linux VM subsequently passed two boots, two cooperative stops and two clean audits; the original 262401-byte response was saved/reread by hash and full bytes, rejected after stop, and revalidated after reboot. The fixed browser reference projection remained identical. Keep auth loss/relogin/retention/caller cancellation regressions and the preflight matrix. Stop-before-publication is not a mid-transfer cancellation witness. Native UI/panel/keyboard/VoiceOver, production profile/kernel promotion and full product acceptance remain open.
