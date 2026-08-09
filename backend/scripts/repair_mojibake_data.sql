-- 文件用途：scripts\repair_mojibake_data.sql 是一个数据库初始化、索引、数据修复或演示数据脚本。
-- 核心逻辑：按文件中的顺序执行配置加载、数据库变更、构建部署或维护操作，并保持可重复执行。

-- Repair historical mojibake in MySQL chat previews and push logs.
-- Run against the application database after taking a backup.

-- 核心逻辑：核心流程：定位历史乱码值，按固定映射更新数据，并通过统计结果确认修复范围。
START TRANSACTION;

SET @mojibake_voice_call = CONVERT(UNHEX('E79287EE85A2E785B6E996ABE6B0B3E798BD') USING utf8mb4) COLLATE utf8mb4_unicode_ci;
SET @mojibake_video_call = CONVERT(UNHEX('E79199E5979BEE95B6E996ABE6B0B3E798BD') USING utf8mb4) COLLATE utf8mb4_unicode_ci;
SET @mojibake_system_sender = CONVERT(UNHEX('E7BBAFE88DBBE7B2BAE5A891E5A09FE4BC85') USING utf8mb4) COLLATE utf8mb4_unicode_ci;

UPDATE user_chats
SET
  last_msg_text = REPLACE(REPLACE(last_msg_text, @mojibake_voice_call, '语音通话'), @mojibake_video_call, '视频通话'),
  last_msg_sender = REPLACE(last_msg_sender, @mojibake_system_sender, '系统消息')
WHERE
  last_msg_text LIKE CONCAT('%', @mojibake_voice_call, '%')
  OR last_msg_text LIKE CONCAT('%', @mojibake_video_call, '%')
  OR last_msg_sender LIKE CONCAT('%', @mojibake_system_sender, '%');

SELECT ROW_COUNT() AS user_chats_rows_repaired;

UPDATE push_delivery_logs
SET
  title = REPLACE(REPLACE(REPLACE(title, @mojibake_system_sender, '系统消息'), @mojibake_voice_call, '语音通话'), @mojibake_video_call, '视频通话'),
  body = REPLACE(REPLACE(REPLACE(body, @mojibake_system_sender, '系统消息'), @mojibake_voice_call, '语音通话'), @mojibake_video_call, '视频通话'),
  error = REPLACE(REPLACE(REPLACE(error, @mojibake_system_sender, '系统消息'), @mojibake_voice_call, '语音通话'), @mojibake_video_call, '视频通话')
WHERE
  title LIKE CONCAT('%', @mojibake_system_sender, '%')
  OR title LIKE CONCAT('%', @mojibake_voice_call, '%')
  OR title LIKE CONCAT('%', @mojibake_video_call, '%')
  OR body LIKE CONCAT('%', @mojibake_system_sender, '%')
  OR body LIKE CONCAT('%', @mojibake_voice_call, '%')
  OR body LIKE CONCAT('%', @mojibake_video_call, '%')
  OR error LIKE CONCAT('%', @mojibake_system_sender, '%')
  OR error LIKE CONCAT('%', @mojibake_voice_call, '%')
  OR error LIKE CONCAT('%', @mojibake_video_call, '%');

SELECT ROW_COUNT() AS push_delivery_logs_rows_repaired;

COMMIT;
