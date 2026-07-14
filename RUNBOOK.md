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
  for the nightly build (FR-CI5; the build never writes). Record Access Key
  ID + Secret for each, plus Account ID (endpoint
  `https://<account_id>.r2.cloudflarestorage.com`).
- Free tier sanity: 10 GB storage / 1M class-A writes / 10M class-B reads
  per month; our layout uses ~2–3k class-A/month (DR-007).

**1.2 healthchecks.io** — create 3 checks (v0) + 1 later (v1):
| check | period | grace |
|---|---|---|
| octranspo-collector | 5 min | 10 min |
| octranspo-sync | 1 h | 30 min |
| octranspo-static | 24 h | 6 h |
| octranspo-nightly-build (v1, later) | 24 h | 3 h |
Add your email (and phone push if you use the app) as alert channels. Record
each ping URL. The collector pings per successful cycle; a distinct
**fail-ping** on the collector check is used for the 401/404 streak alert
(FR-C8) so endpoint death and host death are distinguishable in the timeline.

**1.3 OC Transpo developer portal** — confirm your subscription key is
active. While you're there: **do V-1** — check whether ServiceAlerts exists
as a GTFS-RT endpoint or only as RSS. Record the answer in DECISIONS.md.

**1.4 Hetzner** — account + SSH key uploaded (Project → Security → SSH keys).

## 2. Provision the VPS (≈30 min, today)

- Create server: **CAX11** (2 vCPU ARM, 4 GB), **Ubuntu 24.04**, your SSH
  key, no extras. Nearest DC is fine — latency is irrelevant at 30s polling.
- First login hardening (as root, then never again):
```bash
adduser octo && usermod -aG sudo octo
rsync --archive --chown=octo:octo ~/.ssh /home/octo
ufw allow OpenSSH && ufw --force enable
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

## 4. Install the collector (after P1.2 merges)

```bash
git clone https://github.com/AMikhno/octranspo-reliability && cd octranspo-reliability
uv sync --all-groups
cp .env.example .env   # set: OCTRANSPO_API_KEY, R2 remote name, healthchecks URLs
uv run octranspo collect-once      # smoke: files appear under ./data
sudo cp ops/systemd/*.{service,timer} /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now octranspo-collect.timer octranspo-sync.timer octranspo-static.timer
systemctl list-timers | grep octranspo   # three timers, next-run populated
```
Within ~10 min: healthchecks collector+sync green. Within ~70 min:
`rclone ls r2:octranspo/parsed` shows the first hourly object.

## 5. Acceptance drills (validation.md V-P1 — run all five, once)
1. **Dead-man**: `sudo systemctl stop octranspo-collect.timer` → alert
   arrives within grace → restart → green.
2. **Reboot**: `sudo reboot` → all three timers active after boot.
3. **Wrong bucket**: run sync with `R2_BUCKET=doesnotexist` → non-zero exit,
   nothing pruned.
4. **Endpoint streak**: point one feed URL at a 404 path in `.env` for ~6 min
   → distinct fail-ping fires once → restore → recovery, no repeat ping.
5. **Volumetrics** (after 48 h): `uv run python ops/volumetrics.py --days 2`
   → paste output into DECISIONS.md V-5; compare to spec §8; if off >2×,
   stop and revise spec before Phase 2.

## 6. Steady state

**Weekly (5 min):** healthchecks dashboard all green · `rclone size
r2:octranspo` vs free tier · latest `parsed/` date is today ·
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
| R2 token leaked | Cloudflare → revoke token, issue new, update `.env`; audit bucket for foreign writes (`rclone lsl`, sort by time). |
| API key compromised/rotated | Portal → regenerate; update `.env`; expect one failed cycle max. |
| Quota/billing surprise | Nothing here can bill beyond VPS €4/mo; R2 overage ≈ $0.015/GB — investigate, don't panic. |

## 8. Cost ledger
Hetzner CAX11 ≈ €4/mo (verify at signup) · R2 $0 within free tier ·
healthchecks free tier (≤20 checks) · GHA free (public repo) ·
Cloudflare Pages free. Total ≈ €48/yr.
