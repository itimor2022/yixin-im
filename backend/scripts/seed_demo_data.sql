-- 文件用途：scripts\seed_demo_data.sql 是一个数据库初始化、索引、数据修复或演示数据脚本。
-- 核心逻辑：按文件中的顺序执行配置加载、数据库变更、构建部署或维护操作，并保持可重复执行。

-- Legacy demo seed intentionally disabled for production safety.
--
-- The former dataset created user-visible sample accounts, payment records,
-- risk samples, noisy conversations and unrelated square content. Re-running
-- it could restore content that is unsuitable for an App Store review build.
--
-- Use these curated scripts instead:
--   seed_appstore_review_account.sql
--   seed_square_release_notes_20260723.sql

-- 核心逻辑：核心流程：写入审核/演示环境所需的最小账号、消息或业务样例，并保持脚本可重复执行。
SET NAMES utf8mb4;
SELECT 'legacy_seed_disabled' AS status;
