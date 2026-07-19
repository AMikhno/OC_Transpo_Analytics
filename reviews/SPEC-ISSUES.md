# reviews/SPEC-ISSUES.md — spec defects observed while authoring audit prompts

Found 2026-07-19 during the prompt-authoring pass over spec.md / plan.md /
validation.md / CLAUDE.md / DECISIONS.md / RUNBOOK.md / fixtures/CASES.md.
Recorded per the authoring session's role (report, don't fix). Each needs an
owner decision; none blocks prompt use.

1. **`octranspo-feeds` check mechanics** (RUNBOOK §1.2 / DR-032 / FR-C8).
   healthchecks.io has no ping-less "alert-only" check type. After an FR-C8
   *recovery* success-ping, a period-based check begins expecting regular
   pings and will fire spurious "down" alerts when none come. Options: set
   the period very long (e.g., 365 d) so the expectation is inert, or signal
   recovery some other way (e.g., a log-only event, no success ping).
   Affects P1.1 implementation; audit-p1 U5 will surface the symptom if
   unresolved.

2. **plan.md P1.4 wording predates DR-034.** "Kill-tests: stop timer →
   dead-man alert" still describes the collector as a timer; DR-034 made it
   a long-running service (RUNBOOK §5 and validation V-P1.3 were updated;
   this line was missed). One-word fix ("stop service"), needs a commit.

3. **Definition-of-done vs CI gap** (CLAUDE.md §6 vs FR-CI5). `make check`
   is the done-gate, but gitleaks and `uv lock --check` run only in CI — a
   task can be locally "done" yet fail CI on a leaked string or stale
   lockfile. Either add both to `make check` or record the gap as
   deliberate (fast local loop) in a DR line.

4. **validation.md V-P0 item 2 keyword list is stale.** The pytest filter
   ("atomic or retry or quarantine or enum or staleness") predates
   AC-5.2.4/F-C11 — no "decode" keyword, so decode-path tests aren't
   surfaced by the named command even when they exist. Add "or decode" (and
   consider "or stale_feed" for F-C12) when P0 lands.
