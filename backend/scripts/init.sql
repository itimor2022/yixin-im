-- 文件用途：scripts\init.sql 是一个数据库初始化、索引、数据修复或演示数据脚本。
-- 核心逻辑：按文件中的顺序执行配置加载、数据库变更、构建部署或维护操作，并保持可重复执行。

-- 通用IM数据库初始化脚本
-- MySQL 8.0+

-- 核心逻辑：核心流程：按表结构、索引、约束和默认数据的顺序初始化数据库，保证服务启动所需的基础数据完整。
CREATE DATABASE IF NOT EXISTS genericim DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

USE genericim;

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
    brand VARCHAR(50) DEFAULT '' COMMENT '设备厂商',
    model VARCHAR(100) DEFAULT '' COMMENT '设备型号',
    push_channel VARCHAR(20) NOT NULL DEFAULT '' COMMENT 'apns/apns_voip/fcm/hms/jpush/xiaomi/oppo/webpush',
    device_name VARCHAR(100),
    push_token TEXT,
    push_token_hash CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NULL,
    app_version VARCHAR(50) DEFAULT '',
    push_token_updated_at DATETIME,
    e2ee_public_key TEXT,
    e2ee_public_key_algo VARCHAR(64),
    e2ee_public_key_updated_at DATETIME,
    ip VARCHAR(50),
    location VARCHAR(100),
    last_active DATETIME,
    created_at DATETIME NOT NULL,
    UNIQUE KEY uk_user_device (user_id, device_id),
    UNIQUE KEY uk_push_channel_token_hash (push_channel, push_token_hash),
    INDEX idx_user_id (user_id),
    INDEX idx_device_id (device_id),
    INDEX idx_push_token_hash (push_token_hash)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 推送投递日志
