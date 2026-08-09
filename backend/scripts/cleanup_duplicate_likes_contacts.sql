-- 文件用途：scripts\cleanup_duplicate_likes_contacts.sql 是一个数据库初始化、索引、数据修复或演示数据脚本。
-- 核心逻辑：按文件中的顺序执行配置加载、数据库变更、构建部署或维护操作，并保持可重复执行。

-- Clean duplicate rows before adding unique indexes:
--   moment_likes(moment_id, user_id)
--   contacts(user_id, contact_user_id)
--
-- Retention rules:
--   moment_likes: keep the earliest like by created_at, then lowest id.
--   contacts: keep an active row first, then latest updated_at/created_at, then highest id.
--
-- The rows to be deleted are copied into backup tables before deletion:
--   moment_likes_duplicate_backup
--   contacts_duplicate_backup

-- 1) Scan current duplicate groups.
-- 核心逻辑：核心流程：扫描重复分组，先把待删除记录备份，再执行删除并复核唯一性。
SELECT
  'moment_likes' AS table_name,
  moment_id,
  user_id,
  COUNT(*) AS duplicate_count,
  GROUP_CONCAT(id ORDER BY created_at ASC, id ASC) AS ids
FROM moment_likes
GROUP BY moment_id, user_id
HAVING COUNT(*) > 1
ORDER BY duplicate_count DESC, moment_id, user_id;

SELECT
  'contacts' AS table_name,
  user_id,
  contact_user_id,
  COUNT(*) AS duplicate_count,
  SUM(status = 1) AS active_count,
  GROUP_CONCAT(id ORDER BY status = 1 DESC, updated_at DESC, created_at DESC, id DESC) AS ids
FROM contacts
GROUP BY user_id, contact_user_id
HAVING COUNT(*) > 1
ORDER BY duplicate_count DESC, user_id, contact_user_id;

-- 2) Backup duplicate rows that will be deleted.
CREATE TABLE IF NOT EXISTS moment_likes_duplicate_backup LIKE moment_likes;
CREATE TABLE IF NOT EXISTS contacts_duplicate_backup LIKE contacts;

CREATE TEMPORARY TABLE tmp_keep_moment_likes AS
SELECT id
FROM (
  SELECT
    id,
    ROW_NUMBER() OVER (
      PARTITION BY moment_id, user_id
      ORDER BY created_at ASC, id ASC
    ) AS rn
  FROM moment_likes
) ranked
WHERE rn = 1;

CREATE TEMPORARY TABLE tmp_duplicate_moment_likes AS
SELECT ml.id
FROM moment_likes ml
LEFT JOIN tmp_keep_moment_likes keep_rows ON keep_rows.id = ml.id
WHERE keep_rows.id IS NULL
  AND EXISTS (
    SELECT 1
    FROM moment_likes dup
    WHERE dup.moment_id = ml.moment_id
      AND dup.user_id = ml.user_id
      AND dup.id <> ml.id
  );

INSERT INTO moment_likes_duplicate_backup
SELECT ml.*
FROM moment_likes ml
JOIN tmp_duplicate_moment_likes d ON d.id = ml.id;

CREATE TEMPORARY TABLE tmp_keep_contacts AS
SELECT id
FROM (
  SELECT
    id,
    ROW_NUMBER() OVER (
      PARTITION BY user_id, contact_user_id
      ORDER BY status = 1 DESC, updated_at DESC, created_at DESC, id DESC
    ) AS rn
  FROM contacts
) ranked
WHERE rn = 1;

CREATE TEMPORARY TABLE tmp_duplicate_contacts AS
SELECT c.id
FROM contacts c
LEFT JOIN tmp_keep_contacts keep_rows ON keep_rows.id = c.id
WHERE keep_rows.id IS NULL
  AND EXISTS (
    SELECT 1
    FROM contacts dup
    WHERE dup.user_id = c.user_id
      AND dup.contact_user_id = c.contact_user_id
      AND dup.id <> c.id
  );

INSERT INTO contacts_duplicate_backup
SELECT c.*
FROM contacts c
JOIN tmp_duplicate_contacts d ON d.id = c.id;

-- 3) Delete duplicate rows.
START TRANSACTION;

DELETE ml
FROM moment_likes ml
JOIN tmp_duplicate_moment_likes d ON d.id = ml.id;

DELETE c
FROM contacts c
JOIN tmp_duplicate_contacts d ON d.id = c.id;

COMMIT;

-- 4) Verify no duplicate groups remain.
SELECT
  'moment_likes_remaining_duplicates' AS check_name,
  COUNT(*) AS duplicate_groups
FROM (
  SELECT moment_id, user_id
  FROM moment_likes
  GROUP BY moment_id, user_id
  HAVING COUNT(*) > 1
) d;

SELECT
  'contacts_remaining_duplicates' AS check_name,
  COUNT(*) AS duplicate_groups
FROM (
  SELECT user_id, contact_user_id
  FROM contacts
  GROUP BY user_id, contact_user_id
  HAVING COUNT(*) > 1
) d;
