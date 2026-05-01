#!/bin/bash
# 매일 새벽 1시 recommender 배치 트리거 (launchd 호출).
# launchd 환경은 PATH 가 비어있으니 명시. colima 컨텍스트도 명시.
set -euo pipefail

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"

INFRA_DIR="/Users/bite-server/projects/infra"
LOG_DIR="$HOME/logs/recommender"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/$(date +%Y-%m-%d).log"

{
  echo "=== $(date '+%Y-%m-%d %H:%M:%S') start ==="
  cd "$INFRA_DIR"
  docker context use colima >/dev/null 2>&1 || true
  docker compose --profile batch run --rm recommender
  echo "=== $(date '+%Y-%m-%d %H:%M:%S') done (exit $?) ==="
} >> "$LOG_FILE" 2>&1
