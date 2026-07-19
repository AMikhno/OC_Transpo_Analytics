# Audit prompt — Phase P3: Metrics & semantic layer (checkpoint V-P3)

Run in a FRESH session after the builder declares P3 complete. Stack class:
**published numbers** — the YAML audited here is the single source of truth
for every figure the public site will show.

## 1. Session setup (binding)

- READ-ONLY audit. Findings, never fixes. The one sanctioned mutation is
  probe U4, which happens in a scratch COPY — the clone itself stays clean.
- Fresh clone in scratch:
  ```bash
  git clone https://github.com/AMikhno/OC_Transpo_Analytics "$SCRATCH/audit-p3"
  cd "$SCRATCH/audit-p3" && uv sync --all-groups
  ```
- Report begins with the literal sentence: **"I modified nothing."**
- Builder claims are not evidence; every verdict cites your own command +
  output.
- Expected values come from metrics.md, semantic-layer.md, CASES §E/§G, and
  the pre-computed oracles below — never from mart SQL or YAML. metrics.md
  header rule applies: if YAML, marts, or site disagree with metrics.md,
  metrics.md wins and the others are bugs.

## 2. Binding scope

| ID | One-line restatement |
|---|---|
| FR-M1 | semantic models + metrics YAML = SSOT; `mf validate-configs` green |
| FR-M2 | parity: mf vs mart, zero tolerance, at declared grains |
| FR-M3 | one sanctioned window pattern: Σnum/Σden over counts; no rate aggregation |
| FR-M4 | MIN_EVENTS threshold logic present in marts (rendering audited at P5) |
| D1 (semantic-layer) | every rate is a `ratio` metric — no derived/pre-divided rates |
| D2 | NULL via native division — no COALESCE/IFNULL anywhere in the metric path |
| D3–D7 | surrogate entity, expr-flags, model-layer SCD, time spine, scope |

Plus metrics.md §§1–6 (populations, formulas, null rules, aggregation law),
plan.md P3.1–P3.5, CASES §E (F-M01–F-M05) + §G (F-G01–F-G03), DR-023/024/026.
Out of bounds: site rendering (P5), classification correctness (audited P2).

## 3. Independence rules, oracles, designed probes

Re-runs:

```bash
uv run mf validate-configs      # or the CI-equivalent command named in P3.2
make parity
make build && make build        # determinism, F-G03
```

**Pre-computed oracles** (hand-derived from metrics.md; compare to at least
6 decimal places — zero tolerance means zero):

| Fixture | Value | Expected | Failure signature it catches |
|---|---|---|---|
| F-M01 | system otp_rate | 901/1010 = **0.892079…** | 0.500000 = average-of-averages |
| F-M02 | otp_rate | 60/80 = **0.750000** | 0.705882 = /observed; 0.600000 = /S |
| F-M02 | coverage_rate | 85/100 = **0.850000** | — |
| F-M02 | early_rate / late_rate | **0.100000 / 0.150000** | — |
| F-M02 | skip_rate | 5/85 = **0.058824…** | 0.050000 = /S denominator bug |
| F-M03 | otp/early/late/median/p90 | **all SQL NULL** | 0 or 1 = null-semantics bug |
| F-M03 | coverage_rate / skip_rate | **0.400000 / 1.000000** | — |

Designed probes:

- **U1 — denominator law by SQL (G4).** Over every row of
  mart_reliability__route_daily and __system_daily:
  ```sql
  select * from <mart>
  where otp_rate is distinct from cast(on_time_count as double) / nullif(timed_count, 0)
     or early_rate is distinct from cast(early_count as double) / nullif(timed_count, 0)
     or late_rate  is distinct from cast(late_count  as double) / nullif(timed_count, 0)
     or coverage_rate is distinct from cast(observed_count as double) / nullif(scheduled_count, 0)
     or skip_rate is distinct from cast(skipped_count as double) / nullif(observed_count, 0);
  ```
  (Adapt column names to the mart contract — from the contract YAML, not
  from the SQL that computes them.) Expected: zero rows, fixtures AND real
  data.
- **U2 — ratio structure (D1).** In the semantic YAML: each of
  coverage_rate, otp_rate, early_rate, late_rate, skip_rate is declared
  `type: ratio` with the numerator/denominator pairs from metrics.md §2.
  Any rate as `derived`, `simple`-over-prediv, or a mart-only formula =
  FAIL.
- **U3 — no-coalesce (D2).** `grep -rinE 'coalesce|ifnull|zeroifnull'
  dbt/models/marts dbt/models/semantic` → every hit touching a measure,
  metric, or rate column = FAIL; other hits = findings to justify.
- **U4 — perturb in a scratch copy (F-G02).** `cp -r` the clone to a second
  scratch dir; apply `docs/perturb_mart.patch` THERE; run `make parity`
  there. Expected: FAIL naming otp_rate. Then confirm your original clone
  is untouched (`git status` clean). A parity harness that stays green
  under perturbation is itself the finding.
- **U5 — NULL storage (metrics.md §3).** For the F-M03 cell:
  `select otp_rate from <mart> where <cell predicate>` → SQL NULL (render
  as NULL in the CLI, not 0.0, not 1.0, not 0).
- **U6 — window law (FR-M3/F-M05).** Compute the F-M05 7-day window otp
  from mart count columns yourself: (900+1)/(1000+10) = 0.892079…; confirm
  no mart or helper exposes a pre-averaged multi-day rate column; the
  0.500000 result anywhere is a FAIL.

Recurring invariant probes: **G1** (skipped provenance spot-check still
holds on the current build — one query), **G5**, **G9** as in audit-p0.

## 4. Verification ladder

(a) FR-M1..M4 ACs — verdict + command + output. FR-M2 at BOTH declared
    grains: route (service_date, route_short_name, day_type) and system
    (service_date).
(b) Probes U1–U6 + the oracle-table comparisons.
(c) Fixture re-runs: F-M01–F-M05, F-G01–F-G03 (determinism diff output
    pasted).
(d) UI: n/a.

## 5. Report contract

(1) "I modified nothing." (+ note that U4 ran in a disposable copy);
(2) PASS/FAIL/NOT VERIFIABLE counts; (3) findings, most severe first —
claim, command, output, file:line, spec/DR ID; (4) **Residuals** —
mandatory; NOT VERIFIABLE never silently becomes PASS.

## 6. Stop conditions

- **REJECT**: any FAIL on parity (F-G01/02), a denominator (U1/oracles), a
  NULL rule (U5/F-M03), D1/D2 structure, or determinism (F-G03). These are
  published-number defects.
- **ACCEPTED-WITH-FINDINGS**: metric label wording, YAML syntax-variant
  issues already covered by the V-6/DR-024 decision, missing descriptions,
  time-spine range slack.
