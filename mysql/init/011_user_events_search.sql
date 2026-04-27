-- =============================================
-- user_events 검색 분석용 컬럼 + 인덱스 보강
-- =============================================
-- ML 운영 사이클 (CTR 집계, A/B, fine-tuning)을 위한 schema 확장.
--
-- 변경 요약:
--   1. member_id NULL 허용 → 익명 사용자 이벤트(device_id 만으로 식별) 적재 가능
--   2. device_id 컬럼 추가 → bite-api/internal/event/dto.go가 이미 받고 있던 필드를 DB에 저장
--   3. query_text / query_norm_hash 별도 컬럼 → metadata.query에 묻혀 있던 검색어를
--      집계 가능한 형태로 분리. query_norm_hash는 recsys-serving의 _query_hash와 동일
--      정규화(lower + strip + sha1[:12])로 join 가능
--   4. 인덱스 idx_query_hash, idx_device_occurred 추가
--
-- 적용:
--   - 신규 컨테이너: docker-entrypoint-initdb.d 자동 실행
--   - 기존 컨테이너: docker exec bite-mysql mysql -u root -p"$MYSQL_ROOT_PASSWORD"
--                   bite < 010_user_events_search.sql

ALTER TABLE bite.user_events
    MODIFY COLUMN member_id BIGINT NULL,
    ADD COLUMN device_id CHAR(36) NULL AFTER member_id,
    ADD COLUMN query_text VARCHAR(200) NULL AFTER metadata,
    ADD COLUMN query_norm_hash CHAR(12) NULL AFTER query_text,
    ADD COLUMN query_id CHAR(32) NULL AFTER query_norm_hash,
    ADD INDEX idx_query_hash (query_norm_hash, event_type, occurred_at),
    ADD INDEX idx_query_id (query_id, event_type, position),
    ADD INDEX idx_device_occurred (device_id, occurred_at);

-- bite_dev 미러
ALTER TABLE bite_dev.user_events
    MODIFY COLUMN member_id BIGINT NULL,
    ADD COLUMN device_id CHAR(36) NULL AFTER member_id,
    ADD COLUMN query_text VARCHAR(200) NULL AFTER metadata,
    ADD COLUMN query_norm_hash CHAR(12) NULL AFTER query_text,
    ADD COLUMN query_id CHAR(32) NULL AFTER query_norm_hash,
    ADD INDEX idx_query_hash (query_norm_hash, event_type, occurred_at),
    ADD INDEX idx_query_id (query_id, event_type, position),
    ADD INDEX idx_device_occurred (device_id, occurred_at);
