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
REMOTE

log "deploy complete"
