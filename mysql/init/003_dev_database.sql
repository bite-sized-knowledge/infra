-- 개발계 데이터베이스 생성
CREATE DATABASE IF NOT EXISTS bite_dev;

-- 개발계 전용 유저
CREATE USER IF NOT EXISTS 'bite-dev-user'@'%' IDENTIFIED BY 'bite-dev-123!';
GRANT ALL PRIVILEGES ON bite_dev.* TO 'bite-dev-user'@'%';
FLUSH PRIVILEGES;

-- 개발계 스키마 (운영계와 동일)
USE bite_dev;

CREATE TABLE IF NOT EXISTS member (
    member_id  BIGINT AUTO_INCREMENT NOT NULL,
    email      VARCHAR(255) NULL,
    password   VARCHAR(255) NULL,
    name       VARCHAR(255) NULL,
    birth      INT NULL,
    gender     VARCHAR(10) NULL,
    status     VARCHAR(10) NULL,
    role       VARCHAR(20) NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (member_id),
    UNIQUE KEY (email)
);

CREATE TABLE IF NOT EXISTS interest (
    interest_id BIGINT AUTO_INCREMENT NOT NULL,
    name VARCHAR(255) NOT NULL,
    image VARCHAR(255) NULL,
    thumbnail VARCHAR(255) NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (interest_id),
    UNIQUE KEY (name)
);

CREATE TABLE IF NOT EXISTS member_interest (
    member_interest_id BIGINT AUTO_INCREMENT NOT NULL,
    member_id BIGINT NOT NULL,
    interest_id BIGINT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (member_interest_id)
);

CREATE TABLE IF NOT EXISTS oauth (
    oauth_id BIGINT AUTO_INCREMENT NOT NULL,
    member_id BIGINT NOT NULL,
    provider VARCHAR(10) NOT NULL,
    provider_member_id VARCHAR(255) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (oauth_id),
    UNIQUE KEY (provider, provider_member_id)
);

CREATE TABLE IF NOT EXISTS blog (
    blog_id BIGINT AUTO_INCREMENT NOT NULL,
    platform_id BIGINT NULL,
    title VARCHAR(255) NULL,
    url VARCHAR(500) NULL,
    rss_url VARCHAR(500) NOT NULL,
    favicon VARCHAR(255) NULL,
    crawl_type VARCHAR(20) NOT NULL DEFAULT 'RSS',
    crawl_url VARCHAR(500) NULL,
    external_source VARCHAR(50) NULL,
    external_id BIGINT NULL,
    base_url VARCHAR(500) NULL,
    article_selector VARCHAR(255) NULL,
    title_selector VARCHAR(255) NULL,
    link_selector VARCHAR(255) NULL,
    thumbnail_selector VARCHAR(255) NULL,
    publish_selector VARCHAR(255) NULL,
    publish_format VARCHAR(64) NULL,
    publish_type VARCHAR(20) NULL,
    inner_publish_selector VARCHAR(255) NULL,
    pagination_type VARCHAR(20) NULL,
    page_url_pattern VARCHAR(255) NULL,
    next_page_selector VARCHAR(255) NULL,
    max_pages INT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (blog_id)
);

CREATE TABLE IF NOT EXISTS article (
    article_id CHAR(27) COLLATE utf8mb4_bin NOT NULL,
    blog_id BIGINT NULL,
    url VARCHAR(500) NULL,
    title VARCHAR(255) NULL,
    thumbnail VARCHAR(500) NULL,
    description VARCHAR(1000) NULL,
    keywords VARCHAR(255) NULL,
    category_id BIGINT NULL,
    content LONGTEXT NULL,
    content_length BIGINT NULL,
    lang VARCHAR(10) NULL,
    like_count BIGINT NOT NULL DEFAULT 0,
    share_count BIGINT NOT NULL DEFAULT 0,
    bookmark_count BIGINT NOT NULL DEFAULT 0,
    published_at TIMESTAMP NULL,
    sort_key VARCHAR(60) GENERATED ALWAYS AS (CONCAT(DATE_FORMAT(created_at, '%Y%m%d%H%i%s'), article_id)) STORED,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (article_id),
    INDEX idx_blog_sort_key (blog_id, sort_key DESC),
    INDEX idx_sort_key (sort_key DESC)
);

CREATE TABLE IF NOT EXISTS article_like (
    article_like_id BIGINT AUTO_INCREMENT NOT NULL,
    article_id CHAR(27) NOT NULL,
    member_id BIGINT NOT NULL,
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (article_like_id),
    UNIQUE KEY (article_id, member_id)
);

CREATE TABLE IF NOT EXISTS article_uninterest (
    article_uninterest_id BIGINT AUTO_INCREMENT NOT NULL,
    article_id CHAR(27) NOT NULL,
    member_id BIGINT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (article_uninterest_id)
);

