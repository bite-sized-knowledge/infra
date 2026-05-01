#!/bin/bash
# Mac cron: 매주 일요일 03:00 KST (`0 3 * * 0`).
# article_queue가 비어있을 때만 GPU를 깨워서 judge backfill 실행.
# (큐 차있으면 harvest 우선이라 backfill 건너뜀 — 다음 주에 다시 시도.)
#
# 실제 backfill 로직은 GPU의 ~/harvest_post/scripts/run-weekly-backfill.sh.
# 이 스크립트는 wake + queue check + ssh trigger 만 담당.

set -uo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

LOCKDIR_SELF="/tmp/wake-and-backfill.lock"
LOCKDIR_HARVEST="/tmp/wake-and-harvest.lock"

# 자기 락 (이중 실행 방지)
if ! mkdir "$LOCKDIR_SELF" 2>/dev/null; then
    AGE=$(( $(date +%s) - $(stat -f %m "$LOCKDIR_SELF") ))
    if [ "$AGE" -gt 7200 ]; then
        rmdir "$LOCKDIR_SELF" 2>/dev/null
        mkdir "$LOCKDIR_SELF" 2>/dev/null || exit 0
    else
        exit 0
    fi
fi
trap 'rmdir "$LOCKDIR_SELF" 2>/dev/null' EXIT

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LOG="$SCRIPT_DIR/logs/wake-and-backfill.log"
mkdir -p "$(dirname "$LOG")"

GPU_MAC="70:85:c2:a8:ad:b2"
GPU_HOST="124.59.179.22"
GPU_PORT=3475
GPU_USER="siroo"
SSH="ssh -o ConnectTimeout=5 -o BatchMode=yes -o StrictHostKeyChecking=no -p $GPU_PORT $GPU_USER@$GPU_HOST"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG"; }

# wake-and-harvest와 동시 실행 회피
if [ -d "$LOCKDIR_HARVEST" ]; then
    log "SKIP - wake-and-harvest 진행 중"
    exit 0
fi

# Load MYSQL_PASSWORD
if [ -z "${MYSQL_PASSWORD:-}" ] && [ -f "$SCRIPT_DIR/.env" ]; then
    MYSQL_PASSWORD=$(grep '^MYSQL_PASSWORD=' "$SCRIPT_DIR/.env" | cut -d'=' -f2- | tr -d '"')
    export MYSQL_PASSWORD
fi

QUEUE=$(docker exec bite-mysql mysql -ubite-dev -p"${MYSQL_PASSWORD}" bite -N -e "SELECT COUNT(*) FROM article_queue;" 2>/dev/null | grep -E '^[0-9]+$' | head -1)
if [ -z "$QUEUE" ]; then
    log "ERROR - mysql query failed"
    exit 1
fi
if [ "$QUEUE" -gt 0 ]; then
    log "SKIP - article_queue=$QUEUE (harvest 우선이라 backfill 건너뜀)"
    exit 0
fi

log "START - queue empty, weekly backfill 진행"

# Wake GPU if needed
if ! $SSH echo ok >/dev/null 2>&1; then
    /opt/homebrew/bin/wakeonlan "$GPU_MAC" >> "$LOG" 2>&1
    for i in $(seq 1 12); do
        sleep 10
        if $SSH echo ok >/dev/null 2>&1; then
            log "GPU online after $((i*10))s"
            break
        fi
    done
    if ! $SSH echo ok >/dev/null 2>&1; then
        log "ERROR - GPU not online after 120s"
        exit 1
    fi
else
    log "GPU already online"
fi

# 정상 사이클 정지 + 최신 코드 fetch + backfill을 background로 띄우고 ssh 끊김
$SSH "
sudo -n systemctl stop harvest-post.service 2>&1 || true
cd /home/siroo/harvest_post
git pull --rebase origin prod 2>&1 || echo 'git pull failed (계속 진행)'
chmod +x scripts/run-weekly-backfill.sh 2>/dev/null
setsid nohup bash scripts/run-weekly-backfill.sh </dev/null >/dev/null 2>&1 &
echo 'BACKFILL_PID='\$!
disown 2>/dev/null || true
"
RC=$?
log "remote backfill triggered (ssh exit=$RC). 진행 로그: GPU의 /home/siroo/logs/audit-backfill/*_weekly.log"
log "DONE"
