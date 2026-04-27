#!/bin/bash
# Sync production MySQL data to dev environment.
# Scope: item/content tables only (article, article_queue, article_rejected,
# blog, interest, llm_config_metadata). User activity tables are NOT synced.
# Qdrant is shared between prod and dev (single instance, single collection),
# so no vector sync is needed.
# Runs daily via cron at 04:00 KST.

set -euo pipefail

DOPPLER=/opt/homebrew/bin/doppler
PYTHON=/usr/bin/python3
LOG=/Users/bite-server/projects/infra/logs/sync-prod-to-dev.log
mkdir -p "$(dirname "$LOG")"

{
    echo "=== $(date '+%Y-%m-%d %H:%M:%S') sync started ==="

    cd /Users/bite-server/projects/harvest_post

    # Pull secrets from Doppler (infra/prd) — avoids fragile .env parsing.
    DB_PASSWORD="$("$DOPPLER" secrets get MYSQL_PASSWORD --project infra --config prd --plain)"

    if [ -z "$DB_PASSWORD" ]; then
        echo "[ERROR] MYSQL_PASSWORD missing in Doppler infra/prd" >&2
        exit 1
    fi

    DB_HOST=127.0.0.1 \
    DB_USER=bite-dev \
    DB_PASSWORD="$DB_PASSWORD" \
    "$PYTHON" scripts/sync_bite_to_dev.py

    echo "=== $(date '+%Y-%m-%d %H:%M:%S') sync done ==="
} >> "$LOG" 2>&1
