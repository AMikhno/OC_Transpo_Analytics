# fixtures/CASES.md — fixture catalog & answer key

Written BEFORE implementation (CLAUDE.md §7). The fixture builder (P0.1)
generates binary/static inputs from this table; tests assert the expected
column exactly. If an implementation disagrees with this file, the
implementation is wrong OR this file gets a reviewed correction commit —
never a silent test edit (guardrail 8).

## Conventions (fixed for all fixtures)
- Timezone: America/Toronto. Thresholds at defaults: OTP_EARLY_S=60,
  OTP_LATE_S=300. MIN_EVENTS=200 unless a case says otherwise.
- Synthetic network: route `F1` (and `F2` where needed), trips `T01…`,
  stops `S1…S5` with stop_sequence 1…5.
- Base service_date `2026-06-15` (Monday, no DST anywhere near).
- "TU(t, Δ)" = a TripUpdates record with feed_timestamp t containing
  arrival = scheduled + Δ seconds. Δ ranges below are exact, not illustrative.
- Every classification case also asserts: delay_s NULL ⟺ status ∉ timed.

## A. Classification answer key (spec FR-W5; model int_stop_events__classified)

| ID | Setup (service_date 2026-06-15 unless noted) | Expected status | Expected delay_s |
|---|---|---|---|
| C01 | T01/S1 sched 08:00:00; TU(08:00:05, +0) | on_time | 0 |
| C02 | T01/S2 sched 08:05:00; TU(…, −60) | on_time | −60 |
| C03 | T01/S3 sched 08:10:00; TU(…, −61) | early | −61 |
| C04 | T01/S4 sched 08:15:00; TU(…, +300) | on_time | +300 |
| C05 | T01/S5 sched 08:20:00; TU(…, +301) | late | +301 |
| C06 | T02 (5 stops) trip-level schedule_relationship=CANCELED | skipped ×5 | NULL ×5 |
| C07 | T03/S3 stop-level SKIPPED; S1,S2,S4,S5 have TU(+30) | S3 skipped; others on_time | S3 NULL; others +30 |
| C08 | T04 (5 stops): zero TU records reference the trip | no_data ×5 | NULL ×5 |
| C09 | T05/S1 sched 09:00:00; TU(t1,+400), TU(t2,+200), TU(t3,+100), t1<t2<t3 | on_time (last word wins) | +100 |
| C09b | T05/S2: two TU with equal feed_timestamp, _ingested_at a<b, Δ=+400 then +100 | on_time (tie → later _ingested_at) | +100 |
| C10 | T06/S1 stop_time **25:15:00** on service_date 2026-06-15; TU(start_date=20260615, +120) | on_time; row's service_date = 2026-06-15; scheduled epoch = 2026-06-16T05:15:00Z (01:15 EDT next calendar day) | +120 |
| C11 | **Fall-back day** service_date 2026-11-01: T07/S1 stop_time 08:00:00; TU(+120) | on_time; scheduled epoch = 2026-11-01T**13:00:00Z** (noon−12h anchor = 05:00Z; +8h) | +120 |
| C11b | Same day: T07/S2 stop_time 01:30:00; TU(+0) | on_time; scheduled epoch = 2026-11-01T**06:30:00Z** (anchor 05:00Z + 1.5h — naive local-midnight parsing yields 05:30Z and a spurious −3600 error; that is the bug this case exists to catch) | 0 |
| C12 | T08: TU covers S1–S3 (+30 each); S4,S5 absent from every message | S1–S3 on_time; S4,S5 no_data | +30/+30/+30/NULL/NULL |
| C15 | TU record with no start_date; trip's calendar inactive on both {today, yesterday} candidates | quarantined upstream with type=service_date_unresolved; never reaches classification | — |
| C13 | T99 with schedule_relationship=ADDED, no static baseline; TU present | absent from fct_stop_event; counted once in mart_quality__added_trips | — |
| C14 | Partition check over C01–C12 population | \|timed\|+\|skipped\|+\|no_data\| = \|S\| exactly | — |

Note: unknown-enum input never reaches this model — it is quarantined at the
collector (F-C03 below); a staging test asserts the classified model's input
contains only known relationships.

## B. Collector cases (spec FR-C*, §5.2–5.3)

| ID | Setup | Expected |
|---|---|---|
| F-C01 | Two raw writes, same feed, same second | 2 distinct files; 0 overwrites; both readable |
| F-C02 | Endpoint mock: fail, fail, succeed (then: always-fail) | cycle succeeds, 2 retries logged; always-fail → failed-poll recorded, next cycle on schedule |
| F-C03 | Entity with schedule_relationship="SOMETHING_NEW" | parsed: absent; quarantine: 1 record, errors[0].type="unknown_enum" |
| F-C04 | VehiclePositions entity lacking `position` | quarantine record, errors=[{loc:["position"],msg:"missing position",type:"missing_field"}] |
| F-C05 | Alert/text field with translations [en:"Detour", fr:"Détour"] | parsed record holds {"en":"Detour","fr":"Détour"}; nothing dropped |
| F-C06 | Identical payload polled twice | raw archives both; parsed stored once; two ledger rows, second with unchanged=true |
| F-C07 | Static URL serving 250 MB (cap 200) | abort with clear error; no partial file on disk |
| F-C08 | 10 consecutive mocked 404s; then 200 | exactly one endpoint-alert ping at streak=10; recovery resets state (no second ping) |
| F-C09 | SIGTERM mid-poll during collect-loop | in-flight poll completes; exit code 0; no .tmp files remain |
| F-C10 | One cycle: TripUpdates OK, VehiclePositions times out (retries exhausted) | ledger lands one row per enabled feed: TU outcome=ok, VP outcome=failed with retries=3; parsed only for TU |
| F-C11 | Endpoint returns 200 with an undecodable body (HTML page) | raw archives the verbatim body (AC-5.2.4); one quarantine record errors[0].type="decode_failed"; ledger row outcome=decode_failed; parsed absent |
| F-C12 | Feed serves identical payload (frozen header) for STALE_FEED_ALERT_S | exactly one stale_feed fail-ping naming the feed; recovery resets state (no second ping) |

