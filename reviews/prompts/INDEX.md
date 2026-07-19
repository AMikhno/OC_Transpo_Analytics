# reviews/prompts/INDEX.md — phase-audit prompt map

One audit prompt per plan.md phase; each phase ends at a validation.md
checkpoint and is audited by a fresh, context-free session running the
matching prompt. Written 2026-07-19 against the post-DR-035 document set.

## Standing rules

1. **Fresh session, zero build context.** The auditor must not be the
   session that built the phase, must not read builder chat logs, and
   works in a fresh clone (each prompt §1). The prompts are written so a
   less capable model can execute them: follow instructions, run the exact
   commands, report evidence — no judgment calls about what "good" means.
2. **Relationship to validation.md**: these prompts are the phase-scoped
   instrument; validation.md's generic Audit A/B/C prompts remain the
   whole-repo sweep run once at P6.3. V-P* checklist items are incorporated
   by reference into each prompt's ladder.
3. **Verdict discipline**: PASS / FAIL / NOT VERIFIABLE only; NOT VERIFIABLE
   is legal and never silently becomes PASS; spec beats code even when all
   tests pass.
4. If a prompt's cited spec ID no longer exists (spec evolved after
   2026-07-19), the auditor reports the drift as a finding and audits
   against the live spec — the prompt is the instrument, spec.md is the law.

## Map

| Phase | Prompt | Checkpoint | Enforces (primary) | Stop-condition class |
|---|---|---|---|---|
| P0 collector build | [audit-p0.md](audit-p0.md) | V-P0 | FR-C1..C9; AC-5.2.1–5.2.4; §5.3; AC-5.4.3/5.4.4; CASES §B | capture integrity — FR-C/AC FAIL rejects |
| P1 capture live | [audit-p1.md](audit-p1.md) | V-P1 | FR-Y1..Y4; DR-027/028/029/032/033/034; CASES §C | durability — any FAIL rejects |
| P2 warehouse | [audit-p2.md](audit-p2.md) | V-P2 | FR-W1..W5; FR-D1..D3; spec §4; CASES §A/§D | accounting — classification/epoch/dedup FAIL rejects |
| P3 metrics/semantic | [audit-p3.md](audit-p3.md) | V-P3 | FR-M1..M4; metrics.md; semantic-layer D1–D7; CASES §E/§G | published numbers — parity/denominator/NULL FAIL rejects |
| P4 observability | [audit-p4.md](audit-p4.md) | V-P4 | FR-O1..O6; CASES §F | alerting correctness — either-direction monitor FAIL rejects |
| P5 site | [audit-p5.md](audit-p5.md) | V-P5 | FR-P1..P4; FR-M3/M4/M5; DR-019/025; CASES §H | public honesty — number/adjacency/disclosure FAIL rejects |
| P6 launch | [audit-p6.md](audit-p6.md) | V-P6 | P6.1–P6.4; FR-CI5; DR-019; V-P6 | launch gate — secrets/disclaimer/fresh-clone FAIL rejects |

## Recurring invariant probes (defined once, instantiated per prompt)

| ID | Invariant | Appears in |
|---|---|---|
| G1 | skips proven only (guardrail 1) | P2 P3 P5 |
| G2 | raw immutable + atomic finalization (guardrail 2 / DR-028) | P0 P1 |
| G3 | prune only after verified sync + age (guardrail 3) | P1 |
| G4 | no_data never in punctuality denominators (guardrail 4) | P2 P3 P5 |
| G5 | stack closed — no undecided dependencies (guardrail 5 / DR-020) | all |
| G7 | no `${{ }}` in GHA `run:` (guardrail 7) | P0 P4 P5 P6 |
| G9 | no secrets, full history (guardrail 9) | all |
| G12 | epoch-only duration math (guardrail 12) | P0 P2 |

`reviews/SPEC-ISSUES.md` holds spec defects observed while authoring these
prompts (2026-07-19); they are inputs for the builder/owner, not audit
scope.
