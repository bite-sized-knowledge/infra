#!/bin/bash
# Sync production data (MySQL + Qdrant) to dev environment
# Runs daily via cron at 04:00 KST

set -euo pipefail

LOG="/Users/bite-server/projects/infra/logs/sync-prod-to-dev.log"
mkdir -p "$(dirname "$LOG")"

{
    echo "=== $(date '+%Y-%m-%d %H:%M:%S') sync started ==="

    cd /Users/bite-server/projects/harvest_post

    DB_HOST=127.0.0.1 \
    DB_USER=bite-dev \
    DB_PASSWORD="${DB_PASSWORD:?DB_PASSWORD must be set}" \
    QDRANT_PROD_PORT=6333 \
    QDRANT_DEV_PORT=6335 \
    python3 scripts/sync_bite_to_dev.py

    echo "=== $(date '+%Y-%m-%d %H:%M:%S') sync done ==="
} >> "$LOG" 2>&1
