-- =============================================
-- Recsys Phase 1+2: 추천 풀 + per-user/category bandit + impression/메트릭 집계
-- =============================================
-- 테이블 구성 (bite + bite_dev 양쪽에 동일):
--   1. recommendation_global         : 매일 배치로 갱신되는 글로벌 article 풀
--   2. member_category_bandit        : (member_id, category_id) Beta TS state
--   3. recommendation_impression     : 추천 응답 노출 로그 (CTR/per-position 분석 기반)
--   4. recommendation_metric_daily   : 일별 추천 KPI rollup
--   5. bandit_state_snapshot         : 일별 bandit α/β 스냅샷 (학습 trajectory)
--
-- 컬럼명 노트: `rank`는 MySQL 8.0 reserved word라 `rank_global`로 사용.
--
-- 적용:
--   - 신규 컨테이너: docker-entrypoint-initdb.d 자동 실행
--   - 기존 운영 컨테이너:
--     ```
--     PW=$(doppler secrets get MYSQL_ROOT_PASSWORD --plain --project infra --config prd)
--     docker exec -i bite-mysql mysql -u root -p"$PW" < mysql/init/012_recsys_phase1_2.sql
--     ```
--     SQL 안에 bite. / bite_dev. 양쪽 schema 명시되어 한 번의 exec로 양쪽 적용됨.
--   - 모든 SQL은 IF NOT EXISTS로 멱등.

-- ---------------------------------------------
-- 1. recommendation_global
-- ---------------------------------------------
CREATE TABLE IF NOT EXISTS bite.recommendation_global (
    article_id    CHAR(27) COLLATE utf8mb4_bin NOT NULL,
    score         DOUBLE NOT NULL,
    rank_global   INT NOT NULL,
    category_id   BIGINT NULL,
    generated_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (article_id),
    INDEX idx_score (score DESC),
    INDEX idx_category_score (category_id, score DESC),
    INDEX idx_rank (rank_global)
);

CREATE TABLE IF NOT EXISTS bite_dev.recommendation_global (
    article_id    CHAR(27) COLLATE utf8mb4_bin NOT NULL,
    score         DOUBLE NOT NULL,
    rank_global   INT NOT NULL,
    category_id   BIGINT NULL,
    generated_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (article_id),
    INDEX idx_score (score DESC),
    INDEX idx_category_score (category_id, score DESC),
    INDEX idx_rank (rank_global)
);

-- ---------------------------------------------
-- 2. member_category_bandit
-- ---------------------------------------------
-- Lazy init: 서빙 첫 호출 시 member_interest 기반 prior 채워 넣음.
--   onboarding 선택 카테고리: Beta(α=4, β=1)
--   미선택 카테고리:           Beta(α=1, β=2)
-- Reward: like/bookmark/click → α += 1, share → α += 2, uninterest → β += 2
CREATE TABLE IF NOT EXISTS bite.member_category_bandit (
    member_id     BIGINT NOT NULL,
    category_id   BIGINT NOT NULL,
    alpha         DOUBLE NOT NULL DEFAULT 1.0,
    beta          DOUBLE NOT NULL DEFAULT 1.0,
    impressions   INT NOT NULL DEFAULT 0,
    clicks        INT NOT NULL DEFAULT 0,
    last_updated  TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    created_at    TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (member_id, category_id),
    INDEX idx_member_updated (member_id, last_updated)
);

CREATE TABLE IF NOT EXISTS bite_dev.member_category_bandit (
    member_id     BIGINT NOT NULL,
    category_id   BIGINT NOT NULL,
    alpha         DOUBLE NOT NULL DEFAULT 1.0,
    beta          DOUBLE NOT NULL DEFAULT 1.0,
    impressions   INT NOT NULL DEFAULT 0,
    clicks        INT NOT NULL DEFAULT 0,
    last_updated  TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    created_at    TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (member_id, category_id),
    INDEX idx_member_updated (member_id, last_updated)
);

-- ---------------------------------------------
-- 3. recommendation_impression
-- ---------------------------------------------
-- 응답 시 일괄 INSERT. user_events.click과 (member_id, article_id, time window) 기반 join.
-- bandit_theta는 분석용 (TS sample 분포 추적).
CREATE TABLE IF NOT EXISTS bite.recommendation_impression (
    impression_id  BIGINT AUTO_INCREMENT NOT NULL,
    member_id      BIGINT NOT NULL,
    article_id     CHAR(27) COLLATE utf8mb4_bin NOT NULL,
    category_id    BIGINT NULL,
    position       INT NOT NULL,
    bandit_theta   DOUBLE NULL,
    shown_at       TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP(3),
    PRIMARY KEY (impression_id),
    INDEX idx_member_shown (member_id, shown_at DESC),
    INDEX idx_category_shown (category_id, shown_at DESC),
    INDEX idx_article_shown (article_id, shown_at DESC),
    INDEX idx_member_article (member_id, article_id, shown_at DESC)
);

