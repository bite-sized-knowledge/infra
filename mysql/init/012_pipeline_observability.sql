-- =============================================
-- 012: harvest_post 파이프라인 가시성 — dead-letter + job_run + queue 상태
-- =============================================
-- 배경:
--   harvest_post가 실패한 article을 print()만 찍고 DROP하는 구조라
--   "오늘 뭐가 왜 실패했는지" 사후 추적이 불가했음. monitor 또한
--   article_queue/article 단순 COUNT만 보여줄 뿐 job 단위 가시성 없음.
--
-- 본 마이그레이션:
--   1. article_failed: ProcessingError(permanent) / 임베딩 실패 등 영구 실패 dead-letter.
--      payload(JSON)에 원본 queue row를 보존해 추후 replay 가능.
--   2. job_run: harvest_post / audit_rejected / recover_rejected 매 실행의 시작/종료/카운터/단계별 분포.
--   3. article_queue: status / attempt_count / last_error / last_attempted_at 컬럼 활성화 (기존 컬럼 없음 — 신규 추가).
--
-- 적용:
--   - 신규 컨테이너: docker-entrypoint-initdb.d 자동 실행
--   - 기존 컨테이너:
--       PW=$(grep '^MYSQL_PASSWORD=' /Users/bite-server/projects/infra/.env | cut -d'=' -f2-)
--       docker exec -i bite-mysql mysql -u root -p"$PW" \
--         < /Users/bite-server/projects/infra/mysql/init/012_pipeline_observability.sql
--
-- 멱등성: 모든 ALTER가 INFORMATION_SCHEMA 사전 체크. 재실행 안전.
-- =============================================

