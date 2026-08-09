-- 文件用途：scripts\check_mojibake_remaining.sql 是一个数据库初始化、索引、数据修复或演示数据脚本。
-- 核心逻辑：按文件中的顺序执行配置加载、数据库变更、构建部署或维护操作，并保持可重复执行。

SET @mojibake_voice_call = CONVERT(UNHEX('E79287EE85A2E785B6E996ABE6B0B3E798BD') USING utf8mb4) COLLATE utf8mb4_unicode_ci;
SET @mojibake_video_call = CONVERT(UNHEX('E79199E5979BEE95B6E996ABE6B0B3E798BD') USING utf8mb4) COLLATE utf8mb4_unicode_ci;
SET @mojibake_system_sender = CONVERT(UNHEX('E7BBAFE88DBBE7B2BAE5A891E5A09FE4BC85') USING utf8mb4) COLLATE utf8mb4_unicode_ci;

SELECT COUNT(*) AS user_chats_remaining
FROM user_chats
WHERE
  last_msg_text LIKE CONCAT('%', @mojibake_voice_call, '%')
  OR last_msg_text LIKE CONCAT('%', @mojibake_video_call, '%')
  OR last_msg_sender LIKE CONCAT('%', @mojibake_system_sender, '%');

SELECT COUNT(*) AS push_delivery_logs_remaining
FROM push_delivery_logs
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
