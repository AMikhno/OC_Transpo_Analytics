# RUNBOOK.md — v0 capture: setup, drills, steady-state ops

Audience: the operator (you), by hand — this is the deliberately hands-on
part of the project (DR-010 discussion). Sections 1–3 are doable today,
before any code lands. Section 4 needs the P1.1/P1.2 artifacts merged.
Est. total hands-on time: ~half a day.

## 1. Accounts & credentials (≈30 min, today)

**1.1 Cloudflare R2**
- Dashboard → R2 → Create bucket `octranspo` (location hint: Eastern NA).
- R2 → Manage API Tokens → create **two** tokens, both scoped to bucket
  `octranspo` only: (1) **Object Read & Write** — lives on the VPS for the
  collector/sync; (2) **Object Read only** — lives in GitHub Actions secrets
  for the nightly build (FR-CI5; the build never writes). Leave token TTL at
  the default "Forever" (no surprise mid-operation expiry; rotation is a
  manual §7 play). Record Access Key ID + Secret for each **in your password
  manager** — never in the repo, never on the VPS beyond `.env` — plus
  Account ID (endpoint `https://<account_id>.r2.cloudflarestorage.com`).
- Free tier sanity: 10 GB storage / 1M class-A writes / 10M class-B reads
  per month; our layout uses ~2–3k class-A/month (DR-007).

**1.2 healthchecks.io** — create 4 checks (v0) + 1 later (v1):
| check | period | grace |
|---|---|---|
| octranspo-collector | 5 min | 10 min |
| octranspo-sync | 1 h | 30 min |
| octranspo-static | 24 h | 6 h |
| octranspo-feeds (FR-C8 alerts only) | — | — |
| octranspo-nightly-build (v1, later) | 24 h | 3 h |
Add your email **and** phone push as alert channels — both mandatory; a
single spam-filtered channel is a silent dead-man. Record each ping URL.
The collector pings `octranspo-collector` per completed-and-durably-written
cycle (spec FR-Y3/DR-027). FR-C8 fail-pings (401/404 streaks, decode
failures, stale feed header) target **`octranspo-feeds`**, never the
collector check — a failing feed keeps the dead-man green (spec F-Y05,
DR-032), so feed death and host death are never conflated. Note: never ping
one check more than ~5×/min — healthchecks throttles above that.

**1.3 OC Transpo developer portal** — confirm your subscription key is
active. While you're there: **do V-1** — check whether ServiceAlerts exists
as a GTFS-RT endpoint or only as RSS. Record the answer in DECISIONS.md.
Verified endpoints (live check 2026-07-19; base
`https://nextrip-public-api.azure-api.net/octranspo`):
TripUpdates `…/gtfs-rt-tp/beta/v1/TripUpdates` (note **`-tp`**, not `-tu`),
VehiclePositions `…/gtfs-rt-vp/beta/v1/VehiclePositions`; key goes in the
`Ocp-Apim-Subscription-Key` header.

**1.4 Hetzner** — account + SSH key uploaded (Project → Security → SSH keys).

## 2. Provision the VPS (≈30 min, today)

- Create server: **CAX11** (2 vCPU ARM, 4 GB), **Ubuntu 24.04**, your SSH
  key, no extras. Nearest DC is fine — latency is irrelevant at 30s polling.
- First login hardening (as root, then never again):
```bash
adduser octo && usermod -aG sudo octo
rsync --archive --chown=octo:octo ~/.ssh /home/octo
ufw allow OpenSSH && ufw --force enable
timedatectl set-timezone UTC && timedatectl timesync-status | head -3  # UTC + NTP synced (DR-029)
apt update && apt -y upgrade && apt -y install unattended-upgrades rclone git
dpkg-reconfigure -plow unattended-upgrades   # enable
# /etc/ssh/sshd_config: PasswordAuthentication no, PermitRootLogin no
systemctl restart ssh
```
- Install uv as `octo`: `curl -LsSf https://astral.sh/uv/install.sh | sh`.

## 3. Configure rclone → R2 (≈10 min, today)

As `octo`: `rclone config` → new remote `r2` → type `s3` → provider
`Cloudflare` → paste key/secret → endpoint from 1.1 → defaults elsewhere.
Verify: `rclone lsd r2:` shows the bucket; `echo ok > /tmp/ok && rclone copy
/tmp/ok r2:octranspo/_smoke/ && rclone ls r2:octranspo/_smoke/` round-trips.
**Capability test (V-9)**: `rclone deletefile r2:octranspo/_smoke/ok` —
record in DECISIONS.md whether the RW token can delete objects (Cloudflare's
docs and community reports disagree); the outcome sets DR-033's posture.

## 4. Install the collector (after P1.2 merges)