-- -------------------------------------------------------------------
-- 1. article_failed (dead-letter)
-- -------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS bite.article_failed (
    id              BIGINT AUTO_INCREMENT PRIMARY KEY,
    article_id      CHAR(27) COLLATE utf8mb4_bin NULL,
    blog_id         BIGINT NULL,
    url             VARCHAR(500) NULL,
    title           VARCHAR(255) NULL,
    job_id          BIGINT NULL,
    stage           VARCHAR(32)  NOT NULL,
    error_category  VARCHAR(32)  NULL,
    error_severity  VARCHAR(16)  NULL,
    error_class     VARCHAR(128) NULL,
    error_message   TEXT         NULL,
    traceback       TEXT         NULL,
    payload         JSON         NULL,
    failed_at       TIMESTAMP    DEFAULT CURRENT_TIMESTAMP,
    retried_at      TIMESTAMP    NULL,
    INDEX idx_failed_at  (failed_at),
    INDEX idx_stage      (stage, failed_at),
    INDEX idx_article    (article_id),
    INDEX idx_job        (job_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS bite_dev.article_failed (
    id              BIGINT AUTO_INCREMENT PRIMARY KEY,
    article_id      CHAR(27) COLLATE utf8mb4_bin NULL,
    blog_id         BIGINT NULL,
    url             VARCHAR(500) NULL,
    title           VARCHAR(255) NULL,
    job_id          BIGINT NULL,
    stage           VARCHAR(32)  NOT NULL,
    error_category  VARCHAR(32)  NULL,
    error_severity  VARCHAR(16)  NULL,
    error_class     VARCHAR(128) NULL,
    error_message   TEXT         NULL,
    traceback       TEXT         NULL,
    payload         JSON         NULL,
    failed_at       TIMESTAMP    DEFAULT CURRENT_TIMESTAMP,
    retried_at      TIMESTAMP    NULL,
    INDEX idx_failed_at  (failed_at),
    INDEX idx_stage      (stage, failed_at),
    INDEX idx_article    (article_id),
    INDEX idx_job        (job_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- -------------------------------------------------------------------
-- 2. job_run (실행 로그)
-- -------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS bite.job_run (
    id               BIGINT AUTO_INCREMENT PRIMARY KEY,
    job_name         VARCHAR(64) NOT NULL,
    started_at       TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP(3),
    finished_at      TIMESTAMP(3) NULL,
    duration_ms      INT UNSIGNED NULL,
    status           VARCHAR(16) NOT NULL DEFAULT 'running',
    queued_count     INT UNSIGNED DEFAULT 0,
    processed_count  INT UNSIGNED DEFAULT 0,
    rejected_count   INT UNSIGNED DEFAULT 0,
    failed_count     INT UNSIGNED DEFAULT 0,
    recovered_count  INT UNSIGNED DEFAULT 0,
    stage_breakdown  JSON         NULL,
    error_summary    TEXT         NULL,
    host             VARCHAR(64)  NULL,
    INDEX idx_started_at    (started_at),
    INDEX idx_job_started   (job_name, started_at),
    INDEX idx_status_job    (status, job_name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS bite_dev.job_run (
    id               BIGINT AUTO_INCREMENT PRIMARY KEY,
    job_name         VARCHAR(64) NOT NULL,
    started_at       TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP(3),
    finished_at      TIMESTAMP(3) NULL,
    duration_ms      INT UNSIGNED NULL,
    status           VARCHAR(16) NOT NULL DEFAULT 'running',
    queued_count     INT UNSIGNED DEFAULT 0,
    processed_count  INT UNSIGNED DEFAULT 0,
    rejected_count   INT UNSIGNED DEFAULT 0,
    failed_count     INT UNSIGNED DEFAULT 0,
    recovered_count  INT UNSIGNED DEFAULT 0,
    stage_breakdown  JSON         NULL,
    error_summary    TEXT         NULL,
    host             VARCHAR(64)  NULL,
    INDEX idx_started_at    (started_at),
    INDEX idx_job_started   (job_name, started_at),
    INDEX idx_status_job    (status, job_name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- -------------------------------------------------------------------
-- 3. article_queue: 진행 상태 추적 컬럼 (멱등 ALTER)
--    status: 'queued' | 'processing' | 'transient_failed'
--    failed → article_failed로 이관 후 queue에서 DELETE되므로
--    queue.status는 transient retry 추적용.
-- -------------------------------------------------------------------

-- bite.article_queue.status
SET @c := (SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS
  WHERE TABLE_SCHEMA='bite' AND TABLE_NAME='article_queue' AND COLUMN_NAME='status');
SET @s := IF(@c=0,
  "ALTER TABLE bite.article_queue ADD COLUMN status VARCHAR(24) NOT NULL DEFAULT 'queued'",
  'SELECT 1');
PREPARE st FROM @s; EXECUTE st; DEALLOCATE PREPARE st;

-- bite.article_queue.attempt_count
SET @c := (SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS
  WHERE TABLE_SCHEMA='bite' AND TABLE_NAME='article_queue' AND COLUMN_NAME='attempt_count');
SET @s := IF(@c=0,
  'ALTER TABLE bite.article_queue ADD COLUMN attempt_count INT UNSIGNED NOT NULL DEFAULT 0',
  'SELECT 1');
PREPARE st FROM @s; EXECUTE st; DEALLOCATE PREPARE st;

-- bite.article_queue.last_error
SET @c := (SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS
  WHERE TABLE_SCHEMA='bite' AND TABLE_NAME='article_queue' AND COLUMN_NAME='last_error');
SET @s := IF(@c=0,
  'ALTER TABLE bite.article_queue ADD COLUMN last_error TEXT NULL',
  'SELECT 1');
PREPARE st FROM @s; EXECUTE st; DEALLOCATE PREPARE st;

-- bite.article_queue.last_attempted_at
SET @c := (SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS
  WHERE TABLE_SCHEMA='bite' AND TABLE_NAME='article_queue' AND COLUMN_NAME='last_attempted_at');
SET @s := IF(@c=0,
  'ALTER TABLE bite.article_queue ADD COLUMN last_attempted_at TIMESTAMP NULL',
  'SELECT 1');
PREPARE st FROM @s; EXECUTE st; DEALLOCATE PREPARE st;

-- bite.article_queue idx_status_attempted
SET @i := (SELECT COUNT(*) FROM INFORMATION_SCHEMA.STATISTICS
  WHERE TABLE_SCHEMA='bite' AND TABLE_NAME='article_queue' AND INDEX_NAME='idx_status_attempted');
SET @s := IF(@i=0,
  'CREATE INDEX idx_status_attempted ON bite.article_queue (status, last_attempted_at)',
  'SELECT 1');
PREPARE st FROM @s; EXECUTE st; DEALLOCATE PREPARE st;

-- bite_dev.article_queue.status
SET @c := (SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS
  WHERE TABLE_SCHEMA='bite_dev' AND TABLE_NAME='article_queue' AND COLUMN_NAME='status');
SET @s := IF(@c=0,
  "ALTER TABLE bite_dev.article_queue ADD COLUMN status VARCHAR(24) NOT NULL DEFAULT 'queued'",
  'SELECT 1');
PREPARE st FROM @s; EXECUTE st; DEALLOCATE PREPARE st;

-- bite_dev.article_queue.attempt_count
SET @c := (SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS
  WHERE TABLE_SCHEMA='bite_dev' AND TABLE_NAME='article_queue' AND COLUMN_NAME='attempt_count');
SET @s := IF(@c=0,
  'ALTER TABLE bite_dev.article_queue ADD COLUMN attempt_count INT UNSIGNED NOT NULL DEFAULT 0',
  'SELECT 1');
PREPARE st FROM @s; EXECUTE st; DEALLOCATE PREPARE st;

-- bite_dev.article_queue.last_error
SET @c := (SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS
  WHERE TABLE_SCHEMA='bite_dev' AND TABLE_NAME='article_queue' AND COLUMN_NAME='last_error');
SET @s := IF(@c=0,
  'ALTER TABLE bite_dev.article_queue ADD COLUMN last_error TEXT NULL',
  'SELECT 1');
PREPARE st FROM @s; EXECUTE st; DEALLOCATE PREPARE st;

-- bite_dev.article_queue.last_attempted_at
SET @c := (SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS
  WHERE TABLE_SCHEMA='bite_dev' AND TABLE_NAME='article_queue' AND COLUMN_NAME='last_attempted_at');
SET @s := IF(@c=0,
  'ALTER TABLE bite_dev.article_queue ADD COLUMN last_attempted_at TIMESTAMP NULL',
  'SELECT 1');
PREPARE st FROM @s; EXECUTE st; DEALLOCATE PREPARE st;

-- bite_dev.article_queue idx_status_attempted
SET @i := (SELECT COUNT(*) FROM INFORMATION_SCHEMA.STATISTICS
  WHERE TABLE_SCHEMA='bite_dev' AND TABLE_NAME='article_queue' AND INDEX_NAME='idx_status_attempted');
SET @s := IF(@i=0,
  'CREATE INDEX idx_status_attempted ON bite_dev.article_queue (status, last_attempted_at)',
  'SELECT 1');
PREPARE st FROM @s; EXECUTE st; DEALLOCATE PREPARE st;
