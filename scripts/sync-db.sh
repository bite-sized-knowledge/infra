#!/bin/bash
# bite 운영계 → bite_dev 개발계 DB 동기화
set -euo pipefail

CONTAINER="bite-mysql"
SRC_DB="bite"
DST_DB="bite_dev"
MYSQL_USER="root"
MYSQL_PASS="qkdlxm!"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] DB 동기화 시작: ${SRC_DB} → ${DST_DB}"

# 1. 개발계 테이블 전부 DROP
docker exec "$CONTAINER" mysql -u"$MYSQL_USER" -p"$MYSQL_PASS" "$DST_DB" -e "
SET FOREIGN_KEY_CHECKS = 0;
SET @tables = NULL;
SELECT GROUP_CONCAT(table_name) INTO @tables FROM information_schema.tables WHERE table_schema = '${DST_DB}';
SET @tables = IFNULL(CONCAT('DROP TABLE ', @tables), 'SELECT 1');
PREPARE stmt FROM @tables;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;
SET FOREIGN_KEY_CHECKS = 1;
" 2>/dev/null

# 2. 운영계 덤프 → 개발계 import (스키마 + 데이터)
docker exec "$CONTAINER" mysqldump -u"$MYSQL_USER" -p"$MYSQL_PASS" "$SRC_DB" 2>/dev/null \
  | docker exec -i "$CONTAINER" mysql -u"$MYSQL_USER" -p"$MYSQL_PASS" "$DST_DB" 2>/dev/null

echo "[$(date '+%Y-%m-%d %H:%M:%S')] DB 동기화 완료"

# 3. 로그 3개월치만 유지
LOG_FILE="/tmp/sync-db.log"
if [ -f "$LOG_FILE" ]; then
  CUTOFF=$(date -v-3m '+%Y-%m-%d')
  awk -v cutoff="$CUTOFF" '$0 ~ /^\[/ { d=substr($0,2,10); if(d >= cutoff) print; next } { print }' "$LOG_FILE" > "${LOG_FILE}.tmp" && mv "${LOG_FILE}.tmp" "$LOG_FILE"
fi
