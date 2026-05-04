-- 017_article_rejected_collation.sql
--
-- article_rejected 의 모든 텍스트 컬럼이 MySQL 8 default 인 utf8mb4_0900_ai_ci 로
-- 만들어져 있어 article / article_queue (utf8mb4_unicode_ci, article_id 는
-- utf8mb4_bin) 와 cross-table 비교 시 'Illegal mix of collations' 발생.
--
-- 영향 사례 (2026-05-04 발견):
--   harvester-go IsExistArticle 가 dedup 후보에서 article_rejected 를 누락한
--   결정적 이유 중 하나. 추가하려고 하면 url/article_id 비교에서 즉시 1267 에러.
--   그래서 dedup 강화 패치(harvester-go fix/dedup-rejected) 와 짝으로 이 ALTER 가
--   필수.
--
-- 적용:
--   PW=$(docker exec bite-mysql printenv MYSQL_ROOT_PASSWORD)
--   docker exec -i bite-mysql mysql -u root -p"$PW" \
--     < /Users/bite-server/projects/infra/mysql/init/017_article_rejected_collation.sql
--
-- 멱등: 이미 목표 collation 인 컬럼은 skip. 데이터는 ASCII URL 위주라 변환 손실
-- 없음 (한글 title/description 도 utf8mb4 안에서 collation 만 바뀌므로 동일).

