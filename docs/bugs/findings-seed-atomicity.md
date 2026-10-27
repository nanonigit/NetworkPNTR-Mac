# Findings seed transaction atomicity

## 1. Observe and reproduce

F4a Python/security review found six `setval` calls before the final seed postcondition. Unit REDeac81de fails the transactional-sequence requirement. A separate PostgreSQL16.15 component using that exact old source executes a forced division-by-zero immediately before COMMIT: all fixture tables return empty, but all six sequences remain advanced. This is the isolated regression witness, not a successful seed.

## 2. Investigate

5 Whys: sequence state survived because setval is nontransactional; it was used to align fixed IDs with later inserts; table transaction coverage was assumed to include sequences; the seed pattern came from a previous non-atomic file fixture; initial boundary tests did not force a postcondition failure. Fishbone: SQL semantics, fixed-ID setup, reused pattern, missing rollback witness and incomplete component prerequisites. Timeline: missing-script RED6dcad07 -> eight boundary tests -> review -> sequence REDunit -> transactional repair -> actual old/fixed SQL proof -> report review.

Preparation failures remain counter-evidence: first initdb had no passwd entry forUID1000 and executed no fixture SQL. The next attempt lacked the separately initialized llm_records table and stopped at LOCK before inserts/sequence changes. Neither isolates the sequence bug. The final harness uses an account-only cached-image derivative plus complete pinned schema.sql, llmUsageSchema and llmRecordsSchema/Migrate. Local Unix Docker context and Docker-driver builder are inspected/pinned, RUN and proof containers have no network; no ARTEX startup occurs. Bounded stdin/export avoids known read-only/tmpfs docker-cp failures; unconditional owned-container cleanup survives log-export errors.

## 3. Repair

Use fixed `ALTER SEQUENCE … RESTART WITH max+1` statements inside the transaction. Explicit standard_conforming_strings protects fixed SQL literal semantics. Preserve strict runtime/marker/DSN/environment guards and bounded psql stdin invocation. SQL failures before COMMIT roll back rows and sequence restarts. A process timeout or lost commit acknowledgement remains unconfirmed; emit no success proof and never auto retry.

## 4. Verify

Actual old source: rows empty, sequences advanced to8111/8111/8200/8203/9133/15190. Actual repaired source: rows empty and all sequences unchanged at[1,false]. After explicit rollback verification, a planned successful seed reads back33 full findings,31 exact node payloads plus legacy node15190,11 terminal tasks, one inherited relation and33 trigger-created asset links. Both main and direct SQL replay refuse before insertion with rows/sequences unchanged. No profiles, activity, conversations, usage or retest/traffic jobs; no ARTEX process. Original four browser IDs are unchanged and owned component containers/derivative tag are removed. Evidence: evidence/findings/f4a-seed-sql-{red,green}.json.

Nine focused unit cases and95Python pass;578Swift total/577pass/one existing external-AX skip. Seed line coverage101/102 (99.02%) using missing-line trace analysis. Component report review found no remaining blocker in this scope. Actual ARTEX API, VM, restart and UI parity remain open.

## 5. Prevent

Every seed using generated IDs must verify both row and sequence state after a forced final SQL error. Include all runtime-created DDL, exact trigger-generated associations and validated named guest UID in component preparation. Do not accept a generic SQL failure as the intended regression, nor mocked psql success as SQL proof. Preserve failed states/logs, require exact published-head CI and keep kernel/UI/full workflow gates independent.
