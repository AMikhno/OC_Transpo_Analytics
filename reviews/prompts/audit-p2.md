# Audit prompt — Phase P2: Warehouse backbone (checkpoint V-P2)

Run in a FRESH session after the builder declares P2 complete. Stack class:
**accounting** — this layer decides what every published number will say;
classification and service-date defects propagate to everything downstream.

## 1. Session setup (binding)

- READ-ONLY audit. Findings, never fixes.
- Fresh clone in scratch:
  ```bash
  git clone https://github.com/AMikhno/OC_Transpo_Analytics "$SCRATCH/audit-p2"
  cd "$SCRATCH/audit-p2" && uv sync --all-groups
  ```
- Report begins with the literal sentence: **"I modified nothing."**
- Builder claims are not evidence. Every verdict cites your own command +
  output from this session.
- Expected values come from spec.md §4, fixtures/CASES.md §A/§D, and the
  pre-computed constants in §3 below — never from model SQL. Where the code
  and CASES.md disagree, CASES.md wins (its own maintenance rule: the
  implementation is wrong OR the table gets a reviewed correction commit —
  check `git log fixtures/CASES.md` for silent edits and report any
  Expected-column change lacking a DR line).

## 2. Binding scope

| ID | One-line restatement |
|---|---|
| FR-W1 | deterministic full rebuild; identical inputs → identical marts |
| FR-W2 | staging = typing/renames/UTC only; no joins, no logic |
| FR-W3 | dedup keeps max(feed_timestamp, _ingested_at) per stop-event |
| FR-W4 | schedule expansion: snapshot-versioned, calendar_dates, >24:00 |
| FR-W5 | classification per spec §4 exactly; precedence skipped ▶ timed ▶ no_data |
| FR-D1 | star schema, contracts, uniqueness (service_date, trip_id, stop_sequence) |
| FR-D2 | SCD2 derived from snapshot archive; point-in-time joins |
| FR-D3 | metricflow_time_spine covers the data range |

Plus spec §4 definitions (service_date, observed arrival, status, ADDED),
plan.md P2.1–P2.7, CASES §A (C01–C15, C09b, C11b) and §D (F-D01–F-D04).
Out of bounds: metric YAML/marts arithmetic (P3), site (P5).

## 3. Independence rules, pre-computed constants, designed probes

Re-runs from clean clone:

```bash
make check
uv run dbt build --project-dir dbt --profiles-dir dbt --target fixtures
uv run dbt build --project-dir dbt --profiles-dir dbt --target fixtures --select int_stop_events__classified+
```

**Pre-computed expected epochs** — derived from spec §4 + the noon−12h rule
+ CASES setups, independent of any code. Compare model output to these
exact integers:

| Case | Scheduled stop time | Expected scheduled_arrival_utc | Renders as |
|---|---|---|---|
| C01 | 08:00:00, 2026-06-15 | **1781524800** | 2026-06-15T12:00:00Z |
| C10 | 25:15:00, 2026-06-15 | **1781586900** | 2026-06-16T05:15:00Z |
| C11 | 08:00:00, 2026-11-01 (fall-back) | **1793538000** | 2026-11-01T13:00:00Z |
| C11b | 01:30:00, 2026-11-01 | **1793514600** | 2026-11-01T06:30:00Z |

The value 1793511000 (05:30:00Z) for C11b is the naive-local-midnight DST
bug signature CASES C11b exists to catch — if you see it, that is a FAIL
with the diagnosis already written.

Designed probes:

- **U1 — partition law on REAL data (G4 family).** Over the full
  fct_stop_event from the real-R2 run (P2.7), not fixtures:
  ```sql
  select service_date,
         count(*) as s,
         sum(case when status in ('on_time','early','late') then 1 else 0 end) as timed,
         sum(case when status = 'skipped' then 1 else 0 end) as skipped,
         sum(case when status = 'no_data' then 1 else 0 end) as no_data
  from fct_stop_event group by 1
  having s <> timed + skipped + no_data;
  ```
  Expected: zero rows. Also: `select count(*) from fct_stop_event where
  (delay_s is null) <> (status not in ('on_time','early','late'))` → 0.
