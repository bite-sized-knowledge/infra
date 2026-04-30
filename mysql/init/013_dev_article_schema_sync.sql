-- =============================================
-- bite_dev.article schema sync — bite 와 drift 정정
-- =============================================
-- bite 에는 quality_score / difficulty / content_type / summary / prompt_version 가 있는데
-- bite_dev 에는 없어 recommender global_ranking 등 dev 검증이 깨졌다. 5개 컬럼 보강.
--
-- 적용 (bite_dev 만 — bite 는 이미 동일 컬럼 보유):
--   PW=$(doppler secrets get MYSQL_ROOT_PASSWORD --plain --project infra --config prd)
--   docker exec -i bite-mysql mysql -u root -p"$PW" < mysql/init/013_dev_article_schema_sync.sql
--
-- INFORMATION_SCHEMA 체크 + PREPARE 로 멱등.

-- quality_score
SET @col_exists := (SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS
  WHERE TABLE_SCHEMA = 'bite_dev' AND TABLE_NAME = 'article' AND COLUMN_NAME = 'quality_score');
SET @sql := IF(@col_exists = 0,
  'ALTER TABLE bite_dev.article ADD COLUMN quality_score TINYINT NULL AFTER lang',
  'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- difficulty
SET @col_exists := (SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS
  WHERE TABLE_SCHEMA = 'bite_dev' AND TABLE_NAME = 'article' AND COLUMN_NAME = 'difficulty');
SET @sql := IF(@col_exists = 0,
  'ALTER TABLE bite_dev.article ADD COLUMN difficulty TINYINT NULL AFTER quality_score',
  'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- content_type
SET @col_exists := (SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS
  WHERE TABLE_SCHEMA = 'bite_dev' AND TABLE_NAME = 'article' AND COLUMN_NAME = 'content_type');
SET @sql := IF(@col_exists = 0,
  'ALTER TABLE bite_dev.article ADD COLUMN content_type VARCHAR(20) NULL AFTER difficulty',
  'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- summary
SET @col_exists := (SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS
  WHERE TABLE_SCHEMA = 'bite_dev' AND TABLE_NAME = 'article' AND COLUMN_NAME = 'summary');
SET @sql := IF(@col_exists = 0,
  'ALTER TABLE bite_dev.article ADD COLUMN summary VARCHAR(500) NULL AFTER content_type',
  'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- prompt_version
SET @col_exists := (SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS
  WHERE TABLE_SCHEMA = 'bite_dev' AND TABLE_NAME = 'article' AND COLUMN_NAME = 'prompt_version');
SET @sql := IF(@col_exists = 0,
  'ALTER TABLE bite_dev.article ADD COLUMN prompt_version VARCHAR(20) NULL AFTER summary',
  'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;