CREATE TABLE IF NOT EXISTS bite_dev.recommendation_impression (
    impression_id  BIGINT AUTO_INCREMENT NOT NULL,
    member_id      BIGINT NOT NULL,
    article_id     CHAR(27) COLLATE utf8mb4_bin NOT NULL,
    category_id    BIGINT NULL,
    position       INT NOT NULL,
    bandit_theta   DOUBLE NULL,
    shown_at       TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP(3),
    PRIMARY KEY (impression_id),
    INDEX idx_member_shown (member_id, shown_at DESC),
    INDEX idx_category_shown (category_id, shown_at DESC),
    INDEX idx_article_shown (article_id, shown_at DESC),
    INDEX idx_member_article (member_id, article_id, shown_at DESC)
);

-- ---------------------------------------------
-- 4. recommendation_metric_daily
-- ---------------------------------------------
-- 일별 KPI rollup. recommender 배치가 매일 갱신.
CREATE TABLE IF NOT EXISTS bite.recommendation_metric_daily (
    metric_date            DATE NOT NULL,
    impressions            BIGINT NOT NULL DEFAULT 0,
    clicks                 BIGINT NOT NULL DEFAULT 0,
    ctr                    DOUBLE NULL,
    onboarding_ctr         DOUBLE NULL,
    non_onboarding_ctr     DOUBLE NULL,
    per_category           JSON NULL,
    per_position_ctr       JSON NULL,
    diversity_entropy      DOUBLE NULL,
    freshness_median_days  DOUBLE NULL,
    bandit_active_users    INT NOT NULL DEFAULT 0,
    pool_size              INT NOT NULL DEFAULT 0,
    cold_to_warm_users     INT NOT NULL DEFAULT 0,
    created_at             TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at             TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (metric_date)
);

CREATE TABLE IF NOT EXISTS bite_dev.recommendation_metric_daily (
    metric_date            DATE NOT NULL,
    impressions            BIGINT NOT NULL DEFAULT 0,
    clicks                 BIGINT NOT NULL DEFAULT 0,
    ctr                    DOUBLE NULL,
    onboarding_ctr         DOUBLE NULL,
    non_onboarding_ctr     DOUBLE NULL,
    per_category           JSON NULL,
    per_position_ctr       JSON NULL,
    diversity_entropy      DOUBLE NULL,
    freshness_median_days  DOUBLE NULL,
    bandit_active_users    INT NOT NULL DEFAULT 0,
    pool_size              INT NOT NULL DEFAULT 0,
    cold_to_warm_users     INT NOT NULL DEFAULT 0,
    created_at             TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at             TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (metric_date)
);

-- ---------------------------------------------
-- 5. bandit_state_snapshot
-- ---------------------------------------------
-- 일별 (member, category) α/β 스냅샷. posterior가 onboarding prior에서
-- 실제 행동으로 얼마나 빠르게 수렴하는지 trajectory 분석용.
CREATE TABLE IF NOT EXISTS bite.bandit_state_snapshot (
    snapshot_date  DATE NOT NULL,
    member_id      BIGINT NOT NULL,
    category_id    BIGINT NOT NULL,
    alpha          DOUBLE NOT NULL,
    beta           DOUBLE NOT NULL,
    impressions    INT NOT NULL DEFAULT 0,
    clicks         INT NOT NULL DEFAULT 0,
    PRIMARY KEY (snapshot_date, member_id, category_id),
    INDEX idx_member_date (member_id, snapshot_date),
    INDEX idx_date_category (snapshot_date, category_id)
);

CREATE TABLE IF NOT EXISTS bite_dev.bandit_state_snapshot (
    snapshot_date  DATE NOT NULL,
    member_id      BIGINT NOT NULL,
    category_id    BIGINT NOT NULL,
    alpha          DOUBLE NOT NULL,
    beta           DOUBLE NOT NULL,
    impressions    INT NOT NULL DEFAULT 0,
    clicks         INT NOT NULL DEFAULT 0,
    PRIMARY KEY (snapshot_date, member_id, category_id),
    INDEX idx_member_date (member_id, snapshot_date),
    INDEX idx_date_category (snapshot_date, category_id)
);
