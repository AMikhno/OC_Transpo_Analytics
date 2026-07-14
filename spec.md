# spec.md — OC Transpo Reliability Tracker, v1

Every requirement has acceptance criteria (AC). No criterion, no requirement.
IDs are stable: cite them in commits, reviews, and audits.

## 1. Intent

Measure and publish OC Transpo service reliability from independently collected
GTFS-RT and static GTFS data, with honest denominators: a skip must be proven,
missing telemetry is never bad service, and coverage is reported alongside every
metric. Secondary intent: portfolio-grade demonstration of dbt, semantic-layer,
and dimensional-modeling craft (see DECISIONS.md for priority ordering).

## 2. Users

- **Public visitor** (EN or FR): sees route/system reliability, understands the
  method, can verify claims via the methodology + quality pages.
- **Owner/operator (Ana)**: runs the system unattended; is alerted on capture or
  build failure; verifies correctness without reading implementation code.
- **Reviewer (hiring manager/engineer)**: evaluates repo in ≤15 minutes; must
  find modeling, metrics, tests, and decision trail without digging.

## 3. Scope

### 3.1 In scope (v1)
Collector hardening; VPS+R2 capture pipeline; nightly deterministic DuckDB
build; star schema; status classification; MetricFlow metric definitions with
parity-materialized gold marts; five-pillar native observability + source-error
handling; bilingual Evidence site with methodology and data-quality pages;
full CI; public repo hygiene (license, attribution, decision records).

### 3.2 Out of scope (v1) — guardrail, not suggestion
Databricks/UC/Delta/COPY INTO (v2); Elementary (v2); geospatial/H3 (parked);
alerts-feed modeling (collection continues if the feed exists; no models);
user accounts, comments, or any interactivity beyond navigation/filtering;
realtime (<hourly) freshness; incremental builds; paid services of any kind.

## 4. Definitions

- **service_date**: the GTFS service day a trip belongs to. Join key between
  realtime and schedule. Derivation: use GTFS-RT `trip.start_date` when present.
  Fallback (start_date absent): candidate service_dates = {today, yesterday}
  in agency tz; select the candidate where the trip's calendar is active AND
  the referenced stop's scheduled time is nearest to the observation; if both
  candidates are inactive or the tie is unresolvable, quarantine the record
  with type=service_date_unresolved (CASES C15) — never guess. All duration math on epoch seconds (CLAUDE.md guardrail 12).
- **scheduled stop-event**: one (service_date, trip_id, stop_id, stop_sequence)
  from static GTFS for a service_date that was active per calendar/calendar_dates.
- **observed arrival**: for a (service_date, trip_id, stop_sequence), the arrival
  time from the TripUpdates record with the greatest `feed_timestamp`
  (tie-break: greatest `_ingested_at`). Last word wins.
- **delay_s** = observed_arrival_epoch − scheduled_arrival_epoch.
- **status** (exactly one per scheduled stop-event):
  `skipped` (proven: trip-level CANCELED or stop-level SKIPPED relationship) →
  `on_time` if −OTP_EARLY_S ≤ delay_s ≤ +OTP_LATE_S →
  `early` if delay_s < −OTP_EARLY_S → `late` if delay_s > +OTP_LATE_S →
  `no_data` if no TripUpdates record references the stop-event.
  Defaults: OTP_EARLY_S=60, OTP_LATE_S=300 — config vars; pending verification
  against OC Transpo's published OTP definition (DECISIONS.md, open item V-2).
- **coverage** = share of scheduled stop-events with status ≠ no_data.
- **ADDED trips** (no scheduled baseline): excluded from fct_stop_event and all
  punctuality metrics; counted in `mart_quality__added_trips` for transparency.

## 5. Data contracts

### 5.1 Sources
TripUpdates + VehiclePositions (protobuf, OC Transpo Azure APIM, `/beta/v1/`
paths, key header `Ocp-Apim-Subscription-Key`); static GTFS zip. ServiceAlerts:
conditional — collected iff a GTFS-RT endpoint exists (open item V-1); never
modeled in v1.

### 5.2 Producer contracts (collector boundary)
Pydantic models validate every parsed record. `schedule_relationship` is
validated against the GTFS-RT enum; unknown values are quarantined with reason
`unknown_enum` (resolves doc/code mismatch — the contract is now as documented).
- **AC-5.2.1**: a fixture protobuf with an out-of-enum relationship lands in
  quarantine with `type=unknown_enum`, not in parsed.
