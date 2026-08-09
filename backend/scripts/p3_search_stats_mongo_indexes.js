// 文件用途：scripts\p3_search_stats_mongo_indexes.js 是一个MongoDB 数据维护或演示数据脚本。
// 核心逻辑：按文件中的顺序执行配置加载、数据库变更、构建部署或维护操作，并保持可重复执行。

// P3 MongoDB indexes for monthly message collections.
// Usage:
//   mongosh "mongodb://USER:PASS@HOST:27017/genericim_messages?authSource=admin" \
//     backend/scripts/p3_search_stats_mongo_indexes.js
//
// The script scans messages and messages_YYYYMM collections and creates indexes
// used by message search, file search, delivered/read updates, and statistics.

// 核心逻辑：核心流程：读取脚本参数和数据源，执行批量维护操作，并将结果输出为可审计的日志。
const collections = db.getCollectionNames()
  .filter((name) => name === "messages" || /^messages_\d{6}$/.test(name))
  .sort()
  .reverse();

for (const name of collections) {
  const col = db.getCollection(name);
  print(`creating indexes on ${name}`);

  col.createIndex(
    { chat_id: 1, created_at: -1, msg_id: 1 },
    { name: "idx_chat_created_msg" }
  );

  col.createIndex(
    { chat_id: 1, seq: -1 },
    { name: "idx_chat_seq_desc" }
  );

  col.createIndex(
    { chat_id: 1, sender_id: 1, seq: 1, status: 1 },
    { name: "idx_chat_sender_seq_status" }
  );

  col.createIndex(
    { created_at: -1, type: 1 },
    { name: "idx_created_type" }
  );

  col.createIndex(
    { chat_id: 1, type: 1, "content.file.name": 1, created_at: -1 },
    { name: "idx_chat_file_name_created" }
  );

  // Optional: enable only after confirming the collection has no existing text index.
  // col.createIndex(
  //   { "content.text": "text" },
  //   {
  //     name: "idx_text_content",
  //     default_language: "none",
  //     weights: { "content.text": 1 },
  //   }
  // );
}

print(`processed ${collections.length} message collections`);
