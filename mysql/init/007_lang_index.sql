-- Feed language filter: composite index for filtered recent feed queries
CREATE INDEX idx_lang_publish_sort_key ON article (lang, publish_sort_key DESC);
