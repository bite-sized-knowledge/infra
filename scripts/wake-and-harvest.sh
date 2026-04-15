#!/bin/bash
# Mac cron에서 3시간마다 실행
# article_queue가 비어있으면 GPU를 깨우지 않음
# GPU 깨운 후 처리 완료까지 대기하고 결과를 로그에 기록

export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

# Load MYSQL_PASSWORD from .env
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
if [ -z "$MYSQL_PASSWORD" ] && [ -f "$SCRIPT_DIR/.env" ]; then
    MYSQL_PASSWORD=$(grep '^MYSQL_PASSWORD=' "$SCRIPT_DIR/.env" | cut -d'=' -f2- | tr -d '"')
    export MYSQL_PASSWORD
fi

LOG="/tmp/wake-and-harvest.log"
GPU_MAC="70:85:c2:a8:ad:b2"
GPU_HOST="192.168.219.101"
GPU_USER="siroo"
SSH_KEY="$HOME/.ssh/deploy_ed25519"
MAX_WAIT=3600  # 최대 60분 대기

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG"
}

get_queue_count() {
    docker exec bite-mysql mysql -ubite-dev -p"${MYSQL_PASSWORD}" bite -N -e "SELECT COUNT(*) FROM article_queue;" 2>/dev/null | grep -E '^[0-9]+$' | head -1
}

get_article_count() {
    docker exec bite-mysql mysql -ubite-dev -p"${MYSQL_PASSWORD}" bite -N -e "SELECT COUNT(*) FROM article;" 2>/dev/null | grep -E '^[0-9]+$' | head -1
}

get_rejected_count() {
    docker exec bite-mysql mysql -ubite-dev -p"${MYSQL_PASSWORD}" bite -N -e "SELECT COUNT(*) FROM article_rejected;" 2>/dev/null | grep -E '^[0-9]+$' | head -1
}

gpu_reachable() {
    ssh -o ConnectTimeout=3 -o BatchMode=yes -o StrictHostKeyChecking=no -i "$SSH_KEY" "$GPU_USER@$GPU_HOST" echo ok >/dev/null 2>&1
}

# --- 1. Queue 확인 ---
QUEUE_COUNT=$(get_queue_count)

if [ -z "$QUEUE_COUNT" ]; then
    log "ERROR - mysql query failed"
    exit 1
fi

if [ "$QUEUE_COUNT" -eq 0 ]; then
    # GPU가 켜져있으면 상태 기록
    if gpu_reachable; then
        log "SKIP - queue empty, GPU online (idle)"
    else
        log "SKIP - queue empty"
    fi
    exit 0
fi

# --- 2. 처리 전 상태 기록 ---
ARTICLES_BEFORE=$(get_article_count)
REJECTED_BEFORE=$(get_rejected_count)
log "WAKE - queue=$QUEUE_COUNT, articles=$ARTICLES_BEFORE, rejected=$REJECTED_BEFORE"

# --- 3. GPU 깨우기 (이미 켜져있으면 스킵) ---
if gpu_reachable; then
    log "GPU already online, skipping WoL"
else
    /opt/homebrew/bin/wakeonlan "$GPU_MAC" >> "$LOG" 2>&1

    # SSH 대기 (최대 2분)
    WAITED=0
    while [ $WAITED -lt 120 ]; do
        sleep 10
        WAITED=$((WAITED + 10))
        if gpu_reachable; then
            log "GPU online after ${WAITED}s"
            break
        fi
    done

    if ! gpu_reachable; then
        log "ERROR - GPU did not come online after 120s"
        exit 1
    fi
fi

# --- 4. 처리 완료 대기 ---
# harvest-post는 systemd로 자동 시작, queue가 빌 때까지 대기
ELAPSED=0
while [ $ELAPSED -lt $MAX_WAIT ]; do
    sleep 60
    ELAPSED=$((ELAPSED + 60))

    CURRENT_QUEUE=$(get_queue_count)
    if [ -z "$CURRENT_QUEUE" ]; then
        log "WAIT - ${ELAPSED}s elapsed, mysql query failed"
        continue
    fi

    if [ "$CURRENT_QUEUE" -eq 0 ]; then
        ARTICLES_AFTER=$(get_article_count)
        REJECTED_AFTER=$(get_rejected_count)
        PUBLISHED=$((ARTICLES_AFTER - ARTICLES_BEFORE))
        REJECTED=$((REJECTED_AFTER - REJECTED_BEFORE))
        log "DONE - queue cleared in ${ELAPSED}s: +${PUBLISHED} published, +${REJECTED} rejected"
        exit 0
    fi

    # 5분마다 진행상황 로그
    if [ $((ELAPSED % 300)) -eq 0 ]; then
        PROCESSED=$((QUEUE_COUNT - CURRENT_QUEUE))
        log "WAIT - ${ELAPSED}s elapsed, ${CURRENT_QUEUE} remaining (${PROCESSED} processed)"
    fi
done

# 타임아웃
CURRENT_QUEUE=$(get_queue_count)
ARTICLES_AFTER=$(get_article_count)
REJECTED_AFTER=$(get_rejected_count)
PUBLISHED=$((ARTICLES_AFTER - ARTICLES_BEFORE))
REJECTED=$((REJECTED_AFTER - REJECTED_BEFORE))
log "TIMEOUT - ${MAX_WAIT}s, queue=${CURRENT_QUEUE} remaining, +${PUBLISHED} published, +${REJECTED} rejected"
