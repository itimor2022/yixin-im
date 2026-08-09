-- 文件用途：scripts\seed_appstore_review_account.sql 是一个数据库初始化、索引、数据修复或演示数据脚本。
-- 核心逻辑：按文件中的顺序执行配置加载、数据库变更、构建部署或维护操作，并保持可重复执行。

-- App Store 专用审核账号初始化
-- 明文密码不写入仓库；本文件仅保存 bcrypt 哈希。
-- 可重复执行：每次都会把审核账号重置为两个正常会话。

-- Keep string literals compatible with the existing production schema. Some
-- MySQL 8 installations default connections to utf8mb4_0900_ai_ci while the
-- deployed tables use utf8mb4_unicode_ci, which otherwise breaks comparisons.
-- 核心逻辑：核心流程：写入审核/演示环境所需的最小账号、消息或业务样例，并保持脚本可重复执行。
SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci;
START TRANSACTION;

SET @review_password_hash := '$2a$12$6/wUSBUM93cSXBhPePlN8.mwSmT7kYy8oM5VANjyeGWs29tf1uyCu';
SET @review_uuid := '30000000-0000-0000-0000-000000000001';
SET @assistant_uuid := '30000000-0000-0000-0000-000000000002';
SET @coordinator_uuid := '30000000-0000-0000-0000-000000000003';
SET @private_chat_uuid := '31000000-0000-0000-0000-000000000001';
SET @project_chat_uuid := '31000000-0000-0000-0000-000000000002';

SET @existing_review_id := (SELECT id FROM users WHERE BINARY username = BINARY 'appstore_review' LIMIT 1);
SET @existing_private_chat_id := (SELECT id FROM chats WHERE BINARY uuid = BINARY @private_chat_uuid LIMIT 1);
SET @existing_project_chat_id := (SELECT id FROM chats WHERE BINARY uuid = BINARY @project_chat_uuid LIMIT 1);

DELETE FROM user_devices WHERE user_id = @existing_review_id;
DELETE FROM contacts WHERE user_id = @existing_review_id OR contact_user_id = @existing_review_id;
DELETE FROM user_chats
WHERE user_id = @existing_review_id
   OR chat_id IN (@existing_private_chat_id, @existing_project_chat_id);
DELETE FROM chat_members WHERE chat_id IN (@existing_private_chat_id, @existing_project_chat_id);
DELETE FROM chats WHERE id IN (@existing_private_chat_id, @existing_project_chat_id);

INSERT INTO users (
  uuid, username, password, nickname, avatar, bio, status,
  last_seen, created_at, updated_at, deleted_at
)
VALUES
  (@review_uuid, 'appstore_review', @review_password_hash, '产品体验员', '',
   '体验即时沟通、团队协作与内容分享功能', 1, NOW(), NOW(), NOW(), NULL),
  (@assistant_uuid, 'genericim_assistant', @review_password_hash, '通用IM助手', '',
   '提供产品使用帮助与隐私安全指引', 1, NOW() - INTERVAL 5 MINUTE, NOW(), NOW(), NULL),
  (@coordinator_uuid, 'project_coordinator', @review_password_hash, '项目协调员', '',
   '负责项目进度与团队协作', 1, NOW() - INTERVAL 15 MINUTE, NOW(), NOW(), NULL)
ON DUPLICATE KEY UPDATE
  password = VALUES(password),
  nickname = VALUES(nickname),
  avatar = VALUES(avatar),
  bio = VALUES(bio),
  status = 1,
  ban_reason = '',
  banned_at = NULL,
  updated_at = NOW(),
  deleted_at = NULL;

SET @review_id := (SELECT id FROM users WHERE BINARY username = BINARY 'appstore_review' LIMIT 1);
SET @assistant_id := (SELECT id FROM users WHERE BINARY username = BINARY 'genericim_assistant' LIMIT 1);
SET @coordinator_id := (SELECT id FROM users WHERE BINARY username = BINARY 'project_coordinator' LIMIT 1);

INSERT INTO chats (
  uuid, type, name, avatar, description, owner_id, member_count,
  max_members, is_public, invite_link, username, status,
  can_send_message, can_send_media, can_send_links, can_add_members,
  can_pin_messages, member_protection, join_approval, created_at, updated_at, deleted_at
)
VALUES
  (@private_chat_uuid, 1, '', '', '', @assistant_id, 2, 2, 0,
   'app-review-assistant', '', 0, 1, 1, 1, 0, 0, 0, 0,
   NOW() - INTERVAL 3 DAY, NOW(), NULL),
  (@project_chat_uuid, 2, '项目协作群',
   '/uploads/square/release-20260723/project-workshop.jpg',
   '沟通项目进度、文件协作与会议安排', @coordinator_id, 3, 50, 0,
   'app-review-project', 'project_collaboration', 0, 1, 1, 1, 0, 1, 0, 0,
   NOW() - INTERVAL 3 DAY, NOW(), NULL)
