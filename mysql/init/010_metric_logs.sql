-- metric.bite-sized.xyz 대시보드용 메트릭 로그 테이블.
-- recsys-serving 온라인 요청 / recommender 배치 실행을 영구화한다.
-- 적재 측이 graceful skip을 책임지므로 본 마이그레이션은 idempotent.

CREATE TABLE IF NOT EXISTS recsys_request_log (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    request_id VARCHAR(36) NOT NULL,
    endpoint VARCHAR(32) NOT NULL,
    member_id BIGINT NULL,
    status_code SMALLINT UNSIGNED NOT NULL,
    latency_ms INT UNSIGNED NOT NULL,
    result_count INT NULL,
    query_text VARCHAR(255) NULL,
    source VARCHAR(50) NULL,
    error_class VARCHAR(64) NULL,
    occurred_at TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP(3),
    UNIQUE KEY uk_request_id (request_id),
    INDEX idx_endpoint_occurred (endpoint, occurred_at),
    INDEX idx_status_occurred (status_code, occurred_at),
    INDEX idx_occurred (occurred_at)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS recommender_run_metric (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    run_id CHAR(36) NOT NULL,
    stage VARCHAR(40) NOT NULL,
    duration_ms INT UNSIGNED NULL,
    payload JSON NULL,
    occurred_at TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP(3),
    INDEX idx_run (run_id),
    INDEX idx_stage_occurred (stage, occurred_at),
    INDEX idx_occurred (occurred_at)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS recommender_recall_daily (
    metric_date DATE NOT NULL,
    k SMALLINT UNSIGNED NOT NULL,
    recall FLOAT NULL,
    hit_users INT UNSIGNED NULL,
    total_users INT UNSIGNED NULL,
    total_recommendations INT UNSIGNED NULL,
    unique_items INT UNSIGNED NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (metric_date, k)
) ENGINE=InnoDB;
