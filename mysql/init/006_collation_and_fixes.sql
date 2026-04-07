-- =============================================
-- Fix article_id collation mismatch + article_history unique index
-- =============================================

-- article table uses COLLATE utf8mb4_bin, but related tables use default.
-- This causes JOINs to skip indexes. Fix by matching collation everywhere.

ALTER TABLE article_like MODIFY COLUMN article_id CHAR(27) COLLATE utf8mb4_bin NOT NULL;
ALTER TABLE article_bookmark MODIFY COLUMN article_id CHAR(27) COLLATE utf8mb4_bin NOT NULL;
ALTER TABLE article_share MODIFY COLUMN article_id CHAR(27) COLLATE utf8mb4_bin NOT NULL;
ALTER TABLE article_uninterest MODIFY COLUMN article_id CHAR(27) COLLATE utf8mb4_bin NOT NULL;
ALTER TABLE article_history MODIFY COLUMN article_id CHAR(27) COLLATE utf8mb4_bin NOT NULL;
ALTER TABLE member_last_seen_feed MODIFY COLUMN article_id CHAR(27) COLLATE utf8mb4_bin NOT NULL;
ALTER TABLE user_events MODIFY COLUMN article_id CHAR(27) COLLATE utf8mb4_bin NULL;
ALTER TABLE user_article_engagement MODIFY COLUMN article_id CHAR(27) COLLATE utf8mb4_bin NOT NULL;

-- article_history: unique index for ON DUPLICATE KEY UPDATE pattern
ALTER TABLE article_history ADD UNIQUE INDEX uk_member_article (member_id, article_id);

-- Mirror to bite_dev
ALTER TABLE bite_dev.article_like MODIFY COLUMN article_id CHAR(27) COLLATE utf8mb4_bin NOT NULL;
ALTER TABLE bite_dev.article_bookmark MODIFY COLUMN article_id CHAR(27) COLLATE utf8mb4_bin NOT NULL;
ALTER TABLE bite_dev.article_share MODIFY COLUMN article_id CHAR(27) COLLATE utf8mb4_bin NOT NULL;
ALTER TABLE bite_dev.article_uninterest MODIFY COLUMN article_id CHAR(27) COLLATE utf8mb4_bin NOT NULL;
ALTER TABLE bite_dev.article_history MODIFY COLUMN article_id CHAR(27) COLLATE utf8mb4_bin NOT NULL;
ALTER TABLE bite_dev.member_last_seen_feed MODIFY COLUMN article_id CHAR(27) COLLATE utf8mb4_bin NOT NULL;
ALTER TABLE bite_dev.user_events MODIFY COLUMN article_id CHAR(27) COLLATE utf8mb4_bin NULL;
ALTER TABLE bite_dev.user_article_engagement MODIFY COLUMN article_id CHAR(27) COLLATE utf8mb4_bin NOT NULL;
ALTER TABLE bite_dev.article_history ADD UNIQUE INDEX uk_member_article (member_id, article_id);