## C. Ops cases (spec FR-Y*)

| ID | Setup | Expected |
|---|---|---|
| F-Y01 | Run bundler twice on the same closed hour | second run exit 0; object count unchanged; identical checksums |
| F-Y02 | Sync with R2_BUCKET=nonexistent | non-zero exit; zero local files pruned |
| F-Y03 | Sync OK, hour age < RETENTION_DAYS | uploaded + checked; NOT pruned |
| F-Y04 | Sync OK, hour age ≥ RETENTION_DAYS | pruned locally; present in R2 |
| F-Y05 | VehiclePositions mocked to fail 12 consecutive cycles; TripUpdates healthy | dead-man stays green (FR-Y3); FR-C8 fail-ping fires once at streak 10 on octranspo-feeds naming vehicle_positions; TripUpdates data unaffected |
| F-Y06 | kill -9 the bundler mid-bundle; rerun | no final-path partial visible, or rerun detects manifest mismatch and rebuilds; final bundle checksum equals a clean-run bundle's |
| F-Y07 | Truncated bundle planted at final path, no/stale manifest; run bundler | hour is rebuilt from per-poll sources; manifest matches rebuilt bundle; `zstd -t` passes |
| F-Y08 | Per-poll files staged for 3 non-contiguous past hours; one bundler run | 3 bundles produced, oldest first; each manifest member_count = that hour's per-poll count |
| F-Y09 | Closed hour with zero per-poll records (quiet feed) | zero-count manifest produced; hour is never "absent"; sync uploads it |

## D. Dimensional cases (spec FR-D2)

| ID | Setup | Expected |
|---|---|---|
| F-D01 | Snapshot A (2026-06-01): stop S2 name "Bank / Somerset"; Snapshot B (2026-06-20): renamed "Bank / Gladstone" | dim_stop has 2 versions: [06-01, 06-20) and [06-20, null); is_current on v2 only; no overlap, no gap |
| F-D02 | Fact row on 2026-06-15 for S2 | joins to version 1 attributes ("…Somerset") — point-in-time, not is_current |
| F-D03 | calendar_dates removes service 2026-07-01 for T01's service_id | int_schedule__stop_events emits 0 events for T01 that day |
| F-D04 | Snapshot A shifts T01/S1 from 08:00 to 08:10 effective snapshot B (2026-06-20) | service_dates < 06-20 expand from A's stop_times (08:00); ≥ 06-20 from B's (08:10) |

## E. Metric cases (metrics.md §5/§7)

| ID | Setup | Expected |
|---|---|---|
| F-M01 | Route A: 1,000 timed, 900 on_time (90%). Route B: 10 timed, 1 on_time (10%) | system otp_rate = 901/1010 ≈ **89.2%**, not (90+10)/2 = 50% |
| F-M02 | metrics.md §7 population (S=100; 60/8/12/5/15) | coverage 85.0%, otp 75.0%, early 10.0%, late 15.0%, skip ≈5.9% |
| F-M03 | Cell with timed=0, skipped=2, no_data=3 | otp/early/late/median/p90 all NULL; coverage 40%; skip_rate 100% |
| F-M04 | Route with scheduled_events=150 (< MIN_EVENTS) | absent from rankings; renders "insufficient data" state |
| F-M05 | 7-day window: day1 timed=1000/on_time=900, day2 timed=10/on_time=1 | window otp = 901/1010 ≈ 89.2% via count sums; avg of daily rates (50%) is the forbidden result; median never window-aggregated |

## F. Observability cases (spec FR-O*)

| ID | Setup | Expected |
|---|---|---|
| F-O01 | Weekday with scheduled_events at 50% of trailing 28-day weekday mean | volume_within_seasonal_band FAILS for that date; adjacent normal days pass |
| F-O02 | One day with quarantine_rate = 8% (ceiling 5%) | quarantine threshold test fails; other days pass |
| F-O03 | Newest _ingested_at 13h old at build | source freshness = error (warn 3h / error 12h) |
| F-O04 | delay_s = +9000 injected on a timed row | dbt-expectations bounds test fails naming the row's model |
| F-O05 | Fixture history with only 2 prior saturdays | volume test reports not_enough_history for saturday day_type on the quality page; build stays green; weekday (≥4 periods) still enforced |

## G. Parity & determinism (spec FR-M2, FR-W1)

| ID | Setup | Expected |
|---|---|---|
| F-G01 | `make parity` on fixtures | every metric: mf value = mart value, zero tolerance |
| F-G02 | Apply docs/perturb_mart.patch (changes otp_rate denominator to observed) | parity FAILS naming otp_rate |
| F-G03 | Two consecutive `make build` on frozen fixture R2 state | identical metric values; diff script prints OK |

## H. Product cases (spec FR-P4)

| ID | Setup | Expected |
|---|---|---|
| F-P01 | Site built from fixture marts whose latest complete service_date is 5 days old (STALE_BANNER_DAYS=3) | footer shows "data through <date>"; staleness banner rendered on every page; /data-status.json data_through matches footer |
| F-P02 | Same build with yesterday's data | no banner; JSON matches footer |

## Maintenance rules
- New edge case discovered in real data → new row here + fixture + test, in
  that order, one commit.
- Corrections to Expected require a DR line (what was wrong, why, evidence).
