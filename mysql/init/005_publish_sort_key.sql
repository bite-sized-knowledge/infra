-- =============================================
-- Publish-date-based sort key for the "recent" feed
-- =============================================
--
-- The existing `sort_key` column sorts by `created_at` — the timestamp
-- at which our harvester INSERTED the article into our DB. That made
-- "최신" (latest) feeds reflect crawl order rather than the actual
-- publication order of the source blog posts, so newly-ingested old
-- posts would leapfrog genuinely new posts.
--
-- `publish_sort_key` sorts by `published_at` (the source blog's
-- publication timestamp). We fall back to `created_at` for the rare
-- article that arrives without a publication date in its feed, which
-- keeps it orderable instead of dropping it out of the feed entirely.
--
-- The old `sort_key` column is left alone — it's still referenced by
-- the search index helper (ListBookmarks cursor, etc.) and rewriting
-- everything in one shot is riskier than a narrow additive migration.
-- The /v1/articles/recent and /v1/blogs/{id}/articles endpoints are
-- the two that switch to publish_sort_key in repository.go.
-- =============================================

ALTER TABLE article
  ADD COLUMN publish_sort_key VARCHAR(60)
    GENERATED ALWAYS AS (
      CONCAT(
        DATE_FORMAT(IFNULL(published_at, created_at), '%Y%m%d%H%i%s'),
        article_id
      )
    ) STORED;

CREATE INDEX idx_publish_sort_key         ON article (publish_sort_key DESC);
CREATE INDEX idx_blog_publish_sort_key    ON article (blog_id, publish_sort_key DESC);