ON DUPLICATE KEY UPDATE
  name = VALUES(name),
  avatar = VALUES(avatar),
  description = VALUES(description),
  owner_id = VALUES(owner_id),
  member_count = VALUES(member_count),
  max_members = VALUES(max_members),
  is_public = VALUES(is_public),
  status = 0,
  can_send_message = 1,
  can_send_media = 1,
  can_send_links = 1,
  updated_at = NOW(),
  deleted_at = NULL;

SET @private_chat_id := (SELECT id FROM chats WHERE BINARY uuid = BINARY @private_chat_uuid LIMIT 1);
SET @project_chat_id := (SELECT id FROM chats WHERE BINARY uuid = BINARY @project_chat_uuid LIMIT 1);

INSERT INTO contacts (user_id, contact_user_id, remark, status, created_at, updated_at)
VALUES
  (@review_id, @assistant_id, '通用IM助手', 1, NOW(), NOW()),
  (@assistant_id, @review_id, '产品体验员', 1, NOW(), NOW()),
  (@review_id, @coordinator_id, '项目协调员', 1, NOW(), NOW()),
  (@coordinator_id, @review_id, '产品体验员', 1, NOW(), NOW());

INSERT INTO chat_members (
  chat_id, user_id, role, nickname, is_muted, is_pinned,
  last_read_seq, joined_at, updated_at
)
VALUES
  (@private_chat_id, @review_id, 0, '', 0, 0, 3, NOW() - INTERVAL 3 DAY, NOW()),
  (@private_chat_id, @assistant_id, 0, '', 0, 0, 3, NOW() - INTERVAL 3 DAY, NOW()),
  (@project_chat_id, @review_id, 0, '', 0, 0, 4, NOW() - INTERVAL 3 DAY, NOW()),
  (@project_chat_id, @assistant_id, 0, '', 0, 0, 4, NOW() - INTERVAL 3 DAY, NOW()),
  (@project_chat_id, @coordinator_id, 2, '', 0, 0, 4, NOW() - INTERVAL 3 DAY, NOW());

INSERT INTO user_chats (
  user_id, chat_id, target_id, last_msg_id, last_msg_seq,
  last_msg_time, last_msg_text, last_msg_media_url, last_msg_type,
  unread_count, is_pinned, is_muted, is_archived,
  cleared_at, sort_time, updated_at
)
VALUES
  (@review_id, @private_chat_id, @assistant_id, 0, 3,
   NOW() - INTERVAL 1 HOUR,
   '如需帮助，可以随时发送消息，也可以在设置中查看隐私与安全选项。',
   '', 1, 0, 1, 0, 0, NULL, NOW() - INTERVAL 1 HOUR, NOW()),
  (@review_id, @project_chat_id, 0, 0, 4,
   NOW() - INTERVAL 2 HOUR,
   '下午的沟通安排已经确认，相关内容会同步到群里。',
   '', 1, 0, 0, 0, 0, NULL, NOW() - INTERVAL 2 HOUR, NOW()),
  (@assistant_id, @private_chat_id, @review_id, 0, 3,
   NOW() - INTERVAL 1 HOUR,
   '如需帮助，可以随时发送消息，也可以在设置中查看隐私与安全选项。',
   '', 1, 0, 0, 0, 0, NULL, NOW() - INTERVAL 1 HOUR, NOW()),
  (@assistant_id, @project_chat_id, 0, 0, 4,
   NOW() - INTERVAL 2 HOUR,
   '下午的沟通安排已经确认，相关内容会同步到群里。',
   '', 1, 0, 0, 0, 0, NULL, NOW() - INTERVAL 2 HOUR, NOW()),
  (@coordinator_id, @project_chat_id, 0, 0, 4,
   NOW() - INTERVAL 2 HOUR,
   '下午的沟通安排已经确认，相关内容会同步到群里。',
   '', 1, 0, 0, 0, 0, NULL, NOW() - INTERVAL 2 HOUR, NOW())
ON DUPLICATE KEY UPDATE
  target_id = VALUES(target_id),
  last_msg_seq = VALUES(last_msg_seq),
  last_msg_time = VALUES(last_msg_time),
  last_msg_text = VALUES(last_msg_text),
  last_msg_media_url = VALUES(last_msg_media_url),
  last_msg_type = VALUES(last_msg_type),
  unread_count = 0,
  is_archived = 0,
  cleared_at = NULL,
  sort_time = VALUES(sort_time),
  updated_at = NOW();

COMMIT;

SELECT u.username, u.nickname, COUNT(uc.id) AS visible_conversations
FROM users u
LEFT JOIN user_chats uc ON uc.user_id = u.id AND uc.is_archived = 0
WHERE BINARY u.username = BINARY 'appstore_review'
GROUP BY u.id, u.username, u.nickname;
