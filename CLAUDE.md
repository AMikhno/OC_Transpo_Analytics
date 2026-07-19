# CLAUDE.md — OC Transpo Reliability Tracker (v1)

Agent constitution. Read fully before any task. If an instruction here conflicts
with a prompt, STOP and ask. This file + `spec.md` + `plan.md` + `validation.md`
+ `DECISIONS.md` are the complete source of truth; the conversation is not.

Note for planning sessions (plan mode / opusplan): the 2026-07 capture-layer
red-team audit is fully folded into these documents as DR-027..DR-035 and the
corresponding spec/RUNBOOK/CASES amendments. Plan from the **updated docs
only** — do not read or re-derive from the original audit report; where the
report and the committed docs differ, the docs win.

## 1. Project identity

Public, bilingual (EN/FR), non-commercial accountability site measuring OC Transpo
service reliability from self-collected GTFS-RT data. Credibility comes from
published methodology and honest denominators, not advocacy. Portfolio priorities,
in order: (1) dbt + semantic layer, (2) dimensional modeling, (3) production
credibility. v1 deliberately excludes Databricks (see DECISIONS.md DR-014).

## 2. Stack (fixed — do not add, swap, or "upgrade" anything)

| Layer | Tool | Notes |
|---|---|---|
| Collector | Python 3.12, uv, httpx, Pydantic v2, Typer | greenfield `ingestion/` package (DR-035) |
| Raw store | Local disk → Cloudflare R2 via rclone | layout per spec §5.4 |
| Warehouse | DuckDB via dbt-duckdb (dbt Core, latest 1.x) | nightly full rebuild |
| Transform | dbt + dbt-utils + dbt-expectations (metaplane fork, >=0.10,<0.11) | tz var `America/Toronto` |
| Metrics | MetricFlow (`dbt-metricflow[duckdb]`) | definitions = SSOT; marts materialize |
| Site | Evidence (Node.js LTS) → Cloudflare Pages | EN + FR page trees |
| Scheduling | systemd timers (VPS), GitHub Actions (nightly build) | |
| Alerting | healthchecks.io pings | dead-man switch |
| CI | ruff, mypy, pytest, sqlfluff, gitleaks, `uv lock --check`, dbt build on fixtures | GHA, SHA-pinned actions |

Explicitly NOT in v1 (do not install, scaffold, or reference in code): Databricks,
Unity Catalog, Delta, Auto Loader, Lakeflow, Elementary, Great Expectations,
Airflow/Dagster/Prefect, Docker (VPS runs bare systemd), any paid service.

## 3. Repository layout

```
ingestion/            # collector package (greenfield — DR-035)
ops/                  # NEW: bundler, rclone sync, systemd units, healthcheck ping
dbt/                  # dbt project: models/{staging,intermediate,core,marts}
  models/semantic/    # MetricFlow semantic models + metrics YAML
  tests/              # singular + generic custom tests
  seeds/              # small static seeds (e.g., holiday calendar)
fixtures/             # deterministic fixture feeds + expected-answer seeds
site/                 # Evidence project (en/ and fr/ page trees)
tests/                # Python unit tests for ingestion + ops
.github/workflows/    # ci.yml, nightly.yml, deploy.yml
docs/                 # methodology source-of-truth (published to site)
```

## 4. Conventions

- **Python**: uv-managed; type hints everywhere; `mypy --strict` on `ingestion/`
  and `ops/`; ruff for lint+format; no bare `except`; log with `logging`, never
  `print` (CLI user output via Typer echo is fine).
- **dbt naming**: `stg_<source>__<entity>`, `int_<entity>__<verb>`,
  `dim_<entity>`, `fct_<event>`, `mart_<consumer>__<subject>`. One model per
  file. Every model has a YAML block with description + column docs + tests.
- **SQL style**: sqlfluff (dbt templater) clean; CTE-first; no `select *`
  outside staging; all timestamps stored as UTC epoch or TIMESTAMPTZ-UTC;
  local time only at presentation edges via `America/Toronto`.
- **Contracts**: marts and core models use dbt model contracts (enforced).
- **Commits**: one plan.md task per commit, message `P<phase>.<task>: <summary>`.
  Never combine tasks. Never commit failing tests.
- **Config**: all tunables (thresholds, cadences, URLs, paths) via env or
  `dbt_project.yml` vars — never hardcoded literals in logic.

## 5. Guardrails — the agent must NEVER:

1. Mark an unobserved stop-event as `skipped`. Skips must be proven
   (dispatch-driven signal). Missing telemetry is `no_data`, always.
2. Write non-atomically to `data/raw/` or overwrite an existing raw file.
   Raw is immutable, append-only, collision-safe.
3. Delete or prune any local data unless the R2 upload of that data has been
   verified (rclone check) AND retention age has passed.
4. Fold `no_data` events into punctuality denominators, or publish a ranking
   without the minimum-sample threshold (spec FR-M4).
5. Add a dependency, tool, or service not listed in §2. If one seems needed,
   STOP, write a one-line proposal, and wait for approval (DR-020 rule).
6. Touch Databricks, or write code that imports/depends on it (v2 only).
7. Interpolate untrusted or user-supplied values into GHA `run:` blocks;
   always route through `env:` indirection.
8. Weaken, skip, or delete a failing test to make a task "pass". Fix the code
   or STOP and report the conflict between spec and reality.
9. Hardcode secrets, tokens, or API keys anywhere, including tests and fixtures.
10. Publish text on the site implying affiliation with OC Transpo, or drop the
    attribution + non-affiliation disclaimer (DR-019).
11. Silently reinterpret spec ambiguity. Ambiguity → STOP, ask, and the answer
    becomes a new DR line in DECISIONS.md.
12. Use wall-clock local time for duration math. All arithmetic on epoch
    seconds; `America/Toronto` for display and service-date derivation only.

## 6. Definition of done (every task)

A task is done only when: (a) code + tests written; (b) `make check` passes
(ruff, mypy, pytest, sqlfluff, dbt build on fixtures as applicable); (c) the
runnable state named in plan.md for that task is demonstrated by a command with
observable output; (d) committed as one commit. If any of (a)–(d) is impossible,
STOP and report — do not approximate.

## 7. Fixture-first rule for logic

Any model or function implementing classification, service-date derivation,
dedup, or metric math must be written against `fixtures/` cases with known
expected answers BEFORE running on real data. Fixtures are part of the repo and
CI. Real-data runs are validation, never the first test.

## 8. Commands

```
make install        # uv sync --all-groups
make check          # ruff + mypy + pytest + sqlfluff + dbt build --target fixtures
make collect-once   # single poll (dev)
make build          # nightly pipeline locally: fetch R2 → dbt build → evidence build
make site-dev       # evidence dev server
```
