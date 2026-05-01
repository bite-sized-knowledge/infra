-- =============================================
-- Recsys Phase 1.5: 비회원 추천 + 언어 선호 + feed_request_id 정확 그룹핑
-- =============================================
-- 변경 묶음:
--   1. recommendation_global.lang        : 글로벌 풀 빌드 시 article.lang 그대로. 서빙 시 lang 필터.
--   2. recommendation_impression.device_id / feed_request_id
--      - device_id: 비회원 노출 식별자 (member_id 와 둘 중 하나는 NOT NULL 라는 가드는 app 단)
--      - feed_request_id: 5초 bucket 휴리스틱 대신 응답 단위 정확 그룹핑
--   3. device_category_bandit            : 비회원 카테고리 단위 Beta TS state.
--   4. recommendation_metric_daily.anonymous_*  : 비회원 KPI 분리 추적
--
-- bite + bite_dev 양쪽 멱등 (CREATE TABLE IF NOT EXISTS / INFORMATION_SCHEMA 체크).
--
-- 적용:
--   PW=$(doppler secrets get MYSQL_ROOT_PASSWORD --plain --project infra --config prd)
--   docker exec -i bite-mysql mysql -u root -p"$PW" < mysql/init/015_recsys_phase1_5.sql

-- ---------------------------------------------
-- 1. recommendation_global.lang
-- ---------------------------------------------
SET @col_exists := (SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS
  WHERE TABLE_SCHEMA = 'bite' AND TABLE_NAME = 'recommendation_global' AND COLUMN_NAME = 'lang');
SET @sql := IF(@col_exists = 0,
  'ALTER TABLE bite.recommendation_global ADD COLUMN lang VARCHAR(10) NULL AFTER category_id, ADD INDEX idx_lang_score (lang, score DESC)',
  'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @col_exists := (SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS
  WHERE TABLE_SCHEMA = 'bite_dev' AND TABLE_NAME = 'recommendation_global' AND COLUMN_NAME = 'lang');
