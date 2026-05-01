-- =============================================
-- member.device_id 추가 — 비로그인 lazy guest 발급용
-- =============================================
-- FK-action(좋아요/북마크/구독/관심사) 시점에 lazy로 guest member를 upsert 하기 위한 unique 식별자.
-- 클라이언트가 X-Device-Id 헤더로 보내고, 서버는 device_id로 SELECT → 없으면 INSERT (UNIQUE 제약 race-safe).
--
-- 컬럼 타입: CHAR(36) ascii_bin — UUID는 항상 36자 ASCII이고 binary 비교가 정확.
-- 서버는 입력을 lower-case 정규화 후 비교/저장한다.
--
-- 적용 (bite, bite_dev 양쪽):
--   PW=$(doppler secrets get MYSQL_ROOT_PASSWORD --plain --project infra --config prd)
--   docker exec -i bite-mysql mysql -u root -p"$PW" < mysql/init/014_member_device_id.sql
--
-- INFORMATION_SCHEMA 체크 + PREPARE 로 멱등.

-- bite.member.device_id
SET @col_exists := (SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS
  WHERE TABLE_SCHEMA = 'bite' AND TABLE_NAME = 'member' AND COLUMN_NAME = 'device_id');
SET @sql := IF(@col_exists = 0,
  'ALTER TABLE bite.member ADD COLUMN device_id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NULL AFTER role',
  'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @idx_exists := (SELECT COUNT(*) FROM INFORMATION_SCHEMA.STATISTICS
  WHERE TABLE_SCHEMA = 'bite' AND TABLE_NAME = 'member' AND INDEX_NAME = 'uq_member_device_id');
SET @sql := IF(@idx_exists = 0,
  'ALTER TABLE bite.member ADD UNIQUE KEY uq_member_device_id (device_id)',
  'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- bite_dev.member.device_id
SET @col_exists := (SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS
  WHERE TABLE_SCHEMA = 'bite_dev' AND TABLE_NAME = 'member' AND COLUMN_NAME = 'device_id');
SET @sql := IF(@col_exists = 0,
  'ALTER TABLE bite_dev.member ADD COLUMN device_id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NULL AFTER role',
  'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @idx_exists := (SELECT COUNT(*) FROM INFORMATION_SCHEMA.STATISTICS
  WHERE TABLE_SCHEMA = 'bite_dev' AND TABLE_NAME = 'member' AND INDEX_NAME = 'uq_member_device_id');
SET @sql := IF(@idx_exists = 0,
  'ALTER TABLE bite_dev.member ADD UNIQUE KEY uq_member_device_id (device_id)',
  'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;
