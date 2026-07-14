# semantic-layer.md — MetricFlow design specification

Bridges metrics.md (the contract) to the semantic YAML (built in P3.2).
metrics.md defines WHAT each number means; this file defines HOW that becomes
MetricFlow objects, and which design choices are fixed vs. decided by the
P3.1 spike. The YAML in §7 is a reviewed reference draft, not final code:
P3.2 adapts it to whatever syntax the spike ratifies, changing structure
only with a DR.

## 1. Design decisions (fixed)

**D1 — Rates are `ratio` metrics, without exception.** MetricFlow ratio
metrics recompute numerator and denominator at whatever grain is queried,
which *structurally* enforces metrics.md §5 (no average-of-averages;
fixture F-M01). This is the governance argument for having a semantic layer
at all: the aggregation rule stops being a convention and becomes a property
of the metric type. Any rate implemented as a `derived` or pre-divided
column is a spec violation.

**D2 — NULL semantics ride on native division.** A ratio with a zero
denominator yields NULL, which is exactly metrics.md §3. Therefore:
no COALESCE, IFNULL, or zero-defaulting anywhere in measures, metrics, or
the marts that materialize them. (Agent guardrail; parity fixture F-M03
enforces it.)

**D3 — Surrogate primary entity.** MetricFlow semantic models need a primary
entity; fct_stop_event's natural key is composite. The fact therefore gains
`stop_event_key` = `dbt_utils.generate_surrogate_key(['service_date',
'trip_id','stop_sequence'])` (VARCHAR). architecture.md §5 updated; the
natural-key uniqueness test remains authoritative, the surrogate gets its
own uniqueness test.

**D4 — Status flags live in measure `expr`s, not extra fact columns.**
Measures like `on_time_events` use `case when status = 'on_time' then 1 else
0 end` (sum). Keeps the fact lean; the population algebra of metrics.md §1
is visible in one YAML screen, which is where a reviewer will look.

**D5 — Point-in-time correctness stays in the model layer.** fct_stop_event
already carries the SCD2-resolved route_key/stop_key for the event's
service_date (FR-D2). Semantic-layer joins are therefore plain key joins;
MetricFlow never re-implements SCD logic. Consequence: dimension values from
`routes` are historically accurate by construction.

**D6 — Time.** `service_date` is the fact's `agg_time_dimension` (day
grain). `metricflow_time_spine` (already in the schema) backs cumulative/
offset capabilities; v1 publishes no cumulative metrics, but the spine is
mandatory infrastructure.

**D7 — Scope.** Semantic models: `stop_events` (fact), `routes`, `dates`
(dimension models). `dim_stop` is not in the semantic graph in v1 — no
published metric slices by stop. Adding it later is additive.

## 2. Contract → object map

| metrics.md | MetricFlow object |
|---|---|
| populations §1 (S, timed, observed…) | measures on `stop_events` (D4 exprs) |
| coverage_rate, otp_rate, early_rate, late_rate, skip_rate | `ratio` metrics (D1) |
| scheduled_events, observed_events | `simple` metrics over sum measures |
| median_delay_s, p90_delay_s | `simple` metrics over `percentile` measures (0.5 / 0.9, continuous), expr restricted to timed rows |
| dimensions §4 | `service_date` (time, on fact) · `day_type`, `is_holiday` (via `date_day` entity → `dates`) · route names (via `route` entity → `routes`) · `direction_id` (categorical on fact) |
| aggregation rule §5 | ratio metric type (D1) |
| null rules §3 | native division + no-coalesce rule (D2) |
| publication rules §6 (MIN_EVENTS, rounding, windows) | NOT semantic-layer concerns — marts/site apply them; the semantic layer stays presentation-free |

## 3. Parity mechanics (binds to spec FR-M2, fixtures F-G01/02)

For every metric × grain the site uses: `mf query` (or saved-query
execution) on fixtures must equal the mart's value, zero tolerance. Declared parity grains: route metrics at (service_date, route_short_name,
day_type); system at (service_date); both sides aggregate to the declared
grain before compare — the mart's route_key grain is finer and rolls up.
Documented property: a mid-window route_short_name change splits the series
(rare; it is the route number). The mart SQL is written by the agent but is
*derivative*; when parity fails, the YAML wins and the mart is the bug
(metrics.md header rule). The perturb
patch (F-G02) proves the harness can fail.

## 4. Syntax decision — open item V-6, resolved by spike P3.1

Two live syntaxes: the **legacy top-level spec** (`semantic_models:` /
`metrics:` files — the stable path for OSS MetricFlow) and the **embedded
metrics spec** (semantic annotations inside model YAML — the OSI v1.0 /
Fusion-era direction). The spike tests, on DuckDB, in order: (1) legacy
syntax: `mf validate-configs` + `mf query` both pass? (2) embedded spec:
does the installed toolchain parse *and* query it? Adopt the newest syntax
that passes **both** validate and query; record DR-024 with the outcome.
§7's draft uses legacy syntax because it is the conservative baseline; a
syntax port changes packaging, not the object design above.

## 5. Naming (stable API — site and methodology reference these)

