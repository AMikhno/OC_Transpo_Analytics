# Audit prompt — Phase P0: Collector build (checkpoint V-P0)

Run this in a FRESH session with no build context, after the builder declares
P0 complete. Stack class: **capture integrity** — defects here cause
retroactive, permanent data loss once capture goes live.

## 1. Session setup (binding)

- This is a READ-ONLY audit session. You produce findings, never fixes. Do
  not edit, create, delete, or reformat any repository file; do not commit,
  push, or change any config. If you catch yourself fixing something, stop
  and write it up as a finding instead.
- Work in a fresh clone in a scratch directory — never in a working tree the
  builder used:
  ```bash
  git clone https://github.com/AMikhno/OC_Transpo_Analytics "$SCRATCH/audit-p0"
  cd "$SCRATCH/audit-p0" && uv sync --all-groups
  ```
- Your report MUST begin with the literal sentence: **"I modified nothing."**
- Builder claims are not evidence. Commit messages, code comments, CI logs,
  and pasted test output prove nothing. Every verdict cites a command YOU ran
  in this session plus its captured output.
- Expected values come from spec.md / fixtures/CASES.md or are pre-computed
  in this prompt — never from the implementation. If code and spec disagree,
  the spec wins and the disagreement is a finding, even if all tests pass.

## 2. Binding scope

spec.md requirements this phase claims to satisfy (verify against the live
spec text; one-line restatements here are orientation, not authority):

| ID | One-line restatement |
|---|---|
| FR-C1 | atomic, collision-safe, overwrite-proof raw writes; loud ENOSPC |
| FR-C2 | ≤3 retries, backoff+jitter, inside the poll-interval budget |
| FR-C3 / AC-5.2.2 | `_ingested_at` + `feed_timestamp` on every record |
| FR-C4 | bilingual translation maps preserved (scope per V-1 outcome) |
| FR-C5 | per-cycle per-feed ledger row with counts + feed_header_ts; unchanged-skip |
| FR-C6 / §5.3 | single QuarantineRecord schema (AC-5.3.1/5.3.2) |
| FR-C7 | static snapshot: streaming, size cap, sha256 dedupe |
| FR-C8 | failure-streak + stale-feed fail-pings on the feeds channel |
| FR-C9 | SIGTERM finishes in-flight poll, flushes, exits 0 |
| AC-5.2.1 | unknown enum → quarantine `unknown_enum` |
| AC-5.2.3 | parsed field contract (full field list in spec) |
| AC-5.2.4 | raw = verbatim pre-decode HTTP body; decode_failed path |
| AC-5.4.3 | landing paths/hours are UTC |
| AC-5.4.4 | per-poll files live in `staging/`, outside the synced tree |

Plus plan.md tasks P0.1–P0.11 and fixture rows CASES §B (F-C01…F-C12).
Out of bounds: dbt models, the site, VPS/systemd behavior (that is P1), and
any v1 requirement. Do not report on out-of-scope code except via the
recurring invariant probes below.

## 3. Independence rules and designed probes

Re-run everything yourself from the clean clone:

```bash
make check          # ruff + mypy --strict + pytest + (sqlfluff/dbt skipped pre-P2)
uv run pytest -q    # full suite, no -k filter
uv run pytest --cov=ingestion --cov=ops --cov-report=term  # ≥85% lines each (FR-CI4)
```

Probes the builder could not have anticipated — run all four; each states
its expected observable outcome:

