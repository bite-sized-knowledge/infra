#!/bin/bash
set -euo pipefail

WORKDIR="$(cd "$(dirname "$0")" && pwd)"
EXPECTED_SERVICES=(mysql qdrant bite-api cloudflared recsys-api backup)

ACTUAL_SERVICES_STR="$(cd "$WORKDIR" && docker-compose config --services)"
ACTUAL_SERVICES=()
while IFS= read -r line; do
  ACTUAL_SERVICES+=("$line")
done <<EOF
$ACTUAL_SERVICES_STR
EOF

if [ "${#ACTUAL_SERVICES[@]}" -ne "${#EXPECTED_SERVICES[@]}" ]; then
  echo "unexpected service count: ${#ACTUAL_SERVICES[@]}"
  printf 'actual: %s\n' "${ACTUAL_SERVICES[@]}"
  exit 1
fi

for expected in "${EXPECTED_SERVICES[@]}"; do
  found=false
  for actual in "${ACTUAL_SERVICES[@]}"; do
    if [ "$actual" = "$expected" ]; then
      found=true
      break
    fi
  done
  if [ "$found" = false ]; then
    echo "missing expected service: $expected"
    exit 1
  fi
done

echo "compose services verified"
