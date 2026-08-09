-- 文件用途：scripts\p1_diagnostic_indexes.sql 是一个数据库初始化、索引、数据修复或演示数据脚本。
-- 核心逻辑：按文件中的顺序执行配置加载、数据库变更、构建部署或维护操作，并保持可重复执行。

-- P1 diagnostic indexes for admin security and push diagnostics.
-- Run during a low-traffic window after checking existing indexes:
--   SHOW INDEX FROM admin_login_logs;
--   SHOW INDEX FROM push_delivery_logs;
--   SHOW INDEX FROM user_devices;
-- MySQL does not support CREATE INDEX IF NOT EXISTS consistently, so skip
-- any statement manually when the index already exists.

-- 核心逻辑：核心流程：按查询频率和业务场景创建索引，执行前检查已有索引，执行后用查询计划验证收益。
CREATE INDEX idx_admin_login_logs_created_id
ON admin_login_logs (created_at DESC, id DESC);

CREATE INDEX idx_admin_login_logs_status_created
ON admin_login_logs (status, created_at DESC, id DESC);

CREATE INDEX idx_admin_login_logs_throttle_created
ON admin_login_logs (throttle_applied, created_at DESC, id DESC);

CREATE INDEX idx_push_delivery_logs_occurred_id
ON push_delivery_logs (occurred_at DESC, id DESC);

CREATE INDEX idx_push_delivery_logs_success_occurred
ON push_delivery_logs (success, occurred_at DESC, id DESC);

CREATE INDEX idx_push_delivery_logs_user_occurred
ON push_delivery_logs (user_id, occurred_at DESC, id DESC);

CREATE INDEX idx_push_delivery_logs_device_occurred
ON push_delivery_logs (device_id, occurred_at DESC, id DESC);

CREATE INDEX idx_push_delivery_logs_channel_occurred
ON push_delivery_logs (channel, occurred_at DESC, id DESC);

CREATE INDEX idx_user_devices_user_last_active
ON user_devices (user_id, last_active DESC, id DESC);
