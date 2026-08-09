// 文件用途：scripts\check_mojibake_remaining_mongo.js 是一个MongoDB 数据维护或演示数据脚本。
// 核心逻辑：按文件中的顺序执行配置加载、数据库变更、构建部署或维护操作，并保持可重复执行。

const legacyVoiceCall = String.fromCodePoint(0x7487, 0xe162, 0x7176, 0x95ab, 0x6c33, 0x763d);
const legacyVideoCall = String.fromCodePoint(0x7459, 0x55db, 0xe576, 0x95ab, 0x6c33, 0x763d);
const legacySystemSender = String.fromCodePoint(0x7eef, 0x837b, 0x7cba, 0x5a11, 0x581f, 0x4f05);

function escapeRegex(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

const pattern = new RegExp(
  [legacyVoiceCall, legacyVideoCall, legacySystemSender].map(escapeRegex).join("|"),
);

let total = 0;
db.getCollectionNames()
  .filter((name) => /^messages_\d{6}$/.test(name))
  .forEach((name) => {
    const count = db.getCollection(name).countDocuments({
      $or: [
        { "content.text": pattern },
        { sender_name: pattern },
        { "reply_to.content": pattern },
        { "reply_to.sender_name": pattern },
      ],
    });
    print(`${name}: remaining=${count}`);
    total += count;
  });

print(`mongo_remaining=${total}`);
