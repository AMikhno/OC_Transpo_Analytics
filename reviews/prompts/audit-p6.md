# Audit prompt — Phase P6: Launch & portfolio layer (checkpoint V-P6)

Run in a FRESH session before tagging v1.0.0. Stack class: **launch gate** —
this audit certifies the repo as a public, reviewable artifact. It is
lighter than the others but its REJECT conditions are absolute.

## 1. Session setup (binding)

- READ-ONLY audit. Findings, never fixes.
- Work in a COMPLETELY clean environment — ideally a fresh VM or container,
  at minimum an empty scratch dir on a machine that has never built this
  repo. The point of U1 is that no local state helps.
- Report begins with the literal sentence: **"I modified nothing."**
- Builder claims are not evidence; every verdict cites your own command +
  output or your own recorded click path.

## 2. Binding scope

| Item | One-line restatement |
|---|---|
| P6.1 | reviewer-first README; LICENSE Apache-2.0; badges; topics |
| P6.2 | DECISIONS.md finalized — every DR + open-item outcome recorded |
| P6.3 | fresh-agent audits (validation.md Audit A/B/C) run and triaged |
| P6.4 | tag v1.0.0 |
| DR-019 | attribution + non-affiliation disclaimer (README + site) |
| FR-CI5 | gitleaks; `uv lock --check`; read-only nightly R2 token |
| V-P6 | fresh-clone test; 15-minute reviewer simulation |

Out of bounds: re-auditing P0–P5 content (their own audits cover it) —
except via the closure probes below.

## 3. Independence rules and designed probes

- **U1 — fresh-machine test (V-P6.1).** In the clean environment:
  ```bash
  git clone https://github.com/AMikhno/OC_Transpo_Analytics && cd OC_Transpo_Analytics
  make install && make check
  ```
  following README instructions ONLY. Expected: green. Any undocumented
  prerequisite (a tool, an env var, a manual step not in README/RUNBOOK) =
  FAIL, naming it.
- **U2 — 3-click navigation (V-P6.2).** Starting from the rendered README
  on GitHub, reach each of: (a) the star-schema diagram, (b) one metric
  definition (YAML or metrics.md entry), (c) one decision record, (d) the
  live site. Record each click path. Any target needing >3 clicks = finding
  (accepted-with-findings class); any target unreachable = FAIL.
- **U3 — secrets over full history (G9).**
  `gitleaks detect --source . --log-opts=--all` → 0 leaks. Any hit = FAIL,
  and the finding must state whether the secret is still live (operator
  rotates before launch regardless).
- **U4 — decision-trail closure.** Mechanical checks:
  - Every open item V-1…V-10 in DECISIONS.md has either a recorded outcome
    or an explicit still-open status with an owner. Unmentioned = FAIL of
    P6.2.
  - Every DR number cited anywhere
    (`grep -rhoE 'DR-[0-9]{3}' --include='*.md' . | sort -u`) exists as a
    definition in DECISIONS.md. Dangling reference = finding.
  - LICENSE file is Apache-2.0; README states data attribution and
    non-affiliation (DR-019) — exact-string presence, both README and site
    About/footer (site side re-checked here even though P5 audited it:
    launch is the last gate).
- **U5 — CI final state (FR-CI5).** In `.github/workflows/`: gitleaks step
  present; `uv lock --check` present; nightly workflow references only the
  read-only R2 token secret name; actions SHA-pinned with version comments
  (`grep -nE 'uses:.*@[a-f0-9]{40}' .github/workflows/*.yml` — any
  `@vN`-only pin = finding).
- **U6 — audit-trail integrity (P6.3).** The Audit A/B/C reports from
  validation.md exist as artifacts (files or linked run logs), their
  ≥moderate findings each map to a fix commit or an explicit
  accepted-risk DR line. An audit finding with no disposition = FAIL.

## 4. Verification ladder

(a) P6.1–P6.4 items — verdict + evidence each (tag existence:
    `git tag --list 'v1*'` after the builder tags, or NOT VERIFIABLE if
    auditing pre-tag).
(b) Probes U1–U6.
(c) n/a (no fixture harness specific to this phase).
(d) UI: the U2 click paths and the U4 site-disclosure check are the only
    UI items; no code review.

## 5. Report contract

(1) "I modified nothing."; (2) PASS/FAIL/NOT VERIFIABLE counts; (3)
findings, most severe first — claim, command/click-path, output, item ID;
(4) **Residuals** — mandatory; NOT VERIFIABLE never silently becomes PASS.

## 6. Stop conditions

- **REJECT**: any U3 secrets hit; missing/incorrect disclaimer or
  attribution; fresh-machine failure (U1); an unresolved ≥moderate finding
  from Audit A/B/C (U6); nightly using the write token.
- **ACCEPTED-WITH-FINDINGS**: navigation ergonomics (>3 clicks), badge or
  topic gaps, README wording, SHA-pin comment style.