- **U2 — skip provenance (G1).** Anti-join every status='skipped' row back
  to the parsed stream: each must correspond to a trip-level CANCELED or
  stop-level SKIPPED record for that (service_date, trip_id[, stop]).
  Expected: 0 orphans. Paste one full end-to-end trace (fct row → parsed
  record) as evidence.
- **U3 — determinism (FR-W1).** Run the build twice on identical local
  input; compare: fct row count, and three aggregates you choose (e.g.,
  sum(delay_s) over timed, count by status, max(observed_arrival_utc)).
  Expected: byte-identical.
- **U4 — ADDED exclusion (spec §4).** Fixture ADDED trip: `select count(*)
  from fct_stop_event where trip_id = 'T99'` → 0; appears exactly once in
  mart_quality__added_trips (or its P2-era staging equivalent — if the mart
  doesn't exist yet, mark d NOT VERIFIABLE and say which model you checked).
- **U5 — hand count from the source zip (validation V-P2.3, auditor's
  choice).** Pick one real (route, service_date) yourself. Count scheduled
  stop-events directly from the static GTFS snapshot with duckdb over the
  zip's stop_times/trips/calendar (+calendar_dates), honoring the calendar
  rules in spec §4 — command sketch:
  ```sql
  -- duckdb: read stop_times.txt/trips.txt/calendar.txt from the snapshot zip,
  -- filter trips to route + service_id active on the chosen date,
  -- count stop_times rows for those trips
  ```
  Expected: equals `select count(*) from fct_stop_event where route =
  <yours> and service_date = <yours>` exactly (Q1 = Q2). Any delta = FAIL.

Recurring invariant probes: **G5**, **G9** as in audit-p0; **G12** extended
to `dbt/models` (`grep -rnE 'now\(\)|current_timestamp|localtimestamp'
dbt/models` — hits outside documented presentation edges are findings).
FR-W2 check: `grep -rniE 'join |case when' dbt/models/staging` → every hit
is a finding (staging must contain no joins/logic).

## 4. Verification ladder

(a) FR-W1..W5, FR-D1..D3 ACs — verdict + command + output each. Uniqueness:
    `select service_date, trip_id, stop_sequence, count(*) from
    fct_stop_event group by 1,2,3 having count(*) > 1` → 0 rows.
(b) Probes U1–U5 + the four epoch-constant comparisons.
(c) Fixture harness: the 12-case singular test re-run; verify each CASES §A
    row's Expected column against actual model output — not against the
    test's own assertion (assertions can be wrong in the same way the code
    is; the table is the oracle). C15: confirm the record is in quarantine
    with type=service_date_unresolved and absent from fct.
    F-D01/02: dim_stop versions + point-in-time join; F-D03: zero events on
    the removed date; F-D04: pre/post-snapshot times 08:00 vs 08:10.
(d) UI: n/a.

## 5. Report contract

(1) "I modified nothing."; (2) PASS/FAIL/NOT VERIFIABLE counts; (3)
findings, most severe first — claim, command, output, file:line, spec ID;
(4) **Residuals** — mandatory; NOT VERIFIABLE never silently becomes PASS.

## 6. Stop conditions

- **REJECT**: any FAIL on classification (FR-W5/CASES §A), service-date
  epochs (the four constants), dedup (FR-W3/C09/C09b), the partition law,
  fct uniqueness, skip provenance, or point-in-time SCD joins (F-D02).
  These are accounting defects — every downstream number inherits them.
- **ACCEPTED-WITH-FINDINGS**: build time > 15 min on real data (report the
  number; DR-021 revisit trigger), staging-purity grep hits that are
  provably type-casts, doc/column-description gaps.
- NOT VERIFIABLE is expected for items requiring data volumes that don't
  exist yet (say precisely which and why).
