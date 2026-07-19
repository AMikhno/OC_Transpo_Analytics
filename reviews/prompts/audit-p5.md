# Audit prompt — Phase P5: Bilingual site (checkpoint V-P5)

Run in a FRESH session after the builder declares P5 complete. Stack class:
**public honesty** — this is where the project's core promise (honest
denominators, coverage beside every number, disclosed method) becomes
visible or silently breaks.

**Behavior checks only.** You audit what renders and what numbers appear —
you never code-review frontend files. The only greps allowed against
`site/` are the two explicitly listed below (FR-M3 shape check,
content_revision check), because spec FR-P1/FR-M3 define them as mechanical
CI-style checks.

## 1. Session setup (binding)

- READ-ONLY audit. Findings, never fixes.
- Fresh clone in scratch; build the site against FIXTURE marts first, then
  check the production URL:
  ```bash
  git clone https://github.com/AMikhno/OC_Transpo_Analytics "$SCRATCH/audit-p5"
  cd "$SCRATCH/audit-p5" && uv sync --all-groups && make site-dev
  ```
- Report begins with the literal sentence: **"I modified nothing."**
- Builder claims and screenshots are not evidence; you load every page
  yourself. Numbers are verified against mart SQL you run yourself.
- Expected values come from metrics.md, architecture.md §8 config defaults,
  CASES §H, and mart queries — never from site code.

## 2. Binding scope

| ID | One-line restatement |
|---|---|
| FR-P1 | parallel /en + /fr trees; toggle preserves page; content_revision pairs match |
| FR-P2 | required pages + required visuals; methodology numbers from config |
| FR-P3 | deploy gated on green build; red build leaves site unchanged |
| FR-P4 | footer "data through {date}"; stale banner; /data-status.json |
| FR-M4 | insufficient-data rendering; below-threshold routes out of rankings |
| FR-M5 | coverage % adjacent to every punctuality figure |
| FR-M3 | site SQL: only Σnum/Σden over counts; no rate aggregation |
| DR-019 | attribution + non-affiliation disclaimer |
| DR-025 | all-stops measurement policy + divergence explanation on Methodology |

Plus plan.md P5.1–P5.5, CASES §H (F-P01/F-P02). Out of bounds: mart
correctness (P3), frontend code quality, visual design taste.

## 3. Independence rules and designed probes

- **U1 — three-way number match.** For the latest complete service_date in
  the fixture marts: read Overview's system OTP and coverage off the page;
  run `select otp_rate, coverage_rate from mart_reliability__system_daily
  where service_date = <latest complete>` yourself; fetch
  `/data-status.json`. Expected: page number == SQL (within display
  rounding, 0.1 pp per metrics.md §6) and data_through == footer date ==
  the mart's latest complete service_date. Repeat for ONE route-detail
  figure vs mart_reliability__route_daily, route of your choosing. Any
  mismatch = FAIL.
- **U2 — coverage adjacency sweep (FR-M5).** For every page in FR-P2's
  list (Overview, Routes, Route detail, Methodology, Data Quality, About) in
  BOTH languages: fill a checklist row — does every punctuality figure have
  its coverage % inside the same visual component (same card/tile/tooltip,
  not merely the same page)? Any bare punctuality figure = FAIL.
- **U3 — insufficient-data boundary (FR-M4).** Fixture route with 150
  scheduled events: renders the "insufficient data" state and is ABSENT
  from every ranked table. A fixture route at exactly MIN_EVENTS=200:
  ranked. Silent omission (no state shown) = FAIL even if excluded.
- **U4 — toggle round-trip + revision pairs (FR-P1).** From every page:
  toggle EN→FR→EN returns to the same page. Then the one sanctioned grep:
  compare `content_revision` front-matter across each page pair —
  expected: equal per pair; any mismatch = FAIL (drift guard).
- **U5 — staleness banner (FR-P4/F-P01/F-P02).** Build from the stale
  fixture (latest complete date 5 days old, STALE_BANNER_DAYS=3): banner on
  EVERY page; data-status.json matches the footer. Rebuild fresh: banner
  absent. One page missing the banner = FAIL.
- **U6 — window-math shape (FR-M3, second sanctioned grep).**
  `grep -rnE 'avg\(|mean\(' site/` filtered to SQL over rate columns →
  expected 0 hits; any 7/28/90-day figure on the page must trace to a
  Σcount/Σcount query (open the page's query file only to confirm the
  shape — this is the CI check re-run, not code review).
- **U7 — deploy gate (FR-P3).** Trigger (or have the operator trigger) a
  forced-red build per the builder's documented mechanism; expected:
  production site unchanged — compare a footer build timestamp before/after.
  If no forced-red mechanism is documented, NOT VERIFIABLE + finding
  (validation V-P5.5 requires the proof).
- **U8 — disclosure content (DR-019/DR-025).** About + footer: attribution
  and non-affiliation disclaimer present in EN and FR. Methodology page:
  states thresholds numerically (compare to `OTP_EARLY_S=60`,
  `OTP_LATE_S=300` or current config — have the operator print the config
  values; page must match exactly), the all-stops policy, the interpolated-
  times caveat, the expected divergence from official OTP, the ~5% sensor
  caveat, and the no_data/coverage definitions per metrics.md. A
  methodology number that differs from config = FAIL (hand-typed
  threshold).

## 4. Verification ladder

(a) FR-P1..P4, FR-M4/M5 ACs — verdict + observed behavior each (screenshot
    or copied page text + the command/URL used).
(b) Probes U1–U8.
(c) Fixture cases F-P01/F-P02 re-run (stale + fresh builds).
(d) UI behavior checks are (a)–(c) themselves; no frontend file review.

## 5. Report contract

(1) "I modified nothing."; (2) PASS/FAIL/NOT VERIFIABLE counts; (3)
findings, most severe first — claim, page/URL + command, observed vs
expected, spec ID; (4) **Residuals** — mandatory; NOT VERIFIABLE never
silently becomes PASS.

## 6. Stop conditions

- **REJECT**: any FAIL on number equality (U1), coverage adjacency (U2),
  insufficient-data handling (U3), staleness banner (U5), window-math shape
  (U6), deploy gate (U7), or disclosures (U8). These are the public-honesty
  surface — the site lying about or omitting its own uncertainty is the
  project's defining failure.
- **ACCEPTED-WITH-FINDINGS**: styling, layout, chart aesthetics, FR
  translation wording (flag for Ana's review — she reviews translations per
  plan P5.4), performance.