- **U1 — delay-only update (AC-5.2.3).** Build a TripUpdates .pb (use the
  repo's fixture builder from P0.1) whose stop_time_update carries
  `arrival.delay = +120` and **no `arrival.time`** — the live feed sends
  absolute times, so builder tests likely never cover this legal GTFS-RT
  form. Parse it through the collector's parse path. Expected: the parsed
  JSON record contains arrival delay 120 and a null/absent arrival time;
  nothing dropped, no quarantine. A KeyError, a fabricated time, or a
  quarantined record is a FAIL against AC-5.2.3.
- **U2 — unwritable landing (FR-C1/FR-Y3/DR-027).** Point the collector's
  healthchecks URL at a local mock HTTP server you run in the scratch dir
  (log every request). Start a short collect-loop against fixture feeds,
  then `chmod -w` the staging directory mid-loop. Expected: subsequent
  cycles record ledger outcome=write_failed AND the mock server receives
  zero dead-man pings for those cycles. A ping despite the failed write is
  a FAIL (this is audit-finding F-01's regression check).
- **U3 — mixed-error payload (§5.3).** One poll payload containing BOTH an
  entity with `schedule_relationship="SOMETHING_NEW"` and a
  VehiclePositions entity lacking `position`. Expected: two quarantine
  records; `jq '.errors | type'` over the quarantine output prints exactly
  `"array"` for both; error shapes match AC-5.2.1 and AC-5.3.1
  respectively. One combined record, or two schemas, is a FAIL.
- **U4 — frozen feed at auditor-chosen threshold (FR-C8).** Serve
  byte-identical payloads (frozen header) from a local mock with
  STALE_FEED_ALERT_S overridden to 60. Expected: exactly one `stale_feed`
  fail-ping at the threshold, naming the feed, on the feeds channel; zero
  further pings while frozen; recovery (fresh header) clears state with no
  repeat ping. Also confirms the threshold is config, not a literal.

Recurring invariant probes (report each as PASS/FAIL with output):

- **G2**: run the same-second double-write test (F-C01 command or
  `tests.manual.double_write` per validation.md V-P0.3); expected: two
  files, zero overwrites. Then attempt a deliberate second write to an
  existing raw filename; expected: refused (open mode excludes overwrite).
- **G5**: `git diff <sha-of-last-audited-commit> -- pyproject.toml uv.lock`;
  any dependency not in CLAUDE.md §2's table without a DR line = FAIL.
- **G7**: `grep -n '\${{' .github/workflows/*.yml` — hits inside `run:`
  blocks = FAIL (FR-CI3).
- **G9**: `gitleaks detect --source . --log-opts=--all` → 0 leaks.
- **G12**: `grep -rnE 'datetime\.now\(|\.astimezone\(|timedelta\(' ingestion ops`
  — every hit is a finding unless it is demonstrably presentation/logging
  only; duration or scheduling math on wall-clock objects violates
  CLAUDE.md guardrail 12.

## 4. Verification ladder (in this order, labeled)

(a) **Acceptance criteria**: for every AC in §2's table, one verdict —
PASS / FAIL / NOT VERIFIABLE — with the command run and trimmed output.
Test *names* should map to spec IDs (validation.md V-P0.2); a passing suite
whose names cannot be mapped to FR-C IDs is a finding (traceability).
(b) **Designed probes** U1–U4, one verdict each.
(c) **Fixture harness**: `uv run pytest -q` re-run of CASES §B rows
F-C01…F-C12; cross-check each row's Expected column against the test's
assertion — an assertion weaker than the table (e.g., checks file count but
not readability for F-C01) is a finding.
(d) UI: n/a for this phase.

## 5. Report contract

Produce, in order: (1) the literal opening sentence "I modified nothing.";
(2) verdict summary — counts of PASS / FAIL / NOT VERIFIABLE; (3) findings,
most severe first — each with claim, exact command, captured output,
file:line where relevant, violated spec ID; (4) **Residuals** (mandatory):
every in-scope item not verified and why. NOT VERIFIABLE is an acceptable
verdict; converting it silently to PASS is a report defect.

## 6. Stop conditions

- **REJECT** (phase returns to builder): any FAIL on FR-C1, FR-C5, FR-C8,
  FR-C9, AC-5.2.3, AC-5.2.4, or the §5.3 quarantine contract — these are
  the capture-integrity surface; a defect that ships here becomes permanent
  data loss. Any G9 (secrets) FAIL also rejects.
- **ACCEPTED-WITH-FINDINGS** permissible only for: FR-CI2/CI3 hardening
  gaps, coverage shortfall below 85% (report exact %), test-naming
  traceability, and G12 hits that are demonstrably display-only.
