#!/bin/bash
# Docker cleanup: remove unused images older than 7 days
# Runs daily via cron

LOG_FILE="/Users/bite-server/projects/infra/logs/docker-cleanup.log"
mkdir -p "$(dirname "$LOG_FILE")"

{
  echo "=== Docker cleanup: $(date '+%Y-%m-%d %H:%M:%S') ==="

  # Remove stopped containers older than 7 days
  docker container prune -f --filter "until=168h" 2>&1

  # Remove unused images older than 7 days (keeps images used by running containers)
  docker image prune -a -f --filter "until=168h" 2>&1

  # Remove dangling build cache
  docker builder prune -f --filter "until=168h" 2>&1

  # Show remaining disk usage
  docker system df 2>&1

  # --- GHCR cleanup: delete untagged + old versions ---
  echo ""
  echo "=== GHCR cleanup ==="
  ORG="bite-sized-knowledge"
  KEEP_TAGS="latest|dev"
  RETENTION_DAYS=7
  CUTOFF=$(date -v-${RETENTION_DAYS}d -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
        || date -u -d "${RETENTION_DAYS} days ago" +%Y-%m-%dT%H:%M:%SZ)

  for PKG in bite-api bite-web harvester-go recsys-serving recommender; do
    echo "--- $PKG ---"
    VERSIONS=$(gh api "orgs/$ORG/packages/container/$PKG/versions?per_page=100" --paginate 2>/dev/null) || continue

    echo "$VERSIONS" | python3 -c "
import json, sys
data = json.load(sys.stdin)
cutoff = '$CUTOFF'
keep = {'latest', 'dev'}
deleted = 0
for v in data:
    tags = v.get('metadata', {}).get('container', {}).get('tags', [])
    if any(t in keep for t in tags):
        continue
    if v['created_at'] > cutoff:
        continue
    print(v['id'])
" | while read -r VID; do
      gh api --method DELETE "orgs/$ORG/packages/container/$PKG/versions/$VID" 2>&1 && echo "  deleted version $VID"
    done
  done

  echo "=== Done ==="
  echo ""
} >> "$LOG_FILE" 2>&1