```bash
git clone https://github.com/AMikhno/OC_Transpo_Analytics && cd OC_Transpo_Analytics
uv sync --all-groups
cp .env.example .env && chmod 600 .env   # set: OCTRANSPO_API_KEY, R2 remote name, healthchecks URLs
uv run octranspo collect-once      # smoke: files appear under ./data
sudo cp ops/systemd/*.{service,timer} /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now octranspo-collect.service octranspo-sync.timer octranspo-static.timer
systemctl is-active octranspo-collect    # active — long-running service, not a timer (DR-034)
systemctl list-timers | grep octranspo   # two timers (sync, static), next-run populated
```
Within ~10 min: healthchecks collector+sync green. Within ~70 min:
`rclone ls r2:octranspo/parsed` shows the first hourly object.

## 5. Acceptance drills (validation.md V-P1 — run all eight, once)
1. **Dead-man**: `sudo systemctl stop octranspo-collect.service` → alert
   arrives within grace **on both channels (email + push)** → restart →
   green.
2. **Reboot**: `sudo reboot` → collector service + both timers active after
   boot.
3. **Wrong bucket**: run sync with `R2_BUCKET=doesnotexist` → non-zero exit,
   nothing pruned.
4. **Endpoint streak**: point one feed URL at a 404 path in `.env` for ~6 min
   → fail-ping fires once on `octranspo-feeds`, **collector check stays
   green** → restore → recovery, no repeat ping.
5. **Freeze drill**: point one feed URL at a local static file server
   serving a fixed .pb → `stale_feed` fail-ping within STALE_FEED_ALERT_S,
   naming the feed → restore → recovery.
6. **Garbage drill**: point one feed URL at a page returning 200 + HTML →
   decode_failed streak fail-ping at streak N; the payload appears in raw/
   and quarantine (spec AC-5.2.4).
7. **Bundler backlog**: `sudo systemctl stop octranspo-sync.timer` for 3 h
   (collector running) → restart → within one cycle all missing hours appear
   in R2 (`rclone ls`), oldest first.
8. **Volumetrics** (after 48 h): `uv run python ops/volumetrics.py --days 2`
   → paste output into DECISIONS.md V-5; compare to spec §8; if off >2×,
   stop and revise spec before Phase 2. Same session: decide **V-8** (R2
   economics) from the measured number; confirm overnight `feed_header_ts`
   advancement from the ledger (closes A8); check the weekday TU-vs-VP
   coverage gap (V-10).

## 6. Steady state

**Weekly (5 min):** healthchecks dashboard all green · `rclone size
r2:octranspo` vs free tier · latest `parsed/` date is today **and its
ledger rows show nonzero parsed_count during service hours** (a date alone
can't prove data is flowing) · `df -h /` headroom · ledger rows last 24 h
≈ 2,880/feed (overlap or crash-loop tripwire) ·
(v1) nightly build green and site latest-day = yesterday.

**Annually (December, 10 min):** extend the Ontario/Ottawa holiday seed for
the coming year; nightly build's dim_date test fails loudly if you forget.

**Monthly (10 min):** `apt upgrade` if unattended missed anything · review
Dependabot PRs · R2 class-A ops in Cloudflare analytics (should be ~2–3k) ·
`journalctl -u octranspo-collect --since -7d | grep -ci error` trend.

## 7. Incident playbook

| symptom | action |
|---|---|
| Dead-man alert, host unreachable | Hetzner console reboot; if hardware-dead: new CAX11, rerun §2–4 (≤1 h). Gap = downtime; synced data safe (DR-008). |
| Endpoint-streak alert | Check portal for new paths (beta → GA move); update `.env` URLs; restart timers; DR the change. |
| Sync failing, collector fine | Disk fills in ~days, not hours (hourly bundles): check rclone auth/token expiry first; local data is the buffer. |
| Disk full | Only reachable after multi-day sync failure. Fix sync first; **never delete unsynced data** (CLAUDE.md guardrail 3). Collector fails loudly on ENOSPC (dead-man red, spec FR-C1) — that's by design, not a second incident. |
| R2 token leaked | Cloudflare → revoke token, issue new, update `.env`; audit bucket for foreign writes (`rclone lsl`, sort by time). |
| API key compromised/rotated | Portal → regenerate; update `.env`; expect one failed cycle max. |
| Quota/billing surprise | Nothing here can bill beyond VPS €4/mo; R2 overage ≈ $0.015/GB — investigate, don't panic. |

## 8. Cost ledger
Hetzner CAX11 ≈ €4/mo (verify at signup) · R2 $0 within free tier ·
healthchecks free tier (≤20 checks) · GHA free (public repo) ·
Cloudflare Pages free. Total ≈ €48/yr.
