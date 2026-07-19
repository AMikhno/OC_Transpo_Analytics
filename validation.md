# validation.md — how Ana verifies without reading code

Principles: behavior checks + numbers checked by hand + fresh-agent audits.
The building agent never grades itself. Every checkpoint below is a gate:
red = the phase is not done, regardless of green CI.

Conventions: `$ command` = run it; **Expect:** = observable outcome. Anything
requiring judgment is marked ⚖ with the exact question to answer.

---

## V-P0 — Collector hardening

1. `$ make check` → **Expect:** all green (ruff, mypy, pytest, sqlfluff).
2. `$ uv run pytest -k "atomic or retry or quarantine or enum or staleness" -v`
   → **Expect:** named tests exist and pass (maps FR-C1/C2/C5/C6, AC-5.2.1,
   AC-5.3.1). Test *names* must read like the spec IDs.
3. Same-second collision proof:
   `$ uv run python -m tests.manual.double_write`
   → **Expect:** two files listed, zero overwrites reported.
4. Kill-safety: `$ uv run octranspo collect-loop --interval 5 --duration 60`
   then `Ctrl+C` mid-run → **Expect:** clean exit message; `data/raw/` contains
   only complete files (no `.tmp`).
5. Quarantine shape: `$ jq '.errors | type' data/quarantine/**/*.jsonl | sort -u`
   → **Expect:** exactly `"array"`.
6. ⚖ Open `.github/workflows/` in the GitHub UI: every `uses:` shows a 40-char
   SHA + version comment; no `${{` inside any `run:` block; `permissions:`
   present at top. (3-minute visual scan; no code reading beyond YAML.)

## V-P1 — Capture live (the checkpoint that matters most)

1. `$ rclone ls r2:octranspo/parsed --max-depth 3 | head`
   → **Expect:** an object or zero-count manifest for every **UTC** hour
   since start — absence = incident; member_count=0 = quiet feed (DR-027/28).
   Newest hour directory name matches `date -u +%H`.
2. `$ rclone ls r2:octranspo/raw --max-depth 3 | head`
   → **Expect:** hourly `.tar.zst` bundles.
3. Dead-man proof: `$ sudo systemctl stop octranspo-collect.service` → wait
   grace window → **Expect:** healthchecks email AND push received.
   Restart; check green.
4. Reboot proof: `$ sudo reboot`; after 3 min:
   `$ systemctl is-active octranspo-collect octranspo-sync.timer octranspo-static.timer`
   → **Expect:** `active` ×3.
5. Wrong-bucket drill: run sync with `R2_BUCKET=doesnotexist` →
   **Expect:** non-zero exit; local files still present.
6. Volumetrics: `$ uv run python ops/volumetrics.py --days 2`
   → **Expect:** table of bytes/day (raw, parsed), files/day, records/day.
   ⚖ Compare to spec §8 assumptions; if off >2×, pause and update spec + DRs
   before Phase 2.
7. Static dedupe: after ≥2 daily snapshot runs with unchanged schedule:
   `$ rclone ls r2:octranspo/static` → **Expect:** one zip, manifest showing
   two check entries.
8. Staleness alert (RUNBOOK drill 5): frozen-payload feed → **Expect:**
   `stale_feed` fail-ping on `octranspo-feeds` within STALE_FEED_ALERT_S;
   collector check green throughout; recovery clears.
9. Decode failure (RUNBOOK drill 6): 200+HTML feed → **Expect:** fail-ping
   at streak N; payload present in raw/ AND quarantine (AC-5.2.4); ledger
   rows show outcome=decode_failed.
10. Bundle atomicity: kill the bundler mid-run (harness SIGKILL on a large
    staged hour), rerun → **Expect:** `zstd -t` passes on the bundle;
    manifest member_count equals the hour's per-poll file count.
11. Backlog sweep (RUNBOOK drill 7): 3 h bundler outage → **Expect:** all
    missing hours in R2 within one cycle, oldest first.
12. Hygiene: `$ rclone ls r2:octranspo | grep -c staging` → 0 (per-poll
    files never sync, AC-5.4.4); `$ stat -f %Lp .env` (BSD) / `stat -c %a`
    (Linux) → 600; drill-1 alert arrived on **both** channels.

## V-P2 — Warehouse backbone (hand-verified numbers)

1. `$ make build` (local) → **Expect:** completes < 15 min; prints mart row
   counts.
2. Fixture answer key: `$ dbt build --select int_stop_events__classified+ --target fixtures`
   → **Expect:** green, incl. the 12-case singular test.
