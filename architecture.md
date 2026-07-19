# architecture.md — OC Transpo Reliability Tracker (rev 2, staged)

Supersedes rev 1 entirely. Rev 1 assumed Databricks from day one, Auto Loader
ingestion, and dbt Semantic Layer API serving; those are revised by
DECISIONS.md DR-014/015/021 and §10 below. Where this file and spec.md
overlap, spec.md's acceptance criteria govern.

## 1. Thesis

Measure OC Transpo reliability from independently captured GTFS-RT + static
GTFS, publish it bilingually with published methodology, and never let a
number lie: skips must be proven, missing telemetry is `no_data` (OC Transpo
itself reports ~5% position gaps), and every punctuality figure ships with
its coverage. Portfolio priorities: dbt/semantic layer → dimensional
modeling → production credibility.

## 2. Staged overview

```
v0 CAPTURE (always-on, Databricks-free)          v1 PRODUCT (nightly batch)
┌─────────────────────────────────────┐          ┌──────────────────────────────┐
│ Hetzner VPS (systemd timers)        │          │ GitHub Actions, nightly       │
│  collector 30s ─┐                   │   R2     │  pull parsed/ + static/       │
│  static daily ──┼→ local disk ──────┼─────────→│  dbt build (DuckDB, full      │
│  bundler+sync ──┘  hourly tar.zst / │ (durable)│   rebuild, all tests)         │
│  healthchecks pings on every path   │          │  mf validate + parity         │
└─────────────────────────────────────┘          │  dbt docs artifact            │
                                                 │  Evidence build → CF Pages    │
                                                 └──────────────────────────────┘
v2 MIGRATION (later, documented diff): same dbt project → Databricks Free Ed.
(UC external location on R2, Delta, COPY INTO, MERGE+lookback incremental,
Elementary, Genie internal demo). Public site never depends on it (DR-017).
```

Failure domains: host death = capture gap (≤ sync interval + hour in flight),
never loss of synced data (DR-008). Build failure = stale-but-correct site
(deploy gated on green, FR-P3). Databricks outage in v2 = no public impact.

## 3. v0 capture design

- **Feeds**: TripUpdates (timing backbone), VehiclePositions (enrichment
  only — DR-003), ServiceAlerts iff GTFS-RT (open V-1). 30s cadence matches
  the source's GPS update rate (DR-012).
- **Boundary validation**: Pydantic producer contracts; enum-checked
  schedule_relationship; failures → quarantine with the §5.3 (spec) contract.
- **Immutability**: raw .pb = verbatim pre-decode HTTP body (DR-030),
  archived atomically, collision-safe, append-only; hourly tar.zst bundles,
  atomically finalized with checksum manifests, all boundaries and paths
  UTC (DR-028/029). Parsed/quarantine → hourly .jsonl.gz (directly
  warehouse-readable). Static GTFS daily, sha256-deduped, manifest-tracked.
- **Citizenship**: content-hash unchanged-poll detection (skip re-store;
  every cycle lands a per-feed ledger row — outcome, unchanged flag,
  retries, record counts, feed header ts), bounded retry with jitter
  (≤3, inside the interval budget).
- **Observability at the edge**: healthchecks dead-man proves data was
  *written*, not merely that the process runs (DR-027); separate checks for
  bundler+sync and static snapshot; per-feed alerts (401/404 streaks,
  decode failures, stale feed header) on a dedicated feeds check (DR-032).

## 4. v1 warehouse design (dbt on DuckDB)

Layers: `staging` (typing/renames/UTC only) → `intermediate` (schedule
expansion, latest-update dedup, classification) → `core` (star schema,
contracts enforced) → `marts` (metric materializations the site reads) →
`semantic/` (MetricFlow YAML = metric SSOT, parity-tested against marts).

Deterministic full rebuild nightly from R2 (DR-021): no incremental state, no
dbt-snapshot state; SCD2 is *derived* from the static snapshot archive. The
whole warehouse is reproducible from R2 + a commit hash. Revisit when build
time exceeds 15 min.

Classification, service-date, dedup, and status semantics: normative
definitions live in spec.md §4; the answer key in fixtures/CASES.md §A;
metric formulas in metrics.md. This file does not restate them.

## 5. Star schema (column spec — contracts derive from this)

### fct_stop_event — grain: one scheduled stop-event (DR-004)
| column | type | notes |
|---|---|---|
| stop_event_key | VARCHAR | surrogate PK — dbt_utils.generate_surrogate_key(service_date, trip_id, stop_sequence); MetricFlow primary entity (semantic-layer.md D3) |
| service_date | DATE | part of natural key |
| trip_id | VARCHAR | natural key part (degenerate dimension) |
| stop_sequence | INTEGER | natural key part |
| route_key | BIGINT FK→dim_route | SCD2 version active on service_date |
| stop_key | BIGINT FK→dim_stop | SCD2 version active on service_date |
| date_key | DATE FK→dim_date | = service_date |
| schedule_version_key | BIGINT FK→dim_schedule_version | source snapshot |
| direction_id | SMALLINT | from static trips |
| scheduled_arrival_utc | BIGINT (epoch s) | noon−12h rule (CASES C10/C11) |
| observed_arrival_utc | BIGINT NULL | last-word-wins (spec §4) |
| delay_s | INTEGER NULL | NULL ⟺ status ∉ timed (tested) |
| status | VARCHAR | enum on_time/early/late/skipped/no_data |
| is_observed | BOOLEAN | status ≠ no_data |
| feed_timestamp | BIGINT NULL | provenance |
| _ingested_at | BIGINT NULL | provenance |
Uniqueness: (service_date, trip_id, stop_sequence). All FKs relationship-tested.