CREATE TABLE IF NOT EXISTS article_share (
    article_share_id BIGINT AUTO_INCREMENT NOT NULL,
    article_id CHAR(27) NOT NULL,
    member_id BIGINT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (article_share_id),
    UNIQUE KEY (article_id, member_id)
);

CREATE TABLE IF NOT EXISTS article_bookmark (
    article_bookmark_id BIGINT AUTO_INCREMENT NOT NULL,
    article_id CHAR(27) NOT NULL,
    member_id BIGINT NOT NULL,
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (article_bookmark_id),
    UNIQUE KEY (article_id, member_id),
    INDEX idx_member_id_updated_at (member_id, updated_at)
);

CREATE TABLE IF NOT EXISTS blog_subscribe (
    blog_subscribe_id BIGINT AUTO_INCREMENT NOT NULL,
    blog_id BIGINT NOT NULL,
    member_id BIGINT NOT NULL,
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (blog_subscribe_id),
    UNIQUE KEY (blog_id, member_id)
);

CREATE TABLE IF NOT EXISTS email_verify (
    email_verify_id BIGINT AUTO_INCREMENT NOT NULL,
    email VARCHAR(255) NOT NULL,
    verify_code VARCHAR(255) NOT NULL,
    is_verified BOOLEAN NOT NULL DEFAULT FALSE,
    member_id BIGINT NULL,
    expired_at TIMESTAMP NOT NULL,
    type VARCHAR(20) NOT NULL DEFAULT 'REGISTER',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (email_verify_id),
    UNIQUE KEY (email, type)
);

CREATE TABLE IF NOT EXISTS member_last_seen_feed (
    member_id BIGINT NOT NULL,
    article_id CHAR(27) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (member_id)
);

CREATE TABLE IF NOT EXISTS recommendation (
    recommendation_id BIGINT AUTO_INCREMENT NOT NULL,
    member_id BIGINT NOT NULL,
    article_id CHAR(27) COLLATE utf8mb4_bin NOT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (recommendation_id),
    INDEX idx_member_id_recommendation_id (member_id, recommendation_id)
);

CREATE TABLE IF NOT EXISTS article_history (
    id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
    member_id BIGINT NOT NULL,
    article_id CHAR(27) COLLATE utf8mb4_bin NOT NULL,
    INDEX idx_user_id_id_desc (member_id, id DESC)
);

CREATE TABLE IF NOT EXISTS user_events (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    event_uuid VARCHAR(36) NOT NULL,
    member_id BIGINT NOT NULL,
    event_type VARCHAR(30) NOT NULL,
    article_id CHAR(27) NULL,
    dwell_time_ms INT NULL,
    scroll_depth TINYINT UNSIGNED NULL,
    source VARCHAR(50) NULL,
    position INT NULL,
    feed_request_id VARCHAR(64) NULL,
    session_id VARCHAR(64) NULL,
    device_type VARCHAR(20) NULL,
    app_version VARCHAR(20) NULL,
    metadata JSON NULL,
    occurred_at TIMESTAMP NOT NULL,
    received_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uk_event_uuid (event_uuid),
    INDEX idx_member_occurred (member_id, occurred_at),
    INDEX idx_article_occurred (article_id, occurred_at),
    INDEX idx_session (session_id, occurred_at),
    INDEX idx_feed_request (feed_request_id, position)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS user_article_engagement (
    member_id BIGINT NOT NULL,
    article_id CHAR(27) NOT NULL,
    impressions INT DEFAULT 0,
    clicks INT DEFAULT 0,
    total_dwell_ms BIGINT DEFAULT 0,
    max_scroll_depth TINYINT UNSIGNED DEFAULT 0,
    bookmarked BOOLEAN DEFAULT FALSE,
    liked BOOLEAN DEFAULT FALSE,
    shared BOOLEAN DEFAULT FALSE,
    first_seen_at TIMESTAMP NULL,
    last_seen_at TIMESTAMP NULL,
    engagement_score FLOAT NULL,
    PRIMARY KEY (member_id, article_id),
    INDEX idx_article (article_id),
    INDEX idx_score (member_id, engagement_score DESC)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS article_queue (
    article_id CHAR(27) COLLATE utf8mb4_bin NOT NULL,
    blog_id BIGINT NULL,
    url VARCHAR(500) NULL,
    title VARCHAR(255) NULL,
    thumbnail VARCHAR(500) NULL,
    description VARCHAR(1000) NULL,
    keywords VARCHAR(255) NULL,
    category_id BIGINT NULL,
    content LONGTEXT NULL,
    content_length BIGINT NULL,
    lang VARCHAR(10) NULL,
    like_count BIGINT NOT NULL DEFAULT 0,
    share_count BIGINT NOT NULL DEFAULT 0,
    bookmark_count BIGINT NOT NULL DEFAULT 0,
    published_at TIMESTAMP NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (article_id),
    INDEX idx_article_queue_blog_id (blog_id),
    INDEX idx_article_queue_published_at (published_at)
);
