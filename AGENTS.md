# ARTEX Mac

Follow docs/requirements.md, design.md, tasks.md in that order. Native UI; never execute AI agent commands on macOS. Preserve Docker browser baseline independently. No host folders or general host RPC in guest. Compare every migrated workflow to the pinned browser baseline; pending features are never presented as implemented. Use Lazyweb before UI changes. Keep English comments/commits and Japanese/English docs. Do not commit credentials, guest state, logs or large binary artifacts.

## Temporary Actions quota policy

The user supplied a 2026-10-28 notification showing the account's 2,000 included Actions minutes exhausted, with a stated reset on 2026-11-01. Until availability is verified again, use local full checks and put `[skip ci]` in every pushed HEAD commit. Do not manually dispatch or retry hosted Actions or change billing/budgets. Keep remote CI explicitly unverified; skipped checks are not success. This applies to our pushes, not a claim that other repositories or contributors cannot consume minutes. See docs/actions-quota-policy.md and docs/actions-quota-policy.ja.md.
