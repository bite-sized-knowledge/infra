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

INSERT INTO blog (blog_id, title, url, rss_url, favicon)
VALUES
    (1, '우아한형제들 기술블로그', 'https://techblog.woowahan.com', 'https://techblog.woowahan.com/feed/', 'https://techblog.woowahan.com/favicon.ico'),
    (2, '카카오 기술블로그', 'https://tech.kakao.com', 'https://tech.kakao.com/feed/', 'https://tech.kakao.com/favicon.ico'),
    (3, '토스 기술블로그', 'https://toss.tech', 'https://toss.tech/rss.xml', 'https://toss.tech/favicon.ico'),
    (4, '당근 테크 블로그', 'https://medium.com/daangn', 'https://medium.com/feed/daangn', 'https://miro.medium.com/favicon.ico'),
    (5, '인프랩 기술블로그', 'https://tech.inflab.com', 'https://tech.inflab.com/rss.xml', 'https://tech.inflab.com/favicon.ico'),
    (6, '네이버 D2', 'https://d2.naver.com', 'https://d2.naver.com/d2.atom', 'https://d2.naver.com/favicon.ico'),
    (7, '스포카 기술블로그', 'https://spoqa.github.io', 'https://spoqa.github.io/rss.xml', 'https://spoqa.github.io/favicon.ico'),
    (8, 'LY Corporation Tech Blog', 'https://techblog.lycorp.co.jp', 'https://techblog.lycorp.co.jp/ko/feed/index.xml', 'https://techblog.lycorp.co.jp/favicon.ico'),
    (9, '리디 기술블로그', 'https://ridicorp.com/story-category/tech-blog', 'https://ridicorp.com/story-category/tech-blog/feed/', 'https://ridicorp.com/favicon.ico'),
    (10, '쏘카 기술블로그', 'https://tech.socarcorp.kr', 'https://tech.socarcorp.kr/feed.xml', 'https://tech.socarcorp.kr/favicon.ico')
ON DUPLICATE KEY UPDATE
    title = VALUES(title),
    url = VALUES(url),
    rss_url = VALUES(rss_url),
    favicon = VALUES(favicon),
    crawl_type = 'RSS',
    crawl_url = VALUES(rss_url);
