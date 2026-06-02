-- 壹信数据库初始化脚本
-- MySQL 8.0+

CREATE DATABASE IF NOT EXISTS 壹信DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

USE grimimim;

-- 用户表
CREATE TABLE IF NOT EXISTS users (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    uuid CHAR(36) NOT NULL UNIQUE,
    phone VARCHAR(20) NOT NULL UNIQUE,
    username VARCHAR(50) UNIQUE,
    nickname VARCHAR(100) NOT NULL,
    avatar VARCHAR(500),
    bio VARCHAR(500),
    status TINYINT DEFAULT 1 COMMENT '1:正常 0:禁用',
    last_seen DATETIME,
    created_at DATETIME NOT NULL,
    updated_at DATETIME NOT NULL,
    deleted_at DATETIME,
    INDEX idx_phone (phone),
    INDEX idx_username (username),
    INDEX idx_deleted_at (deleted_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 用户设备表
CREATE TABLE IF NOT EXISTS user_devices (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    user_id BIGINT UNSIGNED NOT NULL,
    device_id VARCHAR(100) NOT NULL,
    device_type VARCHAR(20) NOT NULL COMMENT 'ios/android/web/desktop',
    push_channel VARCHAR(20) DEFAULT NULL COMMENT 'apns/fcm/hms/xiaomi/oppo',
    device_name VARCHAR(100),
    push_token VARCHAR(2048),
    e2ee_public_key TEXT,
    e2ee_public_key_algo VARCHAR(64),
    e2ee_public_key_updated_at DATETIME,
    ip VARCHAR(50),
    location VARCHAR(100),
    last_active DATETIME,
    created_at DATETIME NOT NULL,
    INDEX idx_user_id (user_id),
    INDEX idx_device_id (device_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 用户关系表（好友）
CREATE TABLE IF NOT EXISTS user_relations (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    user_id BIGINT UNSIGNED NOT NULL,
    friend_id BIGINT UNSIGNED NOT NULL,
    status TINYINT DEFAULT 0 COMMENT '0:待确认 1:已添加 2:已拉黑',
    remark VARCHAR(100),
    created_at DATETIME NOT NULL,
    updated_at DATETIME NOT NULL,
    UNIQUE KEY idx_user_friend (user_id, friend_id),
    INDEX idx_friend_id (friend_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 会话表
CREATE TABLE IF NOT EXISTS chats (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    uuid CHAR(36) NOT NULL UNIQUE,
    type TINYINT NOT NULL COMMENT '1:私聊 2:群聊 3:频道',
    name VARCHAR(100),
    avatar VARCHAR(500),
    description VARCHAR(1000),
    owner_id BIGINT UNSIGNED,
    member_count INT DEFAULT 0,
    max_members INT DEFAULT 200,
    is_public BOOLEAN DEFAULT FALSE,
    invite_link VARCHAR(100) UNIQUE,
    can_send_message BOOLEAN DEFAULT TRUE,
    can_send_media BOOLEAN DEFAULT TRUE,
    can_send_links BOOLEAN DEFAULT TRUE,
    can_add_members BOOLEAN DEFAULT FALSE,
    can_pin_messages BOOLEAN DEFAULT FALSE,
    member_protection BOOLEAN DEFAULT FALSE,
    join_approval BOOLEAN DEFAULT FALSE,
    created_at DATETIME NOT NULL,
    updated_at DATETIME NOT NULL,
    deleted_at DATETIME,
    INDEX idx_owner_id (owner_id),
    INDEX idx_type (type),
    INDEX idx_deleted_at (deleted_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 发现页入口配置表
CREATE TABLE IF NOT EXISTS discover_items (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    title VARCHAR(100) NOT NULL,
    icon_url VARCHAR(500),
    url VARCHAR(1000) NOT NULL,
    sort INT DEFAULT 0,
    enabled BOOLEAN DEFAULT TRUE,
    created_at DATETIME NOT NULL,
    updated_at DATETIME NOT NULL,
    INDEX idx_discover_items_sort (sort),
    INDEX idx_discover_items_enabled (enabled),
    INDEX idx_discover_items_created_at (created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 会话成员表
CREATE TABLE IF NOT EXISTS chat_members (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    chat_id BIGINT UNSIGNED NOT NULL,
    user_id BIGINT UNSIGNED NOT NULL,
    role TINYINT DEFAULT 0 COMMENT '0:成员 1:管理员 2:创建者',
    nickname VARCHAR(100),
    is_muted BOOLEAN DEFAULT FALSE,
    is_pinned BOOLEAN DEFAULT FALSE,
    mute_end_time DATETIME,
    last_read_seq BIGINT UNSIGNED DEFAULT 0,
    joined_at DATETIME NOT NULL,
    updated_at DATETIME NOT NULL,
    UNIQUE KEY idx_chat_user (chat_id, user_id),
    INDEX idx_user_id (user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 用户会话列表
CREATE TABLE IF NOT EXISTS user_chats (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    user_id BIGINT UNSIGNED NOT NULL,
    chat_id BIGINT UNSIGNED NOT NULL,
    target_id BIGINT UNSIGNED COMMENT '私聊对方ID',
    last_msg_id BIGINT UNSIGNED DEFAULT 0,
    last_msg_seq BIGINT UNSIGNED DEFAULT 0,
    last_msg_time DATETIME,
    last_msg_text VARCHAR(200),
    unread_count INT DEFAULT 0,
    is_pinned BOOLEAN DEFAULT FALSE,
    is_muted BOOLEAN DEFAULT FALSE,
    is_archived BOOLEAN DEFAULT FALSE,
    sort_time DATETIME,
    updated_at DATETIME NOT NULL,
    UNIQUE KEY idx_user_chat (user_id, chat_id),
    INDEX idx_sort_time (sort_time),
    INDEX idx_target_id (target_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 管理员表
CREATE TABLE IF NOT EXISTS admins (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(50) NOT NULL UNIQUE,
    password VARCHAR(100) NOT NULL,
    nickname VARCHAR(100) NOT NULL,
    email VARCHAR(100) UNIQUE,
    avatar VARCHAR(500),
    role VARCHAR(20) NOT NULL DEFAULT 'admin' COMMENT 'super_admin/admin/operator',
    status TINYINT DEFAULT 1 COMMENT '1:正常 0:禁用',
    last_login_at DATETIME,
    last_login_ip VARCHAR(50),
    created_at DATETIME NOT NULL,
    updated_at DATETIME NOT NULL,
    deleted_at DATETIME,
    INDEX idx_role (role),
    INDEX idx_status (status),
    INDEX idx_deleted_at (deleted_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 管理员登录日志表
CREATE TABLE IF NOT EXISTS admin_login_logs (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    admin_id BIGINT UNSIGNED NOT NULL,
    ip VARCHAR(50),
    user_agent VARCHAR(500),
    status TINYINT DEFAULT 1 COMMENT '1:成功 0:失败',
    created_at DATETIME NOT NULL,
    INDEX idx_admin_id (admin_id),
    INDEX idx_created_at (created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 插入默认超级管理员 (用户名: admin, 密码: 123456)
-- 密码是 bcrypt 加密后的值
INSERT INTO admins (username, password, nickname, email, role, status, created_at, updated_at)
VALUES ('admin', '$2a$10$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy', '超级管理员', 'admin@grimimim.com', 'super_admin', 1, NOW(), NOW())
ON DUPLICATE KEY UPDATE updated_at = NOW();

-- 创建索引优化查询性能
ALTER TABLE users ADD INDEX idx_created_at (created_at);
ALTER TABLE chats ADD INDEX idx_created_at (created_at);
ALTER TABLE user_chats ADD INDEX idx_updated_at (updated_at);

-- chat_last_msg 群/私聊最新消息摘要表
CREATE TABLE IF NOT EXISTS `chat_last_msg` (
  `chat_id` varchar(36) NOT NULL,
  `last_seq` bigint unsigned NOT NULL DEFAULT '0',
  `last_msg_time` datetime NOT NULL,
  `last_msg_text` varchar(200) DEFAULT '',
  `last_msg_type` int NOT NULL DEFAULT '1',
  `last_msg_sender` varchar(100) DEFAULT '',
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`chat_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 关闭 only_full_group_by（MySQL 8.0 兼容）
SET GLOBAL sql_mode = 'STRICT_TRANS_TABLES,NO_ZERO_IN_DATE,NO_ZERO_DATE,ERROR_FOR_DIVISION_BY_ZERO,NO_ENGINE_SUBSTITUTION';
