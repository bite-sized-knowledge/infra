#!/bin/bash
DATE=$(date +%Y%m%d_%H%M%S)
mysqldump --ssl-mode=REQUIRED -h mysql -u${MYSQL_USER} -p${MYSQL_PASSWORD} ${MYSQL_DATABASE} > /backup/bite_${DATE}.sql
# Keep only last 7 days
find /backup -name "bite_*.sql" -mtime +7 -delete
echo "[$(date)] Backup completed: bite_${DATE}.sql"
