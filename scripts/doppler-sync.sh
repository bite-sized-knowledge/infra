#!/bin/bash
# Regenerate .env from Doppler secrets + local config.
# Run this after any Doppler secret change, before `docker compose up`.
set -euo pipefail

INFRA_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# Download secrets from Doppler
doppler secrets download \
  --project infra --config prd \
  --format env --no-file \
  > "$INFRA_DIR/.env.tmp"

# DB_PASSWORD = MYSQL_PASSWORD (alias for services that use DB_PASSWORD)
MYSQL_PW=$(grep '^MYSQL_PASSWORD=' "$INFRA_DIR/.env.tmp" | cut -d= -f2-) || { echo "ERROR: MYSQL_PASSWORD not found in Doppler"; exit 1; }
QDRANT_KEY=$(grep '^QDRANT_API_KEY=' "$INFRA_DIR/.env.tmp" | cut -d= -f2-) || { echo "ERROR: QDRANT_API_KEY not found in Doppler"; exit 1; }
echo "DB_PASSWORD=$MYSQL_PW" >> "$INFRA_DIR/.env.tmp"
echo "RDS_PASSWORD=$MYSQL_PW" >> "$INFRA_DIR/.env.tmp"
echo "QDRANT_API=$QDRANT_KEY" >> "$INFRA_DIR/.env.tmp"

# Non-secret config (not managed by Doppler)
cat >> "$INFRA_DIR/.env.tmp" <<'CONFIG'
MYSQL_DATABASE=bite
MYSQL_USER=bite-dev
DB_HOST=mysql
DB_PORT=3306
DB_NAME=bite
DB_USER=bite-dev
ENVIRONMENT=prod
PROXY_URL=
HARVEST_INTERVAL=1h
DISCORD_WEBHOOK_URL=
LOG_LEVEL=info
QDRANT_URL=http://qdrant:6333
QDRANT_COLLECTION_NAME=bite-vectordb
RECSYS_BASE_URL=http://recsys-api:8001
APP_BASE_URL=https://api.bite-sized.xyz
APP_ENV=production
EMAIL_FROM=Bite <noreply@bite-sized.xyz>
RDS_DATABASE=bite
RDS_HOST=mysql
RDS_USER=bite-dev
RDS_PORT=3306
QDRANT_ENDPOINT=http://qdrant:6333
DB_TLS_CA=/etc/ssl/mysql-ca.pem
CONFIG

mv "$INFRA_DIR/.env.tmp" "$INFRA_DIR/.env"
chmod 600 "$INFRA_DIR/.env"
echo "[$(date)] .env synced from Doppler"
