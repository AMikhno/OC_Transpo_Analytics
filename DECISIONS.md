# DECISIONS.md — decision record trail

One line per settled decision (+context where a reviewer needs it). Newest
last. Open items at the bottom. Format: `DR-NNN: decision — rationale.`

## Founding (from architecture.md, restated for the record)
- **DR-001**: Product thesis = public accountability via honest measurement;
  clinical methodology over advocacy framing.
- **DR-002**: Status taxonomy on_time/early/late/skipped/no_data; a skip must
  be proven by a dispatch signal; missing telemetry is `no_data`, excluded
  from punctuality and reported separately as coverage.
- **DR-003**: TripUpdates is the timing backbone; VehiclePositions is
  enrichment only — protects metrics from sensorless-vehicle bias (~5% per
  OC Transpo's own published caveat).
- **DR-004**: Fact grain = one row per *scheduled* stop-event, observed or not
  — the structural basis for honest denominators.

## Capture & storage
- **DR-005**: Collector runs on a Hetzner ARM VPS (~€4/mo), independent of
  Databricks — Free Edition quota shutoff disqualifies Databricks-hosted
  capture for unrecoverable data.
- **DR-006**: Durable raw store = Cloudflare R2 — free tier, zero egress,
  first-class Unity Catalog external-location support (matters for v2).
  B2 rejected (not a UC credential type), S3 rejected (egress cost).
- **DR-007** (amended): Landing layout = hourly raw `tar.zst` bundles + hourly
  parsed/quarantine `.jsonl.gz`; static GTFS snapshot daily via cron with
  sha256 dedupe; everything synced to R2. Solves file-count explosion and
  keeps write ops far inside R2 free tier.
- **DR-008**: Host failure = gap, not loss (hourly verified sync). Dead-man
  alerting (healthchecks.io) is mandatory Phase-1 scope.
- **DR-009** (revised by DR-014): UC external location on Free Edition is
  community-confirmed, not documented — hands-on verification is a **v2 gate**
  item. Fallback: UC volume upload via SDK.
- **DR-012**: 30s poll cadence retained — matches OC Transpo's 30s GPS update
  rate. Content-hash dedupe + bounded backoff are API-citizenship requirements
  per OC Transpo developer terms (soft rate policy).

## Scope & staging
- **DR-010** (rev): Collector scope = minimum-durable fixes + bilingual
  capture + collector-side staleness counter; Bronze-derived numbers are
  authoritative for anything published; hardening batch (SHA pins, injection
  fix, quarantine contract) rides with Phase 0; Phase-3 geospatial parked;
  frontend is bilingual EN/FR as a product requirement.
- **DR-011**: Latency SLO = daily batch ("data as of yesterday"); hourly
  landing is buffer, not a freshness promise; source-freshness thresholds
  tuned to build time (warn 3h / error 12h).
- **DR-013**: Serving = Evidence bilingual static site over gold marts;
  Databricks Genie/AI-BI demoted to internal demo (v2). Driven by the EN/FR
  public requirement.
- **DR-014**: Architecture is staged. v1 = collector → R2 → dbt-duckdb
  (nightly GHA) → Evidence on Cloudflare Pages. v2 = documented migration to
  Databricks Free Edition (UC, Delta MERGE, COPY INTO, serverless SQL) with a
  portability diff as the headline portfolio artifact.
- **DR-015**: Auto Loader rejected — ~72 files/day makes file-notification
  infrastructure unjustified; `COPY INTO` in v2. Lakeflow out of scope.
- **DR-017**: The public product must never depend on Databricks availability;
  Free Edition is a contained v2 environment (also satisfies its
  non-commercial terms — external users only ever touch the static site).

## Quality & observability
- **DR-016** (rev2): Five-pillar observability (freshness, volume, schema,
  distribution, lineage) + source-error handling is a v1 requirement,
  implemented natively: dbt source freshness, custom seasonal volume-band
  test, producer + model contracts, dbt-expectations distribution checks,
  published dbt-docs lineage, quarantine-rate monitors. Elementary adopted in
  **v2** — it officially supports Databricks but not DuckDB (unofficial macro
  patches rejected as fragile). The v1→v2 tooling diff is documented.
- **DR-018**: Elementary OSS + `edr` static report only; Elementary Cloud out
  of scope. A public data-quality page ships in v1 on the site.
- **DR-020**: Great Expectations rejected — every job it could do is owned
  (Pydantic at the boundary, dbt tests in transform, Elementary for anomalies
  in v2); its assertion vocabulary adopted via the maintained
  metaplane/dbt-expectations package (>=0.10,<0.11; tz var America/Toronto).
  **Tool-admission rule**: a tool enters the stack only when it owns a job
  nothing else owns; JD keywords are satisfied by evaluated-and-rejected
  records like this one, not by installations.
- **DR-021**: v1 nightly build is a deterministic **full rebuild** from R2 —
  no dbt-snapshot runtime state; SCD2 dimensions are derived from the
  immutable static-GTFS snapshot archive, making the whole warehouse
  reproducible from history at any commit. Incremental (Delta MERGE +
  late-arriving lookback) is deliberately deferred to v2. Revisit trigger:
  nightly build > 15 minutes.

## Semantic layer
- **DR-023**: Semantic-layer design fixed in semantic-layer.md: all rates are
  MetricFlow `ratio` metrics (structurally enforces the no-average-of-averages
  rule); NULL semantics via native division, no COALESCE anywhere; surrogate
  `stop_event_key` added to fct_stop_event as the primary entity; SCD/point-
  in-time resolution stays in the model layer, semantic joins are key-only;
  presentation rules (MIN_EVENTS, rounding, windows) are excluded from the
  metric graph. Reference YAML drafted in legacy syntax pending V-6.

- **DR-026**: Adversarial doc review outcomes: (a) marts carry population
  counts; site window math is exclusively Σnum/Σden over counts; percentiles
  never re-aggregated; (b) a per-cycle poll ledger is a fourth landing stream
  and the Bronze source for feed-health metrics; (c) parity grains declared
  (route: service_date × route_short_name × day_type; system: service_date);
  (d) service_date fallback is deterministic-or-quarantine; (e) SCD earliest
  valid_from = 1900-01-01 sentinel; schedule expansion is snapshot-versioned;
  (f) volume test activates per day_type at ≥4 prior periods;
  (g) quality marts split by grain (daily vs feed-daily).

## Product & legal
- **DR-019**: Project is non-commercial and publicly served. Code license
  Apache-2.0; OC Transpo attribution per developer terms; a visible
  non-affiliation disclaimer is required on the site and README. (OC Transpo
  permits commercial and non-commercial use, so data terms do not constrain a
  future change — Databricks FE terms would.)
- **DR-025**: OTP is measured at **all scheduled stops**, not timepoints
  only — timepoint-only OTP structurally hides mid-route running-early/late,
  and running early at a minor stop is among the worst rider outcomes (a
  missed bus) yet invisible to timepoint measurement. Methodology must
  disclose: non-timepoint scheduled times may be agency-interpolated, and
  this OTP will legitimately diverge from OC Transpo's official
  timepoint-based figure — divergence explained, not discovered.
- **DR-022**: On-time thresholds are config vars (default −60s early / +300s
  late) published on the methodology page; pending V-2 verification against
  OC Transpo's own OTP definition for comparability.

## Open items
- **V-1**: ServiceAlerts feed form (GTFS-RT vs RSS) — Ana, 5-min portal check.
  Affects FR-C4 scope only.
- **V-2**: OC Transpo published OTP definition — research task; updates DR-022
  defaults if they differ.
- **V-3**: `mf query` support on DuckDB — agent spike, P3.1; decides FR-M2
  primary vs fallback parity path.
- **V-4**: Evidence ↔ DuckDB artifact version compatibility — agent spike, P5.1.
- **V-5**: Volumetrics — measured at V-P1 after 48h capture; spec §8 updated.
- **V-6**: MetricFlow syntax on DuckDB — legacy top-level spec vs embedded
  metrics spec (OSI v1.0): P3.1 spike adopts the newest that passes both
  `validate` and `query`; outcome recorded as DR-024 (semantic-layer.md §4).
- **V-7**: Check whether OC Transpo static GTFS uses frequencies.txt
  (frequency-based trips would change schedule expansion FR-W4) — one look at
  the snapshot zip; expected absent; record either way.