- **AC-5.2.2**: every parsed record carries `_ingested_at` (UTC epoch of fetch)
  and `feed_timestamp`.

### 5.3 Quarantine contract
`QuarantineRecord = {feed, fetched_at, entity_id, raw_record, errors:
list[{loc, msg, type}]}`. Single schema for all rejection paths.
- **AC-5.3.1**: the VehiclePositions missing-position path emits
  `errors=[{loc:["position"], msg:"missing position", type:"missing_field"}]` —
  same shape as Pydantic-derived errors.
- **AC-5.3.2**: `stg_quarantine` parses 100% of quarantine files in fixtures
  with zero casting hacks (no typeof/CASE on `errors`).

### 5.4 Landing layout (R2 and local mirror)
```
raw/{feed}/{yyyy-mm-dd}/{feed}_{HH}.tar.zst        # hourly bundle of .pb polls
parsed/{feed}/{yyyy-mm-dd}/{feed}_{HH}.jsonl.gz    # hourly rotated records
quarantine/{feed}/{yyyy-mm-dd}/{feed}_{HH}.jsonl.gz
ledger/{feed}/{yyyy-mm-dd}/{feed}_{HH}.jsonl.gz    # one row per feed per cycle
static/{yyyy-mm-dd}/gtfs_{sha256-8}.zip + manifest.json
```
- **AC-5.4.1**: nightly build reads `parsed/`, `quarantine/`, `ledger/`, and
  `static/`; raw is archive only, never a build input.
- **AC-5.4.2**: two consecutive identical static zips produce one stored object
  (sha256 dedupe) and a manifest entry noting the no-change check.

## 6. Functional requirements

### FR-C — Collector (extends existing `ingestion/`)
- **FR-C1 Atomic, collision-safe raw writes.** Temp-file + rename; filename
  includes a monotonic or content-hash suffix; open mode excludes overwrite.
  AC: two writes within the same second on the same feed produce two files;
  kill -9 during write leaves no partial file visible in `raw/`.
- **FR-C2 Bounded retry.** Per-feed: ≤3 attempts, exponential backoff + jitter,
  total ≤ poll interval budget. AC: with a mocked 2×failure→success endpoint,
  one poll cycle succeeds and logs 2 retries; with permanent failure, the cycle
  records a failed poll and the loop continues on schedule (no drift pile-up).
- **FR-C3 `_ingested_at`** on every parsed and quarantined record. AC-5.2.2.
- **FR-C4 Bilingual alert capture** (only if V-1 confirms a GTFS-RT feed): all
  `translation` entries preserved as `{language: text}` map; no index-0 grabs.
  AC: fixture with EN+FR translations round-trips both.
- **FR-C5 Staleness detection + poll ledger.** Every cycle appends one ledger
  row per enabled feed: {feed, cycle_ts, outcome, http_status, unchanged,
  retries, _ingested_at}. If payload content-hash equals the previous poll's,
  mark unchanged=true and skip re-storing parsed output (raw still archives).
  The ledger is the Bronze source for poll success rate, unchanged share, and
  post-hoc FR-C8 audit (DR-010: published numbers derive from landed data).
  AC: replaying the same fixture twice stores parsed once and lands two ledger
  rows, the second with unchanged=true; a failed cycle still lands a ledger
  row with its outcome (CASES F-C10).
- **FR-C6 Quarantine contract** per §5.3.
- **FR-C7 Static snapshot automation.** Daily systemd timer runs
  `snapshot-static`; sha256 dedupe per AC-5.4.2; size cap (default 200 MB) and
  streamed download. AC: oversized fixture URL aborts with a clear error and
  no partial file.
- **FR-C8 Per-feed failure alerting.** ≥N consecutive **post-retry failed
  cycles** for any single feed (cycle fails after FR-C2 retries exhaust:
  non-2xx, timeout, or connection error; default 10) triggers a
  healthchecks fail-ping naming the feed — distinct from the dead-man channel,
  so feed death and host death are distinguishable. AC: mocked 404 streak
  fires exactly one alert ping naming the feed; recovery clears state; a
  mixed cycle (one feed failing, others fine) never suppresses the streak.
- **FR-C9 Graceful shutdown.** SIGTERM finishes the in-flight poll, flushes,
  exits 0 (systemd-friendly). AC: SIGTERM during a loop leaves valid files and
  a clean exit code.