CREATE TABLE IF NOT EXISTS push_delivery_logs (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    user_id BIGINT UNSIGNED NOT NULL,
    device_id BIGINT UNSIGNED NOT NULL,
    device_key VARCHAR(100),
    channel VARCHAR(20),
    provider VARCHAR(20),
    scene VARCHAR(50),
    request_id VARCHAR(100),
    success TINYINT(1) NOT NULL DEFAULT 0,
    error VARCHAR(512),
    title VARCHAR(120),
    body VARCHAR(255),
    occurred_at DATETIME NOT NULL,
    created_at DATETIME NOT NULL,
    INDEX idx_user_id (user_id),
    INDEX idx_device_id (device_id),
    INDEX idx_channel (channel),
    INDEX idx_provider (provider),
    INDEX idx_scene (scene),
    INDEX idx_success (success),
    INDEX idx_occurred_at (occurred_at)
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

-- 发现页轮播图配置表
CREATE TABLE IF NOT EXISTS discover_banners (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    title VARCHAR(100) NOT NULL,
    image_url VARCHAR(500) NOT NULL,
    url VARCHAR(1000),
    sort INT DEFAULT 0,
    enabled BOOLEAN DEFAULT TRUE,
    created_at DATETIME NOT NULL,
    updated_at DATETIME NOT NULL,
    INDEX idx_discover_banners_sort (sort),
    INDEX idx_discover_banners_enabled (enabled),
    INDEX idx_discover_banners_created_at (created_at)
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
    INDEX idx_user_id (user_id),
    INDEX idx_chat_members_user_chat (user_id, chat_id),
    INDEX idx_chat_members_chat_role_joined (chat_id, role DESC, joined_at ASC, user_id)
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
    last_msg_media_url VARCHAR(500),
    unread_count INT DEFAULT 0,
    is_pinned BOOLEAN DEFAULT FALSE,
    is_muted BOOLEAN DEFAULT FALSE,
    is_archived BOOLEAN DEFAULT FALSE,
    sort_time DATETIME,
    updated_at DATETIME NOT NULL,
    UNIQUE KEY idx_user_chat (user_id, chat_id),
    INDEX idx_user_chats_user_pin_sort (user_id, is_pinned DESC, sort_time DESC, id DESC),
    INDEX idx_sort_time (sort_time),
    INDEX idx_target_id (target_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- VIP会员套餐
CREATE TABLE IF NOT EXISTS vip_plans (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    code VARCHAR(32) NOT NULL UNIQUE,
    name VARCHAR(50) NOT NULL,
    level TINYINT NOT NULL COMMENT '1:VIP 2:SVIP',
    duration_days INT NOT NULL DEFAULT 30,
    price DECIMAL(12,2) NOT NULL DEFAULT 0,
    original_price DECIMAL(12,2) NOT NULL DEFAULT 0,
    benefits_json LONGTEXT,
    description VARCHAR(500),
    sort INT DEFAULT 0,
    enabled TINYINT(1) NOT NULL DEFAULT 1,
    created_at DATETIME NOT NULL,
    updated_at DATETIME NOT NULL,
    deleted_at DATETIME,
    UNIQUE KEY idx_vip_plans_code (code),
    INDEX idx_vip_plans_level (level),
    INDEX idx_vip_plans_sort (sort),
    INDEX idx_vip_plans_enabled (enabled),
    INDEX idx_vip_plans_deleted_at (deleted_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 用户VIP会员
CREATE TABLE IF NOT EXISTS user_vip_memberships (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    user_id BIGINT UNSIGNED NOT NULL UNIQUE,
    plan_id BIGINT UNSIGNED,
    level TINYINT NOT NULL DEFAULT 0,
    source VARCHAR(20) NOT NULL DEFAULT 'manual',
    status VARCHAR(20) NOT NULL DEFAULT 'active',
    started_at DATETIME NOT NULL,
    expired_at DATETIME NOT NULL,
    canceled_at DATETIME,
    remark VARCHAR(500),
    created_at DATETIME NOT NULL,
    updated_at DATETIME NOT NULL,
    UNIQUE KEY idx_user_vip_memberships_user_id (user_id),
    INDEX idx_user_vip_memberships_plan_id (plan_id),
    INDEX idx_user_vip_memberships_level (level),
    INDEX idx_user_vip_memberships_status (status),
    INDEX idx_user_vip_memberships_expired_at (expired_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- VIP会员订单
CREATE TABLE IF NOT EXISTS vip_orders (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    order_no VARCHAR(64) NOT NULL UNIQUE,
    user_id BIGINT UNSIGNED NOT NULL,
    plan_id BIGINT UNSIGNED NOT NULL,
    amount DECIMAL(12,2) NOT NULL DEFAULT 0,
    pay_method VARCHAR(20) NOT NULL DEFAULT 'wallet',
    status VARCHAR(20) NOT NULL DEFAULT 'pending',
    paid_at DATETIME,
    canceled_at DATETIME,
    transaction_id VARCHAR(64),
    remark VARCHAR(500),
    created_at DATETIME NOT NULL,
    updated_at DATETIME NOT NULL,
    UNIQUE KEY idx_vip_orders_order_no (order_no),
    INDEX idx_vip_orders_user_id (user_id),
    INDEX idx_vip_orders_plan_id (plan_id),
    INDEX idx_vip_orders_pay_method (pay_method),
    INDEX idx_vip_orders_status (status),
    INDEX idx_vip_orders_transaction_id (transaction_id),
    INDEX idx_vip_orders_created_at (created_at)
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
VALUES ('admin', '$2a$10$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy', '超级管理员', NULL, 'super_admin', 1, NOW(), NOW())
ON DUPLICATE KEY UPDATE
    email = IF(email IS NULL OR email IN ('', 'admin@example.invalid'), NULL, email),
    updated_at = NOW();

-- 默认VIP会员套餐
INSERT INTO vip_plans (code, name, level, duration_days, price, original_price, benefits_json, description, sort, enabled, created_at, updated_at)
VALUES
('vip_month', 'VIP 月卡', 1, 30, 18.00, 30.00, '{"can_create_group":true,"can_create_channel":false,"max_owned_groups":5,"max_owned_channels":0,"max_group_members":500,"max_channel_members":0,"max_pinned_chats":10,"upload_image_limit_mb":20,"upload_video_limit_mb":300,"upload_voice_limit_mb":50,"upload_file_limit_mb":500,"can_set_public_username":false,"can_enable_member_protection":false,"badge":"VIP"}', '适合日常建群和文件传输', 10, 1, NOW(), NOW()),
('vip_year', 'VIP 年卡', 1, 365, 168.00, 216.00, '{"can_create_group":true,"can_create_channel":false,"max_owned_groups":5,"max_owned_channels":0,"max_group_members":500,"max_channel_members":0,"max_pinned_chats":10,"upload_image_limit_mb":20,"upload_video_limit_mb":300,"upload_voice_limit_mb":50,"upload_file_limit_mb":500,"can_set_public_username":false,"can_enable_member_protection":false,"badge":"VIP"}', 'VIP 权益一年有效', 20, 1, NOW(), NOW()),
('svip_month', 'SVIP 月卡', 2, 30, 38.00, 58.00, '{"can_create_group":true,"can_create_channel":true,"max_owned_groups":20,"max_owned_channels":10,"max_group_members":1000,"max_channel_members":5000,"max_pinned_chats":20,"upload_image_limit_mb":50,"upload_video_limit_mb":1024,"upload_voice_limit_mb":100,"upload_file_limit_mb":2048,"can_set_public_username":true,"can_enable_member_protection":true,"badge":"SVIP"}', '适合需要频道和更高容量的用户', 30, 1, NOW(), NOW()),
('svip_year', 'SVIP 年卡', 2, 365, 368.00, 456.00, '{"can_create_group":true,"can_create_channel":true,"max_owned_groups":20,"max_owned_channels":10,"max_group_members":1000,"max_channel_members":5000,"max_pinned_chats":20,"upload_image_limit_mb":50,"upload_video_limit_mb":1024,"upload_voice_limit_mb":100,"upload_file_limit_mb":2048,"can_set_public_username":true,"can_enable_member_protection":true,"badge":"SVIP"}', 'SVIP 权益一年有效', 40, 1, NOW(), NOW())
ON DUPLICATE KEY UPDATE updated_at = NOW();

-- 创建索引优化查询性能
ALTER TABLE users ADD INDEX idx_created_at (created_at);
ALTER TABLE chats ADD INDEX idx_created_at (created_at);
ALTER TABLE user_chats ADD INDEX idx_updated_at (updated_at);