SET @sql := IF(@col_exists = 0,
  'ALTER TABLE bite_dev.recommendation_global ADD COLUMN lang VARCHAR(10) NULL AFTER category_id, ADD INDEX idx_lang_score (lang, score DESC)',
  'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- ---------------------------------------------
-- 2-a. recommendation_impression.device_id
-- ---------------------------------------------
SET @col_exists := (SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS
  WHERE TABLE_SCHEMA = 'bite' AND TABLE_NAME = 'recommendation_impression' AND COLUMN_NAME = 'device_id');
SET @sql := IF(@col_exists = 0,
  'ALTER TABLE bite.recommendation_impression
     MODIFY COLUMN member_id BIGINT NULL,
     ADD COLUMN device_id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NULL AFTER member_id,
     ADD INDEX idx_device_shown (device_id, shown_at DESC),
     ADD INDEX idx_device_article (device_id, article_id, shown_at DESC)',
  'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @col_exists := (SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS
  WHERE TABLE_SCHEMA = 'bite_dev' AND TABLE_NAME = 'recommendation_impression' AND COLUMN_NAME = 'device_id');
SET @sql := IF(@col_exists = 0,
  'ALTER TABLE bite_dev.recommendation_impression
     MODIFY COLUMN member_id BIGINT NULL,
     ADD COLUMN device_id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NULL AFTER member_id,
     ADD INDEX idx_device_shown (device_id, shown_at DESC),
     ADD INDEX idx_device_article (device_id, article_id, shown_at DESC)',
  'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- ---------------------------------------------
-- 2-b. recommendation_impression.feed_request_id
-- ---------------------------------------------
SET @col_exists := (SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS
  WHERE TABLE_SCHEMA = 'bite' AND TABLE_NAME = 'recommendation_impression' AND COLUMN_NAME = 'feed_request_id');
SET @sql := IF(@col_exists = 0,
  'ALTER TABLE bite.recommendation_impression
     ADD COLUMN feed_request_id CHAR(32) NULL AFTER position,
     ADD INDEX idx_feed_request (feed_request_id)',
  'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @col_exists := (SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS
  WHERE TABLE_SCHEMA = 'bite_dev' AND TABLE_NAME = 'recommendation_impression' AND COLUMN_NAME = 'feed_request_id');
SET @sql := IF(@col_exists = 0,
  'ALTER TABLE bite_dev.recommendation_impression
     ADD COLUMN feed_request_id CHAR(32) NULL AFTER position,
     ADD INDEX idx_feed_request (feed_request_id)',
  'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- ---------------------------------------------
-- 3. device_category_bandit (비회원 Beta TS state)
-- ---------------------------------------------
-- member 테이블에 row 없는 비회원의 카테고리 단위 학습 상태.
-- lazy guest 발급(첫 FK action) 시점에는 데이터 마이그레이션 안 함 — 새 member 는 prior 부터.
-- 비회원 흔적은 분석용으로 보존.
CREATE TABLE IF NOT EXISTS bite.device_category_bandit (
    device_id     CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    category_id   BIGINT NOT NULL,
    alpha         DOUBLE NOT NULL DEFAULT 1.0,
    beta          DOUBLE NOT NULL DEFAULT 1.0,
    impressions   INT NOT NULL DEFAULT 0,
    clicks        INT NOT NULL DEFAULT 0,
    last_updated  TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    created_at    TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (device_id, category_id),
    INDEX idx_device_updated (device_id, last_updated)
);

CREATE TABLE IF NOT EXISTS bite_dev.device_category_bandit (
    device_id     CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    category_id   BIGINT NOT NULL,
    alpha         DOUBLE NOT NULL DEFAULT 1.0,
    beta          DOUBLE NOT NULL DEFAULT 1.0,
    impressions   INT NOT NULL DEFAULT 0,
    clicks        INT NOT NULL DEFAULT 0,
    last_updated  TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    created_at    TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (device_id, category_id),
    INDEX idx_device_updated (device_id, last_updated)
);

-- ---------------------------------------------
-- 4. recommendation_metric_daily 의 비회원 분리 KPI
-- ---------------------------------------------
SET @col_exists := (SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS
  WHERE TABLE_SCHEMA = 'bite' AND TABLE_NAME = 'recommendation_metric_daily' AND COLUMN_NAME = 'anonymous_impressions');
SET @sql := IF(@col_exists = 0,
  'ALTER TABLE bite.recommendation_metric_daily
     ADD COLUMN anonymous_impressions BIGINT NOT NULL DEFAULT 0 AFTER impressions,
     ADD COLUMN anonymous_clicks      BIGINT NOT NULL DEFAULT 0 AFTER clicks,
     ADD COLUMN anonymous_ctr         DOUBLE NULL AFTER ctr,
     ADD COLUMN anonymous_active_devices INT NOT NULL DEFAULT 0 AFTER bandit_active_users,
     ADD COLUMN backfill_ratio        DOUBLE NULL AFTER cold_to_warm_users',
  'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @col_exists := (SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS
  WHERE TABLE_SCHEMA = 'bite_dev' AND TABLE_NAME = 'recommendation_metric_daily' AND COLUMN_NAME = 'anonymous_impressions');
SET @sql := IF(@col_exists = 0,
  'ALTER TABLE bite_dev.recommendation_metric_daily
     ADD COLUMN anonymous_impressions BIGINT NOT NULL DEFAULT 0 AFTER impressions,
     ADD COLUMN anonymous_clicks      BIGINT NOT NULL DEFAULT 0 AFTER clicks,
     ADD COLUMN anonymous_ctr         DOUBLE NULL AFTER ctr,
     ADD COLUMN anonymous_active_devices INT NOT NULL DEFAULT 0 AFTER bandit_active_users,
     ADD COLUMN backfill_ratio        DOUBLE NULL AFTER cold_to_warm_users',
  'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- ---------------------------------------------
-- 5. member.lang (선택) — 사용자별 언어 선호 (NULL = 모두 OK)
-- ---------------------------------------------
SET @col_exists := (SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS
  WHERE TABLE_SCHEMA = 'bite' AND TABLE_NAME = 'member' AND COLUMN_NAME = 'lang');
SET @sql := IF(@col_exists = 0,
  'ALTER TABLE bite.member ADD COLUMN lang VARCHAR(10) NULL AFTER device_id',
  'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @col_exists := (SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS
  WHERE TABLE_SCHEMA = 'bite_dev' AND TABLE_NAME = 'member' AND COLUMN_NAME = 'lang');
SET @sql := IF(@col_exists = 0,
  'ALTER TABLE bite_dev.member ADD COLUMN lang VARCHAR(10) NULL AFTER device_id',
  'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;
