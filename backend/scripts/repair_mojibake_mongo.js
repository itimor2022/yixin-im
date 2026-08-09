// 文件用途：scripts\repair_mojibake_mongo.js 是一个MongoDB 数据维护或演示数据脚本。
// 核心逻辑：按文件中的顺序执行配置加载、数据库变更、构建部署或维护操作，并保持可重复执行。

// Repair historical mojibake in MongoDB message collections.
// Usage: mongosh "<mongo-uri>/<database>" backend/scripts/repair_mojibake_mongo.js

// 核心逻辑：核心流程：读取目标集合中的历史数据，按映射规则批量修复字段并记录处理结果。
const legacyVoiceCall = String.fromCodePoint(0x7487, 0xe162, 0x7176, 0x95ab, 0x6c33, 0x763d);
const legacyVideoCall = String.fromCodePoint(0x7459, 0x55db, 0xe576, 0x95ab, 0x6c33, 0x763d);
const legacySystemSender = String.fromCodePoint(0x7eef, 0x837b, 0x7cba, 0x5a11, 0x581f, 0x4f05);
const legacyCallJoin = String.fromCodePoint(0x95ab);
const legacyCallEnd = String.fromCodePoint(0x763d);
const legacyVoiceMarkerA = String.fromCodePoint(0x7487);
const legacyVoiceMarkerB = String.fromCodePoint(0x7176);
const legacyVideoMarkerA = String.fromCodePoint(0x7459);
const legacyVideoMarkerB = String.fromCodePoint(0xe576);

function escapeRegex(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

const exactPattern = new RegExp(
  [legacyVoiceCall, legacyVideoCall, legacySystemSender].map(escapeRegex).join("|"),
);

function repairText(value) {
  if (typeof value !== "string" || value.length === 0) return value;

  let repaired = value
    .split(legacySystemSender).join("系统消息")
    .split(legacyVoiceCall).join("语音通话")
    .split(legacyVideoCall).join("视频通话");

  const looksLikeCall =
    repaired.includes(legacyCallJoin) &&
    repaired.includes(legacyCallEnd) &&
    (
      repaired.includes(legacyVoiceMarkerA) ||
      repaired.includes(legacyVoiceMarkerB) ||
      repaired.includes(legacyVideoMarkerA) ||
      repaired.includes(legacyVideoMarkerB)
    );
  if (!looksLikeCall) return repaired;

  const label =
    repaired.includes(legacyVideoMarkerA) || repaired.includes(legacyVideoMarkerB)
      ? "视频通话"
      : "语音通话";
  const duration = repaired.match(/\d{1,2}:\d{2}(?::\d{2})?/);
  return duration ? `${label} ${duration[0]}` : label;
}

function setIfChanged(update, path, before, after) {
  if (before !== after) update[path] = after;
}

const collections = db.getCollectionNames().filter((name) => /^messages_\d{6}$/.test(name));
let totalChanged = 0;

for (const name of collections) {
  const collection = db.getCollection(name);
  let changed = 0;
  const cursor = collection.find({
    $or: [
      { "content.text": exactPattern },
      { "sender_name": exactPattern },
      { "reply_to.content": exactPattern },
      { "reply_to.sender_name": exactPattern },
    ],
  });

  cursor.forEach((doc) => {
    const update = {};
    setIfChanged(update, "content.text", doc.content?.text, repairText(doc.content?.text));
    setIfChanged(update, "sender_name", doc.sender_name, repairText(doc.sender_name));
    setIfChanged(update, "reply_to.content", doc.reply_to?.content, repairText(doc.reply_to?.content));
    setIfChanged(update, "reply_to.sender_name", doc.reply_to?.sender_name, repairText(doc.reply_to?.sender_name));

    if (Object.keys(update).length > 0) {
      collection.updateOne({ _id: doc._id }, { $set: update });
      changed += 1;
    }
  });

  totalChanged += changed;
  print(`${name}: repaired=${changed}`);
}

print(`total_repaired=${totalChanged}`);
