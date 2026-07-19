# Makefile — command surface per CLAUDE.md §8.
# `check` is the definition-of-done gate (and the Stop-hook command).
# Targets guard for artifacts that later phases create, so `check` is
# meaningful from P0.1 onward without lying about what exists yet.

.PHONY: install check lint type test sql dbt-fixtures parity \
        collect-once collect-loop snapshot-static build site-dev obs-failcases

install:
	uv sync --all-groups

check: lint type test sql dbt-fixtures
	@echo "make check: ALL GREEN"

lint:
	uv run ruff format --check .
	uv run ruff check .

type:
	uv run mypy --strict ingestion
	@if [ -d ops ]; then uv run mypy --strict ops; fi

test:
	uv run pytest -q

sql:
	@if [ -f dbt/dbt_project.yml ]; then \
		uv run sqlfluff lint dbt/models; \
	else echo "sql: skipped (dbt project not created until P2.1)"; fi

dbt-fixtures:
	@if [ -f dbt/dbt_project.yml ]; then \
		uv run dbt build --project-dir dbt --profiles-dir dbt --target fixtures; \
	else echo "dbt-fixtures: skipped (dbt project not created until P2.1)"; fi

parity:
	@if [ -f ops/parity.py ]; then uv run python ops/parity.py; \
	else echo "parity: defined in P3.4"; exit 1; fi

# ---- collector (greenfield — built in P0, DR-035) ----
collect-once:
	uv run octranspo collect-once

collect-loop:
	uv run octranspo collect-loop --interval 30 --duration 600

snapshot-static:
	uv run octranspo snapshot-static

# ---- later-phase entry points (guarded stubs until their tasks land) ----
build:
	@if [ -f ops/build.sh ]; then bash ops/build.sh; \
	else echo "build: nightly pipeline script is created in P4.5 (see plan.md)"; exit 1; fi

site-dev:
	@if [ -f site/package.json ]; then cd site && npm run dev; \
	else echo "site-dev: Evidence project is created in P5.1 (see plan.md)"; exit 1; fi

obs-failcases:
	@if [ -f ops/obs_failcases.sh ]; then bash ops/obs_failcases.sh; \
	else echo "obs-failcases: defined in P4.1-P4.3"; exit 1; fi
