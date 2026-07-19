# Audit prompt — Phase P4: Observability (checkpoint V-P4)

Run in a FRESH session after the builder declares P4 complete. Stack class:
**alerting correctness** — a monitor that cannot fire, or that cries wolf,
recreates the silent-failure mode the capture audit's F-01 closed.

## 1. Session setup (binding)

- READ-ONLY audit. Findings, never fixes. Probe U1 mutates only a scratch
  profile/vars override, never repo files.
- Fresh clone in scratch:
  ```bash
  git clone https://github.com/AMikhno/OC_Transpo_Analytics "$SCRATCH/audit-p4"
  cd "$SCRATCH/audit-p4" && uv sync --all-groups
  ```
- Report begins with the literal sentence: **"I modified nothing."**
- Builder claims are not evidence; every verdict cites your own command +
  output. GHA run history is admissible only as linked evidence for the
  explicitly NOT-VERIFIABLE nightly item (see §4).
- Expected values come from spec FR-O1..O6, architecture.md §8 defaults,
  CASES §F — never from test code.

## 2. Binding scope

| ID | One-line restatement |
|---|---|
| FR-O1 | source freshness on `_ingested_at`: warn 3 h / error 12 h |
| FR-O2 | seasonal volume band ±VOLUME_BAND_PCT; activates at ≥4 prior periods |
| FR-O3 | contract-change CI guard; producer + model contracts |
| FR-O4 | distribution: delay bounds, status set, FK null ceilings, no_data share |
| FR-O5 | dbt docs artifact with full DAG each nightly |
| FR-O6 | quality marts split by grain; quarantine rate > 5% fails the build |

Plus plan.md P4.1–P4.5, CASES §F (F-O01–F-O05), DR-016. Out of bounds:
metric formulas (P3), site rendering of the quality page (P5).

## 3. Independence rules and designed probes

Re-runs:

```bash
uv run dbt build --project-dir dbt --profiles-dir dbt --target fixtures --select tag:observability
make obs-failcases
```

`obs-failcases` must show each staged violation failing its NAMED test and
only that test — one unrelated test failing alongside is a finding
(cross-contamination), one violation failing zero tests is a FAIL.

Designed probes:

- **U1 — thresholds live in config (architecture §8).** In a scratch vars
  override (e.g., `--vars '{volume_band_pct: 5}'` or the repo's documented
  mechanism — read it from dbt_project.yml, not from test code), rerun the
  volume test on the NORMAL fixture: previously-passing daily variance must
  now FAIL. Restore default: passes again. Repeat once for
  QUARANTINE_RATE_MAX at 0.001 → normal fixture fails. If behavior does not
  change with the var, the threshold is hardcoded = FAIL (spec: "never
  hardcoded literals in logic", CLAUDE.md §4).
- **U2 — activation boundary from both sides (F-O05).** Fixture history
  with exactly 3 prior same-day_type periods → volume test reports
  not_enough_history, build green. Add one period (4 total) → test
  enforces. The builder likely tested one side; both must hold.
- **U3 — freshness both sides (FR-O1).** Fixture `_ingested_at` 13 h old →
  freshness ERROR (F-O03). 2 h old → pass, no warn. 4 h old → WARN, not
  error. Three verdicts.
- **U4 — quarantine threshold edges (FR-O6).** 6% day → threshold test
  fails naming that day; 4% day → passes. (F-O02 reruns the 8% case; the
  4%-passes side is the unanticipated half.)

Recurring invariant probes: **G5**, **G9** as in audit-p0; **G7** on the
new/changed workflows (`nightly.yml`): `grep -n '\${{' .github/workflows/`
— hits inside `run:` = FAIL (FR-CI3); also confirm nightly authenticates
with the READ-ONLY R2 token secret name, not the collector's (FR-CI5 —
check the workflow's secret references, not the secret values).

## 4. Verification ladder

(a) FR-O1..O6 ACs — verdict + command + output each. FR-O3: add a column to
    a contracted model in a scratch copy → CI-equivalent check fails
    (state:modified guard); scratch copy discarded.
(b) Probes U1–U4.
(c) Fixture suite: F-O01–F-O05 re-run; each Expected column checked against
    observed behavior, not against the test's assertion.
(d) UI: n/a here (quality page is P5). **Nightly greenness over ≥3 real
    nights (P4.5) is NOT VERIFIABLE inside this session** — record it as
    such and cite the GHA run URLs + the forced-fail night's alert evidence
    for the operator to confirm; do not mark PASS on the builder's
    say-so.

## 5. Report contract

(1) "I modified nothing." (+ scratch-copy note for U1/FR-O3);
(2) PASS/FAIL/NOT VERIFIABLE counts; (3) findings, most severe first —
claim, command, output, file:line, spec ID; (4) **Residuals** — mandatory;
NOT VERIFIABLE never silently becomes PASS.

## 6. Stop conditions

- **REJECT**: any staged violation that fails to fire its test; any normal
  fixture that a test wrongly fails (both directions of U1–U4); a
  hardcoded threshold; nightly workflow using the write token. A monitor
  wrong in either direction is a data-integrity risk.
- **ACCEPTED-WITH-FINDINGS**: docs-artifact cosmetics, test naming, quality
  -mart column naming, cross-contaminated-but-correct failure sets.
