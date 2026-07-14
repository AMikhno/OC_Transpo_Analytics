# OC Transpo Reliability Tracker

Independent, bilingual (EN/FR) measurement of OC Transpo service reliability,
built on self-collected GTFS-RT and static GTFS data — with honest
denominators: **a skip must be proven, and missing telemetry is never counted
as bad service.** OC Transpo itself reports ~5% vehicle-position gaps; this
project's core design decision is refusing to let that 5% contaminate the
numbers. Unobserved events are a third state (`no_data`), excluded from
punctuality and published separately as coverage.

> **Not affiliated with OC Transpo or the City of Ottawa.** Data ©
> OC Transpo / City of Ottawa, used with attribution under their developer
> terms. Code: Apache-2.0. Non-commercial project.

## Status

| stage | scope | state |
|---|---|---|
| **v0 — capture** | hardened collector on a VPS → Cloudflare R2, hourly durable sync, dead-man alerting | in progress (plan.md P0–P1) |
| **v1 — product** | nightly dbt/DuckDB rebuild → star schema → MetricFlow-defined metrics → bilingual Evidence site + public data-quality page | specified, next |
| **v2 — migration** | documented port of the same dbt project to Databricks (UC, Delta, COPY INTO, Elementary) — the portability diff is the artifact | designed, deferred |

Realtime history is unrecoverable — the feed overwrites itself every ~30
seconds and nobody archives it — so capture (v0) runs before and independent
of everything else.

## Documentation map

| file | what it governs |
|---|---|
| [spec.md](spec.md) | requirements with acceptance criteria (normative) |
| [plan.md](plan.md) | phased build; one task = one commit = one runnable state |
| [validation.md](validation.md) | how correctness is verified **without reading code** |
| [CLAUDE.md](CLAUDE.md) | agent constitution: stack, conventions, guardrails |
| [metrics.md](metrics.md) | metric contract — formulas, denominators, null rules |
| [fixtures/CASES.md](fixtures/CASES.md) | the answer key every logic test asserts against |
| [architecture.md](architecture.md) | staged design, star schema, config reference |
| [RUNBOOK.md](RUNBOOK.md) | operations: setup, drills, incident playbook |
| [DECISIONS.md](DECISIONS.md) | every settled decision, including rejected tools |

`BUILD_PLAN.md` is superseded by plan.md + DECISIONS.md (DR-014).

## Quickstart (collector, dev)

Requires [uv](https://docs.astral.sh/uv/) and Python 3.12+.

```bash
uv sync --all-groups
cp .env.example .env && $EDITOR .env    # OCTRANSPO_API_KEY
uv run octranspo collect-once           # one poll of every feed → ./data
uv run octranspo collect-loop --interval 30 --duration 600
uv run octranspo snapshot-static
make check                              # ruff + mypy + pytest + sqlfluff (+ dbt on fixtures)
```

Production capture runs on a small VPS with systemd timers and verified
hourly sync to R2 — see RUNBOOK.md. `data/` is gitignored; raw archives are
the unrecoverable part and live in R2.

## How the numbers work (short version)

One fact row per *scheduled* stop-event. TripUpdates is the timing backbone
(dispatch-driven, immune to GPS gaps); VehiclePositions only ever enriches.
Status ∈ {on_time, early, late, skipped, no_data}; punctuality rates are
computed over timed events only, skip rate over observed events, and coverage
is displayed beside every figure. Thresholds and all tunables are config,
printed on the methodology page from the same variables the models use.
Full contract: metrics.md.

## License & attribution

Code Apache-2.0 (LICENSE). GTFS/GTFS-RT data provided by OC Transpo / City
of Ottawa via their developer program; this project is an independent,
unofficial analysis and makes no claim of endorsement.