### FR-Y — Sync & ops (`ops/`)
- **FR-Y1 Hourly bundler.** Closes the previous hour: raw .pb → tar.zst;
  parsed/quarantine per-poll files → single .jsonl.gz per hour. Idempotent.
  AC: rerunning the bundler on an already-bundled hour is a no-op (exit 0,
  no duplicate objects).
- **FR-Y2 Verified sync.** rclone copy to R2 then `rclone check`; only
  checked hours become prune-eligible; prune after RETENTION_DAYS (default 7).
  AC: simulated failed upload (wrong bucket) leaves local files intact and
  exits non-zero; successful path prunes only checked, aged hours.
- **FR-Y3 Dead-man wiring (process liveness).** The collector pings its
  healthchecks check on every *completed* cycle regardless of per-feed
  outcomes (feed health is FR-C8's separate channel); bundler/sync and static
  snapshot ping their own checks. AC: stopping the timer produces an alert
  within the grace window; a persistently failing single feed keeps the
  dead-man green while FR-C8 fires (CASES F-Y05) — the two failure modes are
  never conflated.
- **FR-Y4 systemd units** for collector loop, hourly bundler+sync, daily static
  snapshot; installable via documented commands; survive reboot (enabled).
  AC: `systemctl status` shows all three active after a VPS reboot.

### FR-W — Warehouse build (nightly, deterministic)
- **FR-W1 Full rebuild from R2** (DR-021): GHA nightly job pulls `parsed/`,
  `quarantine/`, `ledger/`, `static/` (or reads via httpfs), runs `dbt build`,
  produces the site DuckDB artifact. Scheduled at a fixed UTC cron (default
  08:00 UTC); the ET wall-clock time shifts one hour across DST — accepted
  under the daily SLO (DR-011). AC: two consecutive runs on the same R2 state
  produce byte-stable mart row counts and identical metric values.
- **FR-W2 Staging**: one stg model per landed entity; typing, renames, UTC
  normalization only. AC: staging models contain no joins and no business logic
  (reviewable by pattern; enforced by convention checks in CI).
- **FR-W3 Dedup rule**: `int_trip_updates__latest` keeps, per (service_date,
  trip_id, stop_sequence), the record with max(feed_timestamp, _ingested_at).
  AC: fixture with 3 conflicting updates yields exactly the last one.
- **FR-W4 Scheduled baseline**: `int_schedule__stop_events` expands, for each
  service_date, the snapshot version whose validity covers that date (CASES
  F-D04) into scheduled stop-events per §4, honoring calendar_dates
  add/remove and >24:00 stop_times. AC: fixtures cover (a) a 25:30:00 stop_time
  mapping to prior service_date with correct epoch, (b) DST fall-back day
  computing durations via epochs (no 1h error), (c) a calendar_dates removal
  producing zero scheduled events that day.
- **FR-W5 Classification** per §4 exactly, implemented in one model
  (`int_stop_events__classified`) with the status precedence order fixed
  (skipped ▶ timed ▶ no_data). AC: the fixture answer-key seed (≥12 cases:
  on-time boundary ±1s each side, early, late, trip-CANCELED, stop-SKIPPED,
  no_data, ADDED-excluded, duplicate-update, midnight-crossing, DST day,
  unknown-enum-quarantined upstream, zero-coverage trip) matches 100% via a
  singular test.

### FR-D — Dimensional model
- **FR-D1 Star**: `fct_stop_event` (grain = scheduled stop-event; degenerate
  trip attributes; FKs to dims; measures delay_s, status, observed flag) +
  `dim_route`, `dim_stop`, `dim_date` (incl. is_holiday from seed, day_type
  weekday/sat/sun-holiday), `dim_schedule_version`. AC: dbt contracts enforced
  on all core models; relationships tests pass; `fct_stop_event` uniqueness on
  (service_date, trip_id, stop_sequence).
- **FR-D2 SCD2 from snapshot archive** (DR-021): dim_route/dim_stop validity
  intervals derived deterministically from the ordered static snapshots
  (valid_from/valid_to, current flag); no dbt snapshot state. AC: fixture with
  a renamed stop across two snapshots yields two versions with correct,
  non-overlapping intervals; fact rows join to the version active on their
  service_date (point-in-time correctness test). The earliest version's
  valid_from is the sentinel 1900-01-01 — facts may predate the first
  snapshot's capture date.
- **FR-D3 metricflow_time_spine** model present and covering the data range.

### FR-M — Metrics & semantic layer
- **FR-M1 Definitions as SSOT**: semantic models + metrics in YAML for, at
  minimum: otp_rate, early_rate, late_rate, skip_rate, coverage_rate,
  observed_events, scheduled_events. Dimensions: service_date, route, day_type.
  AC: `mf validate-configs` passes in CI.
- **FR-M2 Parity marts**: each published metric is materialized in gold marts;
  a CI parity job compares `mf query` output vs mart output on fixtures with
  zero tolerance, at declared grains: route metrics at (service_date,
  route_short_name, day_type); system at (service_date) — both sides
  aggregated to the declared grain before comparison. AC: intentionally perturbing a mart formula fails CI.
  (If `mf query` on DuckDB proves unavailable — open item V-3 — fallback:
  parity against mf-compiled SQL; the YAML remains SSOT either way.)
- **FR-M3 No re-derivation, one sanctioned pattern**: the site queries marts
  only. Multi-day/window figures are computed exclusively as
  sum(numerator_count)/sum(denominator_count) over mart count columns —
  never by aggregating rate columns. Percentile metrics (median/p90) are
  daily-display-only and are never re-aggregated. AC: grep-level CI check
  permits only the sum/sum shape in `site/` SQL (CASES F-M05); any avg() or
  rate-column aggregation fails.
- **FR-M4 Minimum-sample threshold**: rankings exclude (route, period) cells
  below MIN_EVENTS (default 200 scheduled events); excluded cells are shown as
  "insufficient data", never omitted silently. AC: fixture route below
  threshold renders the insufficient-data state on the site and is absent from
  ranked tables.
- **FR-M5 Coverage adjacency**: every punctuality figure displayed on the site
  carries its coverage % within the same component. AC: visual check V-P5.

### FR-O — Observability (five pillars + source errors, native)
- **FR-O1 Freshness**: dbt source freshness on `_ingested_at`
  (warn 3h / error 12h at build time, per DR-011). AC: stale fixture triggers
  warn; nightly job surfaces freshness status into the quality mart.
- **FR-O2 Volume**: custom generic test `volume_within_seasonal_band` —
  today's scheduled and observed event counts vs trailing 28-day same-day_type
  band (config: ±%, default 30). Activation: per day_type, the test runs only once ≥4 prior same-day_type
  periods exist; before that it reports not_enough_history on the quality
  page instead of failing (CASES F-O05). AC: fixture with a 50% drop fails;
  normal weekday/weekend variance passes; cold-start reports, not fails.
- **FR-O3 Schema**: producer contracts (boundary) + dbt model contracts (core/
  marts) + CI `state:modified` guard requiring doc updates for contract changes.
  AC: adding a column to a contracted model without contract update fails CI.
- **FR-O4 Distribution**: dbt-expectations checks — delay_s within plausible
  bounds (config, default −1800..+7200s) on observed events; status within
  accepted set; null-rate ceilings on key FKs; `no_data` share per day ≤ config
  ceiling (default 40%) with floor alerting handled by FR-O2 style band.
  AC: fixture violations fail the respective tests.
- **FR-O5 Lineage**: `dbt docs generate` published (site or CI artifact) each
  nightly run. AC: docs artifact exists and includes the full DAG.
- **FR-O6 Source errors**: split by grain — `mart_quality__daily` (date
  grain: coverage, freshness status, volume-band status) and
  `mart_quality__feed_daily` (date × feed: quarantine counts + rate,
  unchanged share, poll success rate — all from the ledger and quarantine
  streams); a
  threshold test fails the build if quarantine rate > config (default 5%).
  AC: fixtures exercise pass and fail paths.

### FR-P — Product (Evidence site)
- **FR-P1 Bilingual**: parallel `/en` and `/fr` page trees sharing queries;
  language toggle preserving page context. Each page pair carries a matching content_revision front-matter value;
  CI fails on mismatched pairs (drift guard). AC: every published page exists
  in both languages; toggle round-trip returns to the same page; revision
  mismatch fails CI.
- **FR-P2 Pages**: Overview (system OTP, coverage, trend), Routes (ranked with
  FR-M4 handling), Route detail, Methodology (thresholds, taxonomy, coverage
  definition, OC Transpo's ~5% sensor caveat cited, service-date rules,
  **all-stops measurement policy per DR-025** — OTP at every scheduled stop,
  interpolated-times caveat, expected divergence from the agency's
  timepoint-based official OTP explained), Required visuals, all computable
  from existing marts: Overview = OTP + coverage dual trend (7/28/90d) +
  status-share stacked area + day_type comparison; Routes = ranked bar with
  coverage encoding + insufficient-data state; Route detail = OTP/coverage
  sparklines + status breakdown.
  Data Quality (FR-O6 mart: coverage trend, quarantine rate, freshness,
  volume-band status), About (attribution, non-affiliation disclaimer,
  license, repo link). AC: all pages render from marts with no build errors;
  methodology numbers match config vars (no hand-typed thresholds).
- **FR-P3 Deploy**: GHA deploys the built site to Cloudflare Pages after a
  green nightly build; failed builds leave the previous site live.
  AC: forced red build → site unchanged (verified once, V-P5).
- **FR-P4 Public staleness signal.** Every page footer shows "data through
  {latest complete service_date}"; if that date is older than
  STALE_BANNER_DAYS (default 3), a visible banner states the data is stale —
  the accountability site holds itself to its own transparency standard. The
  site also publishes `/data-status.json` {data_through, built_at} for the
  README status badge. AC: fixture build with old data renders the banner
  (CASES F-P01); JSON matches the footer; fresh build shows no banner.

### FR-CI — Pipeline hygiene
- **FR-CI1**: ruff + mypy(strict on ingestion/ops) + pytest + sqlfluff + dbt
  build on fixtures, all required on PR and main.
- **FR-CI2**: actions SHA-pinned with version comments; Dependabot for
  github-actions + pip + dbt packages.
- **FR-CI3**: no `${{ }}` interpolation inside `run:`; env indirection only;
  workflow-level `permissions: contents: read` (elevate per-job only where
  needed, e.g. Pages deploy). AC: grep-level CI check passes; manual review.
- **FR-CI4**: unit tests for FR-C1..C9 and ops scripts; dbt unit/singular tests
  for FR-W/FR-D/FR-M per their ACs. Coverage of `ingestion/` and `ops/` ≥ 85% lines each.
- **FR-CI5**: gitleaks secret scan on PR and main; `uv lock --check` so
  dependency drift fails loudly; the nightly build workflow authenticates
  with a **read-only** R2 token distinct from the collector's write token —
  the build never writes to R2. AC: gitleaks step present in CI and verified once locally against its own
  test corpus — never by committing bait secrets; a stale lockfile fails CI;
  nightly workflow references only the read-only token secret.

## 7. Edge cases (each maps to a fixture + AC above)
Same-second double poll (FR-C1); transient 5xx then success (FR-C2); permanent
outage window (FR-C2, FR-O1); identical consecutive payloads (FR-C5); unknown
enum (AC-5.2.1); missing position (AC-5.3.1); EN+FR translations (FR-C4);
oversized static zip (FR-C7); beta-URL 404 streak (FR-C8); SIGTERM mid-poll
(FR-C9); re-run bundler (FR-Y1); failed upload (FR-Y2); duplicate updates
(FR-W3); 25:30 stop_time (FR-W4a); DST fall-back (FR-W4b); calendar_dates
removal (FR-W4c); CANCELED trip (FR-W5); SKIPPED stop (FR-W5); ADDED trip
(§4, FR-W5); zero-coverage trip = all no_data (FR-W5); stop renamed across
schedule versions (FR-D2); route below sample threshold (FR-M4); quarantine
spike (FR-O6); volume drop (FR-O2).

## 8. Non-functional
- **Cost ceiling**: VPS ≈ €4/mo; everything else free tier. Any change → DR.
- **Latency SLO**: site data current through the last complete service day
  (DR-011); build finishes < 15 min (DR-021 revisit trigger).
- **Reproducibility**: same R2 state + same commit → same marts (FR-W1).
- **Security**: secrets only via env/GHA secrets; least-privilege tokens
  (R2 token scoped to bucket; Pages token scoped to project).
- **Volumetrics**: assumptions ~5–9k trips/day, ~250–400k scheduled stop-events
  /day, compressed landing ≤ ~300 MB/day — confirmed or corrected at V-P1
  checkpoint; spec updated with measured values.

## 9. Open verifications (block only their dependents)
- **V-1** ServiceAlerts feed form (GTFS-RT vs RSS) — owner: Ana. Blocks FR-C4
  scope only.
- **V-2** OC Transpo published OTP definition — owner: Ana/agent research.
  Blocks nothing (config default ships); updates §4 + methodology page.
- **V-3** `mf query` on DuckDB availability — owner: agent, P3 first task.
  Determines FR-M2 primary vs fallback path.
- **V-4** Evidence ↔ DuckDB version compatibility — owner: agent, P5 first task.