### dim_route (SCD2, derived — DR-021)
route_key PK · route_id · route_short_name · route_long_name · route_type ·
valid_from DATE · valid_to DATE NULL · is_current BOOL. No overlap/gap per
route_id (tested, CASES F-D01).

### dim_stop (SCD2, derived)
stop_key PK · stop_id · stop_name · stop_lat · stop_lon · valid_from ·
valid_to · is_current. Same interval tests.

### dim_date
date_key PK (DATE) · year · month · day · day_of_week ·
day_type ∈ {weekday, saturday, sunday_holiday} · is_holiday (seed:
Ontario/Ottawa observances) · is_dst_transition BOOL.

### dim_schedule_version
schedule_version_key PK · sha256 · snapshot_date · valid_from · valid_to.

### metricflow_time_spine
date_day (DATE), covering min(service_date)…today.

### Marts (contracts enforced; columns = metrics.md §2 + keys)
mart_reliability__route_daily (grain route_key × service_date; carries
route_id + route_short_name and all population counts alongside daily rates —
parity and site windows aggregate on counts, T1/T3 rules) ·
mart_reliability__system_daily (service_date) ·
mart_quality__daily (service_date) · mart_quality__feed_daily
(service_date × feed, sourced from ledger + quarantine) ·
mart_quality__added_trips (service_date).

## 6. Semantic layer mechanism (revision of rev-1 §6)

MetricFlow YAML in-repo is the single metric SSOT: validated in CI
(`mf validate-configs`), queried on fixtures, and **materialized** into the
marts the site reads. Parity CI proves mart = metric definition (F-G01/02).
Dynamic SL API serving (paid dbt platform) is explicitly not used; the
governance claim — one CI-validated definition per number — holds via parity,
not via a serving endpoint. v2 revisits serving on Databricks; the YAML moves
unchanged.

## 7. Observability (five pillars + source errors — DR-016)

| pillar | v1 mechanism | v2 addition |
|---|---|---|
| freshness | dbt source freshness on _ingested_at (3h/12h) + dead-man | Elementary learned baselines |
| volume | custom seasonal band test (day_type-aware, ±30%) | Elementary volume anomalies (day_of_week seasonality) |
| schema | Pydantic producer contracts + dbt model contracts + CI guard | Elementary schema monitors, UC |
| distribution | dbt-expectations bounds/null-rate/accepted-values; no_data share ceiling | Elementary column anomalies |
| lineage | dbt docs DAG published nightly | Unity Catalog lineage |
| source errors | quarantine contract + rate threshold (5%) + unchanged-poll and poll-success in mart_quality__daily | Elementary on quarantine tables |

Authority rule (DR-010): anything *published* derives from warehouse models;
collector-side counters are operational telemetry only.

## 8. Configuration reference (single source; all are env/dbt vars)

| var | default | consumer | meaning |
|---|---|---|---|
| POLL_INTERVAL_S | 30 | collector | feed poll cadence (DR-012) |
| RETRY_MAX / RETRY_BASE_MS | 3 / 500 | collector | bounded backoff |
| ENDPOINT_FAIL_STREAK | 10 | collector | per-feed consecutive fetch-failure alert threshold (FR-C8) |
| STALE_FEED_ALERT_S | 1800 | collector | feed-header-age fail-ping threshold, 24/7 (DR-027; re-tuned at V-P1) |
| STALE_BANNER_DAYS | 3 | site | public staleness banner trigger (FR-P4) |
| STATIC_MAX_MB | 200 | collector | snapshot download cap |
| RETENTION_DAYS | 7 | ops | local prune age (post-verified sync) |
| OTP_EARLY_S / OTP_LATE_S | 60 / 300 | dbt, site | on-time window (DR-022, V-2) |
| MIN_EVENTS | 200 | marts, site | ranking sample floor (FR-M4) |
| VOLUME_BAND_PCT | 30 | dbt test | seasonal volume tolerance |
| QUARANTINE_RATE_MAX | 0.05 | dbt test | source-error ceiling |
| NO_DATA_SHARE_MAX | 0.40 | dbt test | coverage floor alarm |
| FRESH_WARN_H / FRESH_ERROR_H | 3 / 12 | dbt sources | build-time freshness |
| TZ (dbt-date var) | America/Toronto | dbt-expectations | temporal tests |

Changing a default = config commit + methodology page auto-reflects (FR-P2)
+ DR line if it alters published semantics.

## 9. Security posture
Least-privilege everywhere: R2 token scoped to one bucket; Pages token scoped
to one project; GHA `permissions: contents: read` baseline; SHA-pinned
actions + Dependabot; env-indirection in workflows; secrets never in repo or
fixtures; VPS: non-root service user, ufw default-deny inbound (ssh only),
unattended-upgrades.

## 10. v2 outline (pointer, not spec)
Same dbt project re-targeted at Databricks Free Edition: UC external location
on R2 (verify — DR-009), COPY INTO bronze (DR-015), Delta core with
MERGE+lookback incremental replacing full rebuild, Elementary adoption
(DR-016), Genie as internal demo (DR-013). Deliverable = migration diff:
what ported, what didn't, why. Written as its own spec when v1 ships.
