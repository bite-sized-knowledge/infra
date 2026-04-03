#!/bin/bash
set -euo pipefail

WORKDIR="$(cd "$(dirname "$0")" && pwd)"
EXPECTED_DEFAULT_SERVICES=(mysql qdrant recsys-api bite-api bite-api-dev bite-web bite-web-dev harvester-go cloudflared backup deploy-webhook)
EXPECTED_BATCH_SERVICES=(mysql qdrant recsys-api bite-api bite-api-dev bite-web bite-web-dev harvester-go cloudflared backup deploy-webhook recommender)

if docker compose version >/dev/null 2>&1; then
  COMPOSE_CMD=(docker compose)
else
  COMPOSE_CMD=(docker-compose)
fi

verify_services() {
  local mode="$1"
  local services_str="$2"
  shift 2
  local -a expected=("$@")

  local -a actual=()
  while IFS= read -r line; do
    actual+=("$line")
  done <<EOF
$services_str
EOF

  if [ "${#actual[@]}" -ne "${#expected[@]}" ]; then
    echo "[$mode] unexpected service count: ${#actual[@]}"
    printf '[%s] actual: %s\n' "$mode" "${actual[@]}"
    exit 1
  fi

  for expected_service in "${expected[@]}"; do
    local found=false
    for actual_service in "${actual[@]}"; do
      if [ "$actual_service" = "$expected_service" ]; then
        found=true
        break
      fi
    done
    if [ "$found" = false ]; then
      echo "[$mode] missing expected service: $expected_service"
      exit 1
    fi
  done
}

DEFAULT_SERVICES_STR="$(cd "$WORKDIR" && "${COMPOSE_CMD[@]}" config --services)"
BATCH_SERVICES_STR="$(cd "$WORKDIR" && "${COMPOSE_CMD[@]}" --profile batch config --services)"

verify_services "default" "$DEFAULT_SERVICES_STR" "${EXPECTED_DEFAULT_SERVICES[@]}"
verify_services "batch" "$BATCH_SERVICES_STR" "${EXPECTED_BATCH_SERVICES[@]}"

echo "compose services verified (default + batch profile)"
