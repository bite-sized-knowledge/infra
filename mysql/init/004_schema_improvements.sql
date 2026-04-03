-- =============================================
-- Schema improvements: indexes, constraints, columns
-- =============================================

-- 1. Missing indexes for query performance
ALTER TABLE article_like ADD INDEX idx_member_id (member_id);
ALTER TABLE article_share ADD INDEX idx_member_id (member_id);
ALTER TABLE article_uninterest ADD INDEX idx_member_article (member_id, article_id);
ALTER TABLE member_interest ADD INDEX idx_member_id (member_id);
ALTER TABLE member_interest ADD INDEX idx_interest_id (interest_id);
ALTER TABLE oauth ADD INDEX idx_member_id (member_id);

-- 2. Missing unique constraints (prevent duplicate data)
ALTER TABLE article_uninterest ADD UNIQUE KEY uk_article_member (article_id, member_id);
ALTER TABLE member_interest ADD UNIQUE KEY uk_member_interest (member_id, interest_id);

-- 3. Add score column to recommendation table for ML re-ranking
ALTER TABLE recommendation ADD COLUMN score FLOAT NULL AFTER article_id;
ALTER TABLE recommendation ADD INDEX idx_member_score (member_id, score DESC);

-- 4. Clean up article_queue: remove meaningless count columns
ALTER TABLE article_queue DROP COLUMN like_count;
ALTER TABLE article_queue DROP COLUMN share_count;
ALTER TABLE article_queue DROP COLUMN bookmark_count;
