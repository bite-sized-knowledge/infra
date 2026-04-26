-- =============================================
-- 009: UNIQUE constraint on article(url) and article_queue(url)
-- =============================================
-- Defends against the duplicate-on-renormalize failure mode:
-- when harvester-go's normalizeLink() rules change (e.g. a new
-- tracking-param added to the strip list), the same article
-- re-fetched later hashes to a different article_id and the
-- old article_id-only IsExistArticle check misses it. The
-- application-level fix in IsExistArticle (database.go) also
-- compares URL exactly; this DB constraint is the second line
-- of defense — even if a buggy code path slips past, MySQL
-- rejects the insert.
--
-- Apply order: run AFTER scripts/review/data_quality_cleanup.py
-- has resolved existing duplicates. Otherwise this ALTER will
-- fail with ER_DUP_ENTRY.
--
-- Storage: VARCHAR(500) utf8mb4 = 2000 bytes per key < 3072 byte
-- max for InnoDB on MySQL 8 default page size. No prefix needed.

ALTER TABLE article
    ADD UNIQUE KEY uk_article_url (url);

ALTER TABLE article_queue
    ADD UNIQUE KEY uk_article_queue_url (url);
