-- 文件用途：scripts\p0_indexes.sql 是一个数据库初始化、索引、数据修复或演示数据脚本。
-- 核心逻辑：按文件中的顺序执行配置加载、数据库变更、构建部署或维护操作，并保持可重复执行。

-- P0 SQL indexes for high-frequency IM queries.
-- Run during a low-traffic window and verify with EXPLAIN before/after.
-- If an index already exists, skip that statement manually.

-- 核心逻辑：核心流程：按查询频率和业务场景创建索引，执行前检查已有索引，执行后用查询计划验证收益。
CREATE INDEX idx_user_chats_user_pin_sort
ON user_chats (user_id, is_pinned DESC, sort_time DESC, id DESC);

CREATE INDEX idx_chat_members_user_chat
ON chat_members (user_id, chat_id);

CREATE INDEX idx_chat_members_chat_role_joined
ON chat_members (chat_id, role DESC, joined_at ASC, user_id);

CREATE INDEX idx_moments_status_visibility_created
ON moments (status, visibility, created_at DESC, id DESC);

CREATE INDEX idx_moments_user_status_created
ON moments (user_id, status, created_at DESC, id DESC);

CREATE INDEX idx_moments_status_created
ON moments (status, created_at DESC, id DESC);

CREATE INDEX idx_transactions_user_created
ON transactions (user_id, created_at DESC, id DESC);

CREATE INDEX idx_transactions_user_type_created
ON transactions (user_id, type, created_at DESC, id DESC);
