# plan.md — v1 build plan

Mode: step-by-step (task loop). One task = one commit = one runnable state.
Ana verifies at every ✅ checkpoint using validation.md; the agent never
self-certifies a checkpoint. Phases are strictly ordered; tasks within a phase
are ordered unless marked ∥ (parallel-safe).

Capture urgency note: P1 (capture live on VPS) is the calendar-critical path —
every day before it runs is unrecoverable history. P0 is small; do not let it
sprawl. Ana may provision the VPS (V-P1 prep) while P0 is in progress.

---

## Phase 0 — Collector hardening (agent, local)
Exit: existing collector satisfies FR-C1..C9 + §5.2/5.3 on fixtures; CI green.

- **P0.1** Fixture harness: deterministic .pb fixtures + builders for all §7
  collector cases; wire `make check`. Done when: pytest runs fixtures offline.
- **P0.2** FR-C1 atomic collision-safe raw writes (+ tests).
- **P0.3** FR-C2 bounded retry/backoff (+ mocked-endpoint tests).
- **P0.4** FR-C3 `_ingested_at` everywhere; update models + tests.
- **P0.5** FR-C6/§5.3 QuarantineRecord unification (+ AC-5.3.1 test).
- **P0.6** §5.2 enum enforcement → quarantine `unknown_enum` (+ AC-5.2.1).
- **P0.7** FR-C5 staleness counter + skip-parsed-on-unchanged (+ tests).
- **P0.8** FR-C4 bilingual translations map (guarded by V-1; if RSS/absent,
  implement the map for TripUpdates' own translated fields only and record DR).
- **P0.9** FR-C7 static snapshot: streaming download, size cap, sha256 dedupe.
- **P0.10** FR-C8 endpoint-change detection + FR-C9 graceful shutdown.
- **P0.11** Hardening batch: SHA-pin actions + Dependabot (FR-CI2), env
  indirection + permissions block (FR-CI3), mypy strict + gitleaks +
  `uv lock --check` in CI (FR-CI1/CI5), bump requires-python to >=3.12.
- ✅ **Checkpoint V-P0** (validation.md §P0)

## Phase 1 — Capture live: VPS + R2 (Ana hands-on; agent writes artifacts)
Exit: 48h of verified capture in R2; volumetrics recorded; alerts proven.

- **P1.1** (agent) `ops/`: hourly bundler (FR-Y1), verified sync + prune
  (FR-Y2), healthcheck pings (FR-Y3), all with unit tests on tmpdirs.
- **P1.2** (agent) systemd unit files + install runbook `ops/README.md`
  (FR-Y4), R2 bucket/token setup steps, healthchecks setup steps.
- **P1.3** (Ana) Provision Hetzner CAX11, create R2 bucket + scoped token,
  install per runbook, start timers, confirm healthchecks green.
- **P1.4** (Ana) Kill-tests: stop timer → dead-man alert; wrong-bucket sync →
  non-zero + no prune; reboot → all units return (FR-Y4 AC).
- **P1.5** (both) After 48h: run `ops/volumetrics.py` (agent writes) →
  measured sizes/counts; update spec §8 + DECISIONS.md; confirm R2 free-tier
  headroom.
- ✅ **Checkpoint V-P1**

## Phase 2 — Warehouse backbone (agent)
Exit: nightly-shaped local build produces classified fct_stop_event from
fixtures AND from real R2 data; all FR-W/FR-D ACs green.
Sequencing: P2.1–P2.6 are fixture-only and run ∥ with Phase 1's 48-hour
capture window (agent works while the clock runs); only P2.7 requires V-P1.

- **P2.1** dbt project skeleton per CLAUDE.md §3–4; profiles (local + fixtures
  targets); sqlfluff config; dbt-utils + dbt-expectations pinned, tz var set.
- **P2.2** Staging models for parsed feeds + static tables (FR-W2) + sources
  with freshness config (FR-O1 thresholds).
- **P2.3** `int_schedule__stop_events` (FR-W4) — fixture-first: 25:30, DST,
  calendar_dates cases before real data.
- **P2.4** `int_trip_updates__latest` dedup (FR-W3).
- **P2.5** Classification `int_stop_events__classified` (FR-W5) against the
  12-case answer key; singular test wired into `make check`.
- **P2.6** Dims: dim_date (+holiday seed, day_type), dim_route/dim_stop SCD2
  from snapshot archive (FR-D2 point-in-time test), dim_schedule_version,
  metricflow_time_spine (FR-D3).
- **P2.7** `fct_stop_event` with contracts + uniqueness + relationships
  (FR-D1); first full run over real R2 history; record row counts.
- ✅ **Checkpoint V-P2** (includes Ana's hand-verified numbers, validation.md)

## Phase 3 — Metrics & semantic layer (agent)
Exit: metric YAML = SSOT; parity CI proves marts match; determinism proven.

- **P3.1** V-3 + V-6 spike: `dbt-metricflow[duckdb]` validate + query on
  fixtures; syntax decision per semantic-layer.md §4; DR-024 the outcome.
- **P3.2** Semantic models + metrics YAML from semantic-layer.md §7 draft
  (design decisions D1–D7 are fixed; syntax per P3.1); `mf validate-configs`
  in CI (FR-M1).
- **P3.3** Gold marts: `mart_reliability__route_daily`,
  `mart_reliability__system_daily`, `mart_quality__daily`,
  `mart_quality__added_trips`; contracts + FR-M4 threshold logic.
- **P3.4** Parity harness (FR-M2) incl. the perturb-test proving it fails.
- **P3.5** Determinism check (FR-W1 AC): two identical builds → identical
  metric values; wire as CI job on fixtures.
- ✅ **Checkpoint V-P3**

## Phase 4 — Observability, native (agent)
Exit: five pillars + source errors enforced in build; quality mart feeds site.

- **P4.1** `volume_within_seasonal_band` custom generic test (FR-O2) with
  pass/fail fixtures. ∥
- **P4.2** dbt-expectations distribution suite (FR-O4). ∥
- **P4.3** Quality mart completion (FR-O6) + quarantine-rate threshold test. ∥
- **P4.4** Contract-change CI guard (FR-O3); dbt docs artifact in nightly
  (FR-O5).
- **P4.5** `nightly.yml`: R2 pull → dbt build (all tests) → docs → artifacts;
  failure pings healthchecks build-check. Runs green on real data 3 nights.
- ✅ **Checkpoint V-P4**

## Phase 5 — Site (agent; Ana reviews behavior only)
Exit: bilingual site live on Cloudflare Pages from real marts.

- **P5.1** V-4 spike: Evidence + DuckDB artifact wiring; record versions.
- **P5.2** EN pages: Overview, Routes, Route detail (FR-P2, FR-M4/M5 states).
- **P5.3** Methodology + Data Quality + About pages, config-driven numbers,
  attribution + disclaimer (FR-P2, DR-019).
- **P5.4** FR structure + language toggle (FR-P1); translations reviewed by Ana.
- **P5.5** `deploy.yml` → Cloudflare Pages, gated on green build (FR-P3),
  incl. the forced-red no-deploy proof.
- ✅ **Checkpoint V-P5**

## Phase 6 — Launch & portfolio layer (agent drafts; Ana approves)
- **P6.1** README rewrite: hiring-reviewer-first (thesis → architecture sketch
  → metrics/honesty story → decision-record index → quickstart). LICENSE
  (Apache-2.0), badges, repo topics.
- **P6.2** DECISIONS.md finalized (all DRs + open-item outcomes); docs/ synced
  to site methodology.
- **P6.3** Fresh-session audit (validation.md §Audit) run against spec.md;
  findings triaged; fixes committed.
- **P6.4** Tag v1.0.0.
- ✅ **Checkpoint V-P6 / launch**

## Standing rules
- A blocked task → STOP + written question; the answer becomes a DR line.
- Any deviation from spec discovered mid-task → surface it; never silently
  reconcile (CLAUDE.md guardrail 11).
- After each phase, Ana pushes; the agent never pushes.
