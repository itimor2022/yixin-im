// 文件用途：scripts\seed_appstore_review_messages.js 是一个MongoDB 数据维护或演示数据脚本。
// 核心逻辑：按文件中的顺序执行配置加载、数据库变更、构建部署或维护操作，并保持可重复执行。

const reviewTag = 'appstore_review_20260723';
const reviewUser = '30000000-0000-0000-0000-000000000001';
const assistantUser = '30000000-0000-0000-0000-000000000002';
const coordinatorUser = '30000000-0000-0000-0000-000000000003';
const privateChat = '31000000-0000-0000-0000-000000000001';
const projectChat = '31000000-0000-0000-0000-000000000002';
const now = new Date();

db.messages.deleteMany({ seed_tag: reviewTag });

function message(id, chatId, seq, senderId, senderName, emoji, text, ageMinutes) {
  const createdAt = new Date(now.getTime() - ageMinutes * 60 * 1000);
  return {
    seed_tag: reviewTag,
    msg_id: id,
    chat_id: chatId,
    seq,
    sender_id: senderId,
    sender_name: senderName,
    sender_avatar: '',
    sender_emoji_avatar: emoji,
    sender_nickname_color: '#2563EB',
    type: 1,
    content: { text },
    status: 1,
    is_revoked: false,
    is_edited: false,
    deleted_for: [],
    created_at: createdAt,
    updated_at: createdAt
  };
}

db.messages.insertMany([
  message('32000000-0000-0000-0000-000000000001', privateChat, 1,
    assistantUser, '通用IM助手', '💬',
    '欢迎使用通用IM。你可以在这里体验消息发送、图片与文件分享等功能。', 180),
  message('32000000-0000-0000-0000-000000000002', privateChat, 2,
    reviewUser, '产品体验员', '🧑‍💼', '收到，我先了解一下主要功能。', 120),
  message('32000000-0000-0000-0000-000000000003', privateChat, 3,
    assistantUser, '通用IM助手', '💬',
    '如需帮助，可以随时发送消息，也可以在设置中查看隐私与安全选项。', 60),
  message('32000000-0000-0000-0000-000000000004', projectChat, 1,
    coordinatorUser, '项目协调员', '👩‍💼',
    '大家好，本周项目计划已更新，请查看群内进度。', 300),
  message('32000000-0000-0000-0000-000000000005', projectChat, 2,
    assistantUser, '通用IM助手', '💬',
    '文档与图片可以直接发到群内，方便成员集中协作。', 260),
  message('32000000-0000-0000-0000-000000000006', projectChat, 3,
    reviewUser, '产品体验员', '🧑‍💼',
    '好的，我会在今天整理需要跟进的事项。', 180),
  message('32000000-0000-0000-0000-000000000007', projectChat, 4,
    coordinatorUser, '项目协调员', '👩‍💼',
    '下午的沟通安排已经确认，相关内容会同步到群里。', 120)
]);

printjson({
  review_messages: db.messages.countDocuments({ seed_tag: reviewTag }),
  review_chats: db.messages.distinct('chat_id', { seed_tag: reviewTag }).length
});