Metric names are public identifiers: `coverage_rate`, `otp_rate`,
`early_rate`, `late_rate`, `skip_rate`, `scheduled_events`,
`observed_events`, `median_delay_s`, `p90_delay_s`. Renames require a DR +
site/methodology sweep in the same commit.

## 6. Agent guardrails (additive to CLAUDE.md §5)

- No COALESCE/IFNULL on any measure, metric, or mart rate column (D2).
- No `derived` metric that re-implements a ratio (D1).
- No metric math in marts beyond materializing these definitions (FR-M3).
- No semantic-layer knowledge of MIN_EVENTS, rounding, or display windows
  (§2 last row) — presentation stays out of the metric graph.
- Measure exprs must match metrics.md §1 population algebra verbatim in
  effect; F-M02's worked example is the acceptance oracle.
- Percentile measures/metrics are never re-aggregated across days; window
  rates only via count sums (metrics.md §6). Site and marts inherit this.

## 7. Reference YAML draft (legacy syntax; P3.1 ratifies, P3.2 finalizes)

```yaml
semantic_models:
  - name: stop_events
    description: One row per scheduled stop-event (DR-004). Fact of record.
    model: ref('fct_stop_event')
    defaults:
      agg_time_dimension: service_date
    entities:
      - { name: stop_event, type: primary, expr: stop_event_key }
      - { name: route,      type: foreign, expr: route_key }
      - { name: date_day,   type: foreign, expr: date_key }
    dimensions:
      - name: service_date
        type: time
        type_params: { time_granularity: day }
      - { name: status,       type: categorical }
      - { name: direction_id, type: categorical }
    measures:
      - { name: scheduled_events, agg: sum, expr: "1" }
      - name: observed_events
        agg: sum
        expr: "case when status <> 'no_data' then 1 else 0 end"
      - name: timed_events
        agg: sum
        expr: "case when status in ('on_time','early','late') then 1 else 0 end"
      - name: on_time_events
        agg: sum
        expr: "case when status = 'on_time' then 1 else 0 end"
      - name: early_events
        agg: sum
        expr: "case when status = 'early' then 1 else 0 end"
      - name: late_events
        agg: sum
        expr: "case when status = 'late' then 1 else 0 end"
      - name: skipped_events
        agg: sum
        expr: "case when status = 'skipped' then 1 else 0 end"
      - name: delay_s_median
        agg: percentile
        agg_params: { percentile: 0.5, use_discrete_percentile: false }
        expr: "case when status in ('on_time','early','late') then delay_s end"
      - name: delay_s_p90
        agg: percentile
        agg_params: { percentile: 0.9, use_discrete_percentile: false }
        expr: "case when status in ('on_time','early','late') then delay_s end"

  - name: dates
    model: ref('dim_date')
    entities:
      - { name: date_day, type: primary, expr: date_key }
    dimensions:
      - { name: day_type,   type: categorical }
      - { name: is_holiday, type: categorical }

  - name: routes
    model: ref('dim_route')
    entities:
      - { name: route, type: primary, expr: route_key }
    dimensions:
      - { name: route_short_name, type: categorical }
      - { name: route_long_name,  type: categorical }

metrics:
  - { name: scheduled_events, type: simple, label: Scheduled stop-events,
      type_params: { measure: scheduled_events } }
  - { name: observed_events,  type: simple, label: Observed stop-events,
      type_params: { measure: observed_events } }
  - name: coverage_rate
    type: ratio
    label: Coverage
    type_params: { numerator: observed_events, denominator: scheduled_events }
  - name: otp_rate
    type: ratio
    label: On-time performance
    type_params: { numerator: on_time_events, denominator: timed_events }
  - name: early_rate
    type: ratio
    label: Early rate
    type_params: { numerator: early_events, denominator: timed_events }
  - name: late_rate
    type: ratio
    label: Late rate
    type_params: { numerator: late_events, denominator: timed_events }
  - name: skip_rate
    type: ratio
    label: Skip rate (of observed)
    type_params: { numerator: skipped_events, denominator: observed_events }
  - { name: median_delay_s, type: simple, label: Median delay (s),
      type_params: { measure: delay_s_median } }
  - { name: p90_delay_s, type: simple, label: P90 delay (s),
      type_params: { measure: delay_s_p90 } }

saved_queries:
  - name: reliability_route_daily
    description: Backs mart_reliability__route_daily (parity target).
    query_params:
      metrics: [scheduled_events, observed_events, coverage_rate, otp_rate,
                early_rate, late_rate, skip_rate, median_delay_s, p90_delay_s]
      group_by:
        - TimeDimension('stop_event__service_date', 'day')
        - Dimension('route__route_short_name')
        - Dimension('date_day__day_type')
  - name: reliability_system_daily
    description: Backs mart_reliability__system_daily (parity target).
    query_params:
      metrics: [scheduled_events, observed_events, coverage_rate, otp_rate,
                early_rate, late_rate, skip_rate, median_delay_s, p90_delay_s]
      group_by:
        - TimeDimension('stop_event__service_date', 'day')
```

Review focus for Ana (5 minutes, no tooling): do the measure exprs implement
metrics.md §1 exactly, and do the ratio numerator/denominator pairs match
§2's table? Those two checks are the entire business-logic surface of this
file.
