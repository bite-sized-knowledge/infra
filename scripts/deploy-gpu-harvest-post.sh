#!/bin/bash
# Wake the GPU machine and rebuild harvest_post's docker image on it.
#
# This script runs on the Mac host (bite-server user). It is invoked by the
# deploy-webhook container via SSH into host.docker.internal, which lands as
# bite-server on the Mac — so this script has access to Mac's PATH,
# wakeonlan, and Mac's ~/.ssh/id_ed25519 (the key authorized on the GPU).
#
# Flow:
#   1. WoL magic packet to GPU MAC
#   2. Poll GPU SSH port until reachable (max 120s)
#   3. SSH into GPU: git pull + docker compose build harvest-post
#      (the actual harvest run + shutdown is handled separately by the
#      harvest-post.service systemd unit, which runs on boot.)
#
# Exits non-zero if any step fails, so the webhook + CI surface the error.

set -euo pipefail

GPU_MAC="70:85:c2:a8:ad:b2"
GPU_HOST="192.168.219.101"
GPU_USER="siroo"
SSH_OPTS="-o StrictHostKeyChecking=accept-new -o ConnectTimeout=5 -o BatchMode=yes"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"; }

# --- 1. wake ---
log "sending WoL to $GPU_MAC"
/opt/homebrew/bin/wakeonlan "$GPU_MAC" > /dev/null

# --- 2. wait for SSH ---
log "waiting for $GPU_HOST:22"
READY=0
for i in $(seq 1 60); do
    if nc -z -w 2 "$GPU_HOST" 22 2>/dev/null; then
        log "GPU SSH ready after ${i} attempts"
        READY=1
        break
    fi
    sleep 2
done
if [ "$READY" -ne 1 ]; then
    log "ERROR: GPU did not come up within 120s"
    exit 1
fi

# Extra buffer for sshd to be actually accepting sessions
sleep 3

# --- 3. git pull + docker build on GPU ---
# After build, explicitly restart harvest-post.service to run the FRESH
# code. On boot systemd already tried to run the old run.sh via
# WantedBy=multi-user.target; by the time we pulled new code that auto-
# start had already failed (or used stale code). `systemctl restart`
# resets the failed state and re-execs run.sh with the up-to-date files.
log "git pull + docker compose build on GPU"
ssh $SSH_OPTS "$GPU_USER@$GPU_HOST" bash <<'REMOTE'
set -euo pipefail
cd ~/harvest_post
echo "[gpu] current HEAD: $(git rev-parse --short HEAD 2>/dev/null || echo none)"
git fetch --quiet origin prod
git reset --hard origin/prod
echo "[gpu] new HEAD: $(git rev-parse --short HEAD)"
docker compose -f docker-compose.gpu.yml build harvest-post
echo "[gpu] build complete"
# Copy the possibly-updated systemd unit file into /etc/ — if the unit
# file itself changed in this pull, the running systemd still has the
# old version cached, so daemon-reload + restart picks up both.
if ! diff -q /etc/systemd/system/harvest-post.service ~/harvest_post/harvest-post.service > /dev/null 2>&1; then
    echo "[gpu] systemd unit changed, updating /etc/systemd/system/"
    sudo -n cp ~/harvest_post/harvest-post.service /etc/systemd/system/harvest-post.service
    sudo -n systemctl daemon-reload
fi
echo "[gpu] systemctl start harvest-post.service (runs run.sh with fresh code)"
sudo -n systemctl reset-failed harvest-post.service 2>/dev/null || true
# --no-block: dispatch the start job and return immediately. run.sh takes
# 5-10 minutes (docker compose up + vLLM cold start + queue drain +
# shutdown) which is far beyond the Cloudflare Tunnel ~100s timeout
# between GitHub Actions and the webhook. We return quickly from the
# deploy script so CI gets its "ok:true" response promptly, while
# systemd carries run.sh to completion in the background on the GPU.
sudo -n systemctl start --no-block harvest-post.service
echo "[gpu] systemd start dispatched (non-blocking)"
REMOTE

log "deploy complete"
