# Audit prompt — Phase P1: Capture live, VPS + R2 (checkpoint V-P1)

Run in a FRESH session after ≥48 h of live capture. Stack class:
**durability** — this layer is why host failure is a gap and not a loss;
any defect here silently destroys history.

Some commands run on the VPS or against R2. If the auditing session lacks
SSH/R2 access, the operator (Ana) runs the exact commands this prompt
dictates and pastes raw output; the auditor still writes the verdicts. The
operator must not substitute commands or pre-filter output.

## 1. Session setup (binding)

- READ-ONLY audit. Findings, never fixes. Nothing on the VPS or in R2 is
  modified except where a drill explicitly says so (drills stop/start
  services; they never delete data).
- Repo work happens in a fresh clone:
  ```bash
  git clone https://github.com/AMikhno/OC_Transpo_Analytics "$SCRATCH/audit-p1"
  cd "$SCRATCH/audit-p1" && uv sync --all-groups
  ```
- Your report MUST begin with the literal sentence: **"I modified nothing."**
  (Drill-induced stop/start events are listed under a "drill actions" note.)
- Builder/operator claims are not evidence — including healthchecks
  screenshots from setup day. Every verdict cites a command run during THIS
  audit with captured output.
- Expected values come from spec.md §5.4/FR-Y*, DR-027/028/029/032/034,
  RUNBOOK, CASES §C, or this prompt — never from ops code.

## 2. Binding scope

| ID | One-line restatement |
|---|---|
| FR-Y1 | atomic manifest-verified bundling; all-closed-hours sweep; zero-count manifests |
| FR-Y2 | rclone copy + `rclone check`; prune only checked + aged hours |
| FR-Y3 | dead-man ping only after durable write; feed health separate |
| FR-Y4 | collector = restarting service; bundler/sync + static = timers; reboot-safe |
| AC-5.4.3 | UTC paths and bundle boundaries |
| AC-5.4.4 | staging/ never syncs; R2 holds only the §5.4 layout |
| DR-033 | non-deleting sync; V-9 delete-test outcome recorded |

Plus plan.md P1.1–P1.5, RUNBOOK §§4–6, CASES §C (F-Y01…F-Y09), and
validation.md V-P1 items 1–12. Out of bounds: collector internals (audited
at P0), dbt, site.

## 3. Independence rules and designed probes

Baseline re-runs (VPS):

```bash
systemctl is-active octranspo-collect octranspo-sync.timer octranspo-static.timer   # active ×3
systemctl show octranspo-collect -p Type,Restart    # service w/ Restart=on-failure (DR-034)
```

Then execute validation.md V-P1 items 1–12 exactly as written there.

Designed probes — the auditor chooses the samples, never the builder:

- **U1 — random-hour integrity (DR-028).** Pick an arbitrary fully-synced
  UTC hour ≥24 h old — your choice, stated in the report, not one the
  builder demonstrated. Download its raw bundle + manifest from R2:
  `zstd -t <bundle>` passes; `tar -tf <bundle> | wc -l` equals the
  manifest's member_count; `sha256sum <bundle>` equals the manifest's
  sha256. Repeat for the same hour's parsed .jsonl.gz
  (`gunzip -t`, line count vs manifest). Any mismatch = FAIL.
- **U2 — UTC naming (AC-5.4.3).** On the VPS: newest hour directory name
  equals `date -u +%H` (mid-hour). Pick one complete past calendar day in
  R2: exactly 24 hour objects/manifests per stream. 23 or 25 without a DST
  explanation dated to that day = FAIL.
- **U3 — ledger cadence (DR-027/034).** For one random complete hour, count
  ledger rows per feed: expected 110–130 (30 s cadence ± jitter). Below 110
  = crash-loop or overlap symptom; above 130 = duplicate-instance symptom;
  both FAIL. For service-hour rows, parsed_count > 0; a service-hour run of
  rows with parsed_count = 0 and outcome=ok is a FAIL (the F-01 silent-
  capture regression).
- **U4 — staging leak (AC-5.4.4/DR-007).** `rclone ls r2:octranspo` piped
  through a filter for `staging` and for `.pb` paths outside `raw/` bundles:
  expected 0 objects. Cloudflare dashboard class-A operations for the
  current month: within DR-007's stated budget; a 10×+ anomaly = FAIL.
- **U5 — channel separation (DR-032).** Re-run RUNBOOK drill 4 with a bad
  URL you choose. Expected: `octranspo-feeds` alerts once naming the feed;
  the `octranspo-collector` check stays green for the entire window (check
  its event log); recovery clears with no repeat. A red collector check
  during a feed-only failure = FAIL.

Recurring invariant probes:

- **G2**: rerun the bundler on an already-bundled hour (F-Y01): exit 0,
  object checksums unchanged (capture before/after `rclone hashsum`).
- **G3**: list local landing hours: none older than RETENTION_DAYS remain;
  pick 3 pruned hours from the ledger's history and confirm each exists in
  R2. A pruned hour absent from R2 is the worst possible finding — report
  it first.
- **G5 / G9**: as in audit-p0 (fresh clone).

## 4. Verification ladder

(a) FR-Y1..Y4 ACs, one verdict each, command + output.
(b) Probes U1–U5.
(c) CASES §C rows: F-Y01–F-Y04 re-run directly; F-Y05–F-Y09 re-run where a
    VPS drill can reproduce them (F-Y06/F-Y07 kill-mid-bundle: run against a
    staged copy of one hour in a scratch dir on the VPS using the ops
    bundler CLI — never against live staging). Mark any row not
    reproducible as NOT VERIFIABLE with the reason.
(d) UI: n/a. (healthchecks dashboards are read as evidence artifacts, not
    audited as UI.)

## 5. Report contract

(1) "I modified nothing." + drill-actions note; (2) PASS/FAIL/NOT VERIFIABLE
counts; (3) findings, most severe first, each with claim + command + output
+ spec ID; (4) **Residuals** — every unverified in-scope item and why. NOT
VERIFIABLE never silently becomes PASS.

## 6. Stop conditions

- **REJECT on any FAIL.** This phase is the durability layer; there is no
  tolerable defect class. The only accepted-with-findings category is
  purely documentary (runbook typos, naming drift) where the observed
  behavior itself passed.
- Additionally REJECT if the V-9 delete-capability test result is recorded
  nowhere (DECISIONS.md open item must have an outcome by end of P1).