3. **Hand verification (do not skip):** pick one real (route, day) you can
   reason about. Run the three queries in `docs/verify_queries.sql`
   (agent-provided, plain SQL):
   - Q1 scheduled events for that route/day from static GTFS;
   - Q2 the same count from `fct_stop_event`;
   - Q3 status breakdown for that route/day.
   → **Expect:** Q1 = Q2 exactly. ⚖ Q3 sanity: no_data share roughly consistent
   with OC Transpo's ~5% sensor caveat + outage windows you know about from
   healthchecks history; zero `skipped` unless a CANCELED/SKIPPED signal
   existed that day (spot-check one skipped example back to its parsed record
   with Q4, provided).
4. DST/service-day spot check: run Q5 (provided) for a >24:00 stop_time trip
   → **Expect:** scheduled epoch renders to the *next* calendar day local time,
   prior service_date.
5. Point-in-time SCD: Q6 joins a fact row from before a schedule change to
   dims → **Expect:** the old version's attributes.

## V-P3 — Metrics & semantic layer

1. `$ mf validate-configs` (or CI log) → **Expect:** pass.
2. Parity: `$ make parity` → **Expect:** all metrics identical (mf vs mart),
   zero tolerance; report table printed.
3. Tamper drill: `$ git apply docs/perturb_mart.patch && make parity`
   → **Expect:** FAIL naming the perturbed metric. `$ git checkout -- .`
4. Determinism: `$ make build && make build` → **Expect:** identical metric
   values both runs (script diffs and prints OK).
5. ⚖ Read only the metrics YAML (it's documentation-grade): do the definitions
   say what the methodology page will claim? Denominator of otp_rate must be
   observed events only; coverage separate.

## V-P4 — Observability

1. `$ dbt build --target fixtures --select tag:observability`
   → **Expect:** green; then `$ make obs-failcases` → **Expect:** each staged
   violation (volume drop, delay bound, quarantine spike, stale source) fails
   its named test and only that test.
2. Nightly proof: GHA `nightly.yml` green ≥3 consecutive real nights; on the
   forced-fail night (agent stages one), healthchecks build-check alerts.
3. `$ open artifacts/dbt-docs/index.html` → **Expect:** full DAG renders;
   fct_stop_event lineage traces to both realtime and static sources.

## V-P5 — Site (behavior only)

1. Every page in EN and FR; toggle round-trips to the same page. Numbers on
   Overview match `mart_reliability__system_daily` for the latest day (Q7).
2. Insufficient-data state visible for at least one low-sample route; that
   route absent from rankings.
3. Every punctuality figure has coverage % adjacent (FR-M5) — scan all pages.
4. Methodology thresholds equal the config values (agent prints config; you
   compare on-screen). Disclaimer + attribution present on About + footer.
5. Deploy gate: forced-red build → **Expect:** production site unchanged
   (compare a timestamp in footer).
6. Quality page shows: coverage trend, quarantine rate, freshness status,
   volume-band status — and they match `mart_quality__daily` (Q8).

## V-P6 — Launch

1. Fresh-clone test on a clean machine/VM: `git clone … && make install &&
   make check` → **Expect:** green with README instructions only.
2. 15-minute reviewer simulation: open repo cold; can you reach (a) the star
   schema diagram, (b) a metric definition, (c) a decision record, (d) the live
   site, each in ≤3 clicks from README? Fix nav if not.

---

## Fresh-agent audit prompts (run in a NEW session, no build context)

**Audit A — spec compliance:**
"You are auditing, not fixing. Repo attached. For every FR and AC in spec.md,
output a table: ID | met/not-met/partial | evidence (file:line or command
output) | severity. Then list any behavior in the code that spec.md does not
require (scope creep). Do not modify anything."

**Audit B — honesty invariants:**
"Adversarial review: find any path by which (1) an unobserved stop-event could
be counted as skipped or folded into punctuality, (2) a published number could
disagree between site, mart, and metric YAML, (3) raw data could be lost or
overwritten. Cite exact code paths; propose the minimal test that would have
caught each."

**Audit C — security/CI:**
"Review .github/, ops/, and all secret handling against FR-CI1..4 and
CLAUDE.md guardrails 7/9. Output findings with severity and one-line fixes."

Triage rule: audit findings ≥ 'moderate' block launch; the *building* session
implements fixes; the *audit* session re-verifies.

## Standing weekly ops check (post-launch, 5 minutes)
healthchecks all green · GHA nightly green · R2 usage vs free tier ·
site latest-day date is yesterday · quality page coverage ≥ recent norm.
