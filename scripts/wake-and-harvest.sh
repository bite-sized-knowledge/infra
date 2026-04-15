#!/bin/bash
# Mac cron에서 3시간마다 실행
# article_queue가 비어있으면 GPU를 깨우지 않음

export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

# Load MYSQL_PASSWORD from .env
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
if [ -z "$MYSQL_PASSWORD" ] && [ -f "$SCRIPT_DIR/.env" ]; then
    MYSQL_PASSWORD=$(grep '^MYSQL_PASSWORD=' "$SCRIPT_DIR/.env" | cut -d'=' -f2- | tr -d '"')
    export MYSQL_PASSWORD
fi

LOG="/tmp/wake-and-harvest.log"
GPU_MAC="70:85:c2:a8:ad:b2"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG"
}

# article_queue 건수 확인 (운영계)
MYSQL_OUT=$(docker exec bite-mysql mysql -ubite-dev -p"${MYSQL_PASSWORD:?}" bite -N -e "SELECT COUNT(*) FROM article_queue;" 2>&1)
DOCKER_EXIT=$?
QUEUE_COUNT=$(echo "$MYSQL_OUT" | grep -E '^[0-9]+$' | head -1)

if [ $DOCKER_EXIT -ne 0 ] || [ -z "$QUEUE_COUNT" ]; then
    log "ERROR - docker/mysql failed (exit=$DOCKER_EXIT): $MYSQL_OUT"
    exit 1
fi

if [ -z "$QUEUE_COUNT" ] || [ "$QUEUE_COUNT" -eq 0 ]; then
    log "SKIP - article_queue is empty ($QUEUE_COUNT)"
    exit 0
fi

log "WAKE - $QUEUE_COUNT articles in queue, sending WoL"
/opt/homebrew/bin/wakeonlan "$GPU_MAC" >> "$LOG" 2>&1
