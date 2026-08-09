-- 文件用途：scripts\p3_search_stats_indexes.sql 是一个数据库初始化、索引、数据修复或演示数据脚本。
-- 核心逻辑：按文件中的顺序执行配置加载、数据库变更、构建部署或维护操作，并保持可重复执行。

-- P3 search/statistics indexes for high-volume admin/search workloads.
-- Run during a low-traffic window after checking existing indexes with SHOW INDEX.
-- MySQL does not support CREATE INDEX IF NOT EXISTS consistently; skip statements
-- manually when the same index already exists.

-- Global search: contacts search and user lookup.
-- 核心逻辑：核心流程：按查询频率和业务场景创建索引，执行前检查已有索引，执行后用查询计划验证收益。
CREATE INDEX idx_contacts_user_status_updated
ON contacts (user_id, status, updated_at DESC, contact_user_id);

CREATE INDEX idx_contacts_user_contact_status
ON contacts (user_id, contact_user_id, status);

CREATE INDEX idx_users_nickname_deleted
ON users (nickname, deleted_at, id);

CREATE INDEX idx_users_status_created
ON users (status, created_at DESC, id DESC);

-- Chat search and visible chat windows.
CREATE INDEX idx_chats_status_type_created
ON chats (status, type, created_at DESC, id DESC);

CREATE INDEX idx_chats_username_status
ON chats (username, status, id);

-- Admin health trend and dashboard statistics.
CREATE INDEX idx_health_metric_snapshots_created_id
ON health_metric_snapshots (created_at DESC, id DESC);

CREATE INDEX idx_health_metric_snapshots_status_created
ON health_metric_snapshots (status, created_at DESC, id DESC);

-- User/device dashboard counts.
CREATE INDEX idx_user_devices_last_active_user
ON user_devices (last_active DESC, user_id);

-- MongoDB message collection indexes:
-- Execute the companion mongosh script in backend/scripts/p3_search_stats_mongo_indexes.js.
