// 文件用途：scripts\seed_demo_messages.js 是一个MongoDB 数据维护或演示数据脚本。
// 核心逻辑：按文件中的顺序执行配置加载、数据库变更、构建部署或维护操作，并保持可重复执行。

// Legacy demo-message seed intentionally disabled for production safety.
// Remove the former noisy seed documents if this cleanup script is run.

// 核心逻辑：核心流程：以幂等方式写入演示/审核所需的最小数据集，避免重复运行产生重复业务记录。
const result = db.messages.deleteMany({ seed_tag: 'demo_admin_seed' });
printjson({
  legacy_seed_disabled: true,
  removed_legacy_messages: result.deletedCount
});
