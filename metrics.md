# metrics.md — metric contract (SSOT in prose)

This document is the human-readable contract behind the MetricFlow YAML
(built in P3.2) and the methodology page (P5.3). If YAML, marts, or site ever
disagree with this file, this file wins and the others are bugs.
All metrics compute from `fct_stop_event` at the scheduled-stop-event grain.

## 1. Event populations (exact set algebra)

Let S = all scheduled stop-events for the cell (a cell = any combination of
the dimensions in §4, e.g. route × service_date).

- `timed`     = events with status ∈ {on_time, early, late}
- `skipped`   = events with status = skipped (proven only; DR-002)
- `no_data`   = events with status = no_data
- `observed`  = timed ∪ skipped            (we know what happened)
- S           = observed ∪ no_data          (partition; enforced by test)

Statuses are mutually exclusive and exhaustive — a dbt test asserts
|timed| + |skipped| + |no_data| = |S| for every cell.

## 2. Metric definitions

| metric | formula | denominator population | null rule |
|---|---|---|---|
| scheduled_events | count(S) | — | never null |
| observed_events | count(observed) | — | never null |
| coverage_rate | observed_events / scheduled_events | S | null iff S empty |
| otp_rate | count(on_time) / count(timed) | timed | **null iff timed = 0** |
| early_rate | count(early) / count(timed) | timed | null iff timed = 0 |
| late_rate | count(late) / count(timed) | timed | null iff timed = 0 |
| skip_rate | count(skipped) / count(observed) | observed | null iff observed = 0 |
| median_delay_s | median(delay_s) over timed | timed | null iff timed = 0 |
| p90_delay_s | percentile_cont(0.90)(delay_s) over timed | timed | null iff timed = 0 |

Rationale locked by DR-002/DR-004:
- Punctuality (otp/early/late, delay stats) is defined over **timed** events
  only — a skipped stop has no meaningful delay; a no_data stop has no
  information. Neither may appear in these denominators.
- skip_rate is over **observed**, not S: we can only attest a skip where we
  could observe at all. The methodology page states the corollary honestly:
  true skip incidence among no_data events is unknown.
- coverage_rate is always displayed adjacent to any punctuality figure
  (spec FR-M5). A cell may be 95% on-time with 40% coverage; both numbers
  are the claim.

## 3. Null and zero semantics (agents get this wrong — read twice)

- A rate whose denominator is 0 is **NULL**, never 0 and never 100%.
  NULL renders on the site as "no data", styled distinctly from 0%.
- delay_s is NULL for skipped and no_data events (enforced by test:
  status ∉ timed ⇒ delay_s IS NULL, and status ∈ timed ⇒ delay_s IS NOT NULL).
- ADDED trips are outside S entirely (spec §4); they appear only in
  `mart_quality__added_trips` counts.

## 4. Dimensions

service_date; route (point-in-time SCD2 version active on service_date,
per FR-D2); day_type (weekday | saturday | sunday_holiday, from dim_date;
statutory holidays classify as sunday_holiday — Ontario + City of Ottawa
observances, maintained as a seed); direction_id (route detail pages only).

## 5. Aggregation rule (the classic mistake, forbidden here)

Rates NEVER average across cells. System-level or multi-day rates recompute
from summed populations:

  otp_rate(system, week) = Σ on_time / Σ timed   — not avg(route otp_rates).

MetricFlow ratio metrics give this for free (numerator and denominator are
separate measures); the marts must implement the same way. A parity fixture
(one big route + one tiny route with opposite rates) exists specifically to
catch average-of-averages: CASES.md F-M01.

## 6. Publication rules

- **Min-sample (FR-M4, DR-022 family):** ranked displays exclude cells with
  scheduled_events < MIN_EVENTS (default 200); excluded cells render as
  "insufficient data", never silently dropped.
- **Threshold disclosure:** OTP_EARLY_S / OTP_LATE_S values (defaults 60/300;
  V-2 may revise) are printed on the methodology page from config — never
  hand-typed into prose.
- **Trend windows:** default site windows are last 7 / 28 / 90 complete
  service days; a "complete" day = service_date < today's service_date.
- **Rounding:** rates display at 0.1 pp; delay stats at whole seconds.
  Marts store full precision; rounding is presentation-only.
- **Window aggregation (the only sanctioned site-side arithmetic):**
  multi-day rates = Σ numerator_count / Σ denominator_count over mart count
  columns (§5 applies at every layer). Rate columns are never averaged or
  summed. Percentile metrics are daily-display-only — a median of daily
  medians is meaningless and is forbidden (CASES F-M05).

## 7. Worked example (doubles as fixture F-M02)

Route 6, one service_date: S = 100 scheduled stop-events.
timed = 80 (60 on_time, 8 early, 12 late), skipped = 5, no_data = 15.

- coverage_rate = 85/100 = 85.0%
- otp_rate = 60/80 = 75.0% · early_rate = 10.0% · late_rate = 15.0%
- skip_rate = 5/85 ≈ 5.9%
- Site renders: "75.0% on time (coverage 85.0%)".

Any implementation that produces 60/100, 60/85, or 5/100 for these values is
wrong, regardless of how plausible the code looks.

## 8. Metric → mart → page map

| metric | mart | site pages |
|---|---|---|
| population counts (scheduled/observed/timed/on_time/early/late/skipped) + daily rates + daily median/p90, by route×day | mart_reliability__route_daily | Routes, Route detail |
| same, system×day | mart_reliability__system_daily | Overview |
| coverage, freshness status, volume-band status | mart_quality__daily | Data Quality |
| quarantine rate, unchanged share, poll success (per feed, from ledger) | mart_quality__feed_daily | Data Quality |
| ADDED counts | mart_quality__added_trips | Data Quality |
