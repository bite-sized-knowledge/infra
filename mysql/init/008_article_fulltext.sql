-- =============================================
-- FULLTEXT search index on article (title, description, keywords)
-- =============================================
-- Replaces LIKE '%q%' full table scan with relevance-ranked FULLTEXT.
-- ngram parser handles Korean (CJK) + English; default ngram_token_size=2.
-- Used by /v1/articles/search via MATCH ... AGAINST in BOOLEAN MODE.

ALTER TABLE article
    ADD FULLTEXT INDEX ft_article_search (title, description, keywords) WITH PARSER ngram;

-- Mirror to bite_dev
ALTER TABLE bite_dev.article
    ADD FULLTEXT INDEX ft_article_search (title, description, keywords) WITH PARSER ngram;