-- ===== bite =====
SET @col_collation := (SELECT COLLATION_NAME FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA='bite' AND TABLE_NAME='article_rejected' AND COLUMN_NAME='article_id');
SET @sql := IF(@col_collation <> 'utf8mb4_bin',
  'ALTER TABLE bite.article_rejected MODIFY COLUMN article_id char(27) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin NOT NULL',
  'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @col_collation := (SELECT COLLATION_NAME FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA='bite' AND TABLE_NAME='article_rejected' AND COLUMN_NAME='url');
SET @sql := IF(@col_collation <> 'utf8mb4_unicode_ci',
  'ALTER TABLE bite.article_rejected MODIFY COLUMN url varchar(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci',
  'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @col_collation := (SELECT COLLATION_NAME FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA='bite' AND TABLE_NAME='article_rejected' AND COLUMN_NAME='title');
SET @sql := IF(@col_collation <> 'utf8mb4_unicode_ci',
  'ALTER TABLE bite.article_rejected MODIFY COLUMN title varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci',
  'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @col_collation := (SELECT COLLATION_NAME FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA='bite' AND TABLE_NAME='article_rejected' AND COLUMN_NAME='thumbnail');
SET @sql := IF(@col_collation <> 'utf8mb4_unicode_ci',
  'ALTER TABLE bite.article_rejected MODIFY COLUMN thumbnail varchar(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci',
  'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @col_collation := (SELECT COLLATION_NAME FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA='bite' AND TABLE_NAME='article_rejected' AND COLUMN_NAME='description');
SET @sql := IF(@col_collation <> 'utf8mb4_unicode_ci',
  'ALTER TABLE bite.article_rejected MODIFY COLUMN description varchar(1000) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci',
  'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @col_collation := (SELECT COLLATION_NAME FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA='bite' AND TABLE_NAME='article_rejected' AND COLUMN_NAME='content');
SET @sql := IF(@col_collation <> 'utf8mb4_unicode_ci',
  'ALTER TABLE bite.article_rejected MODIFY COLUMN content longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci',
  'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @col_collation := (SELECT COLLATION_NAME FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA='bite' AND TABLE_NAME='article_rejected' AND COLUMN_NAME='lang');
SET @sql := IF(@col_collation <> 'utf8mb4_unicode_ci',
  'ALTER TABLE bite.article_rejected MODIFY COLUMN lang varchar(10) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci',
  'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @col_collation := (SELECT COLLATION_NAME FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA='bite' AND TABLE_NAME='article_rejected' AND COLUMN_NAME='reject_reason');
SET @sql := IF(@col_collation <> 'utf8mb4_unicode_ci',
  'ALTER TABLE bite.article_rejected MODIFY COLUMN reject_reason varchar(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL',
  'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- 테이블 default collation 도 맞춰 future ADD COLUMN 이 0900_ai_ci 로 되돌아가지 않게.
SET @tbl_collation := (SELECT TABLE_COLLATION FROM INFORMATION_SCHEMA.TABLES
    WHERE TABLE_SCHEMA='bite' AND TABLE_NAME='article_rejected');
SET @sql := IF(@tbl_collation <> 'utf8mb4_unicode_ci',
  'ALTER TABLE bite.article_rejected DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci',
  'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;


-- ===== bite_dev =====
SET @col_collation := (SELECT COLLATION_NAME FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA='bite_dev' AND TABLE_NAME='article_rejected' AND COLUMN_NAME='article_id');
SET @sql := IF(@col_collation <> 'utf8mb4_bin',
  'ALTER TABLE bite_dev.article_rejected MODIFY COLUMN article_id char(27) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin NOT NULL',
  'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @col_collation := (SELECT COLLATION_NAME FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA='bite_dev' AND TABLE_NAME='article_rejected' AND COLUMN_NAME='url');
SET @sql := IF(@col_collation <> 'utf8mb4_unicode_ci',
  'ALTER TABLE bite_dev.article_rejected MODIFY COLUMN url varchar(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci',
  'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @col_collation := (SELECT COLLATION_NAME FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA='bite_dev' AND TABLE_NAME='article_rejected' AND COLUMN_NAME='title');
SET @sql := IF(@col_collation <> 'utf8mb4_unicode_ci',
  'ALTER TABLE bite_dev.article_rejected MODIFY COLUMN title varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci',
  'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @col_collation := (SELECT COLLATION_NAME FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA='bite_dev' AND TABLE_NAME='article_rejected' AND COLUMN_NAME='thumbnail');
SET @sql := IF(@col_collation <> 'utf8mb4_unicode_ci',
  'ALTER TABLE bite_dev.article_rejected MODIFY COLUMN thumbnail varchar(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci',
  'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @col_collation := (SELECT COLLATION_NAME FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA='bite_dev' AND TABLE_NAME='article_rejected' AND COLUMN_NAME='description');
SET @sql := IF(@col_collation <> 'utf8mb4_unicode_ci',
  'ALTER TABLE bite_dev.article_rejected MODIFY COLUMN description varchar(1000) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci',
  'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @col_collation := (SELECT COLLATION_NAME FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA='bite_dev' AND TABLE_NAME='article_rejected' AND COLUMN_NAME='content');
SET @sql := IF(@col_collation <> 'utf8mb4_unicode_ci',
  'ALTER TABLE bite_dev.article_rejected MODIFY COLUMN content longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci',
  'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @col_collation := (SELECT COLLATION_NAME FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA='bite_dev' AND TABLE_NAME='article_rejected' AND COLUMN_NAME='lang');
SET @sql := IF(@col_collation <> 'utf8mb4_unicode_ci',
  'ALTER TABLE bite_dev.article_rejected MODIFY COLUMN lang varchar(10) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci',
  'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @col_collation := (SELECT COLLATION_NAME FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA='bite_dev' AND TABLE_NAME='article_rejected' AND COLUMN_NAME='reject_reason');
SET @sql := IF(@col_collation <> 'utf8mb4_unicode_ci',
  'ALTER TABLE bite_dev.article_rejected MODIFY COLUMN reject_reason varchar(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL',
  'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @tbl_collation := (SELECT TABLE_COLLATION FROM INFORMATION_SCHEMA.TABLES
    WHERE TABLE_SCHEMA='bite_dev' AND TABLE_NAME='article_rejected');
SET @sql := IF(@tbl_collation <> 'utf8mb4_unicode_ci',
  'ALTER TABLE bite_dev.article_rejected DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci',
  'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;
