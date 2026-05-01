-- =============================================
-- Recsys Phase 1.6: impression 에 backfilled flag + latency_ms
-- =============================================
-- 회피 항목 3 (backfill_ratio) + 4 (recommend latency 일별 누적) 의 source.
--
-- recommender metric_rollup 가 매일 다음을 계산:
--   - backfill_ratio = SUM(was_backfilled) / COUNT(*)
--   - recommend_latency_p50_ms / recommend_latency_p95_ms = percentile(latency_ms)
--
-- INFORMATION_SCHEMA 체크 + PREPARE 멱등. bite + bite_dev 양쪽.

-- recommendation_impression.was_backfilled
SET @col_exists := (SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS
  WHERE TABLE_SCHEMA = 'bite' AND TABLE_NAME = 'recommendation_impression' AND COLUMN_NAME = 'was_backfilled');
SET @sql := IF(@col_exists = 0,
  'ALTER TABLE bite.recommendation_impression ADD COLUMN was_backfilled TINYINT(1) NOT NULL DEFAULT 0 AFTER bandit_theta',
  'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @col_exists := (SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS
  WHERE TABLE_SCHEMA = 'bite_dev' AND TABLE_NAME = 'recommendation_impression' AND COLUMN_NAME = 'was_backfilled');
SET @sql := IF(@col_exists = 0,
  'ALTER TABLE bite_dev.recommendation_impression ADD COLUMN was_backfilled TINYINT(1) NOT NULL DEFAULT 0 AFTER bandit_theta',
  'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- recommendation_impression.latency_ms — 응답 단위 latency (같은 feed_request_id 내 모든 row 동일)
SET @col_exists := (SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS
  WHERE TABLE_SCHEMA = 'bite' AND TABLE_NAME = 'recommendation_impression' AND COLUMN_NAME = 'latency_ms');
SET @sql := IF(@col_exists = 0,
  'ALTER TABLE bite.recommendation_impression ADD COLUMN latency_ms INT NULL AFTER was_backfilled',
  'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @col_exists := (SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS
  WHERE TABLE_SCHEMA = 'bite_dev' AND TABLE_NAME = 'recommendation_impression' AND COLUMN_NAME = 'latency_ms');
SET @sql := IF(@col_exists = 0,
  'ALTER TABLE bite_dev.recommendation_impression ADD COLUMN latency_ms INT NULL AFTER was_backfilled',
  'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- recommendation_metric_daily.recommend_latency_p50_ms / p95_ms
SET @col_exists := (SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS
  WHERE TABLE_SCHEMA = 'bite' AND TABLE_NAME = 'recommendation_metric_daily' AND COLUMN_NAME = 'recommend_latency_p50_ms');
SET @sql := IF(@col_exists = 0,
  'ALTER TABLE bite.recommendation_metric_daily
     ADD COLUMN recommend_latency_p50_ms DOUBLE NULL AFTER backfill_ratio,
     ADD COLUMN recommend_latency_p95_ms DOUBLE NULL AFTER recommend_latency_p50_ms',
  'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @col_exists := (SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS
  WHERE TABLE_SCHEMA = 'bite_dev' AND TABLE_NAME = 'recommendation_metric_daily' AND COLUMN_NAME = 'recommend_latency_p50_ms');
SET @sql := IF(@col_exists = 0,
  'ALTER TABLE bite_dev.recommendation_metric_daily
     ADD COLUMN recommend_latency_p50_ms DOUBLE NULL AFTER backfill_ratio,
     ADD COLUMN recommend_latency_p95_ms DOUBLE NULL AFTER recommend_latency_p50_ms',
  'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;
