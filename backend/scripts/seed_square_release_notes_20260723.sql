-- 文件用途：scripts\seed_square_release_notes_20260723.sql 是一个数据库初始化、索引、数据修复或演示数据脚本。
-- 核心逻辑：按文件中的顺序执行配置加载、数据库变更、构建部署或维护操作，并保持可重复执行。

-- 通用IM广场近期更新日志内容
-- 用途：隐藏旧的公开广场内容，并写入统一的协同办公主题更新日志。
-- 特性：不物理删除旧内容；可重复执行；不会重复插入。

-- 核心逻辑：核心流程：写入审核/演示环境所需的最小账号、消息或业务样例，并保持脚本可重复执行。
SET NAMES utf8mb4;
START TRANSACTION;

SET @square_user_id := COALESCE(
  (
    SELECT u.id
    FROM official_users ou
    INNER JOIN users u ON u.id = ou.user_id
    WHERE ou.deleted_at IS NULL
      AND u.deleted_at IS NULL
      AND u.status = 1
    ORDER BY ou.sort_order DESC, ou.id ASC
    LIMIT 1
  ),
  (
    SELECT id
    FROM users
    WHERE username = 'demo'
      AND deleted_at IS NULL
      AND status = 1
    LIMIT 1
  ),
  (
    SELECT id
    FROM users
    WHERE deleted_at IS NULL
      AND status = 1
    ORDER BY id ASC
    LIMIT 1
  )
);

-- 保留旧内容和互动关系，仅从公开广场隐藏，便于必要时回退。
UPDATE moments
SET status = 2,
    updated_at = NOW()
WHERE visibility = 1
  AND @square_user_id IS NOT NULL
  AND deleted_at IS NULL
  AND status IN (0, 1)
  AND uuid NOT IN (
    'release-20260723-login',
    'release-20260723-square',
    'release-20260723-cross-platform',
    'release-20260723-message',
    'release-20260723-collaboration',
    'release-20260723-security'
  );

INSERT INTO moments (
  uuid,
  user_id,
  content,
  content_type,
  media_urls,
  video_thumbnail,
  topics,
  visibility,
  selected_contacts,
  like_count,
  comment_count,
  share_count,
  view_count,
  status,
  location,
  created_at,
  updated_at,
  deleted_at
)
SELECT
  item.uuid,
  @square_user_id,
  item.content,
  2,
  JSON_ARRAY(item.image_url),
  '',
  JSON_ARRAY('版本更新', '协同办公'),
  1,
  JSON_ARRAY(),
  0,
  0,
  0,
  0,
  1,
  '',
  NOW() - INTERVAL item.age_hour HOUR,
  NOW(),
  NULL
FROM (
  SELECT
    'release-20260723-login' AS uuid,
    '版本更新｜移动端登录与启动体验优化\n\n本次更新进一步优化首次安装后的启动与登录流程，完善网络初始化和状态恢复，让新设备首次打开应用时也能更顺畅地进入工作空间。' AS content,
    '/uploads/square/release-20260723/team-planning.jpg' AS image_url,
    2 AS age_hour
  UNION ALL
  SELECT
    'release-20260723-square',
    '版本更新｜广场浏览体验优化\n\n广场现在会优先展示图片封面，媒体内容在需要时再加载；离开当前内容后会及时释放资源，信息流浏览更加轻快，工作动态也能更快呈现。',
    '/uploads/square/release-20260723/project-workshop.jpg',
    8
  UNION ALL
  SELECT
    'release-20260723-cross-platform',
    '版本更新｜多端协同体验升级\n\nAndroid、Windows 与网页端的连接和界面体验得到统一优化。无论在办公室电脑还是移动设备上，都可以自然衔接会话、联系人和团队协作内容。',
    '/uploads/square/release-20260723/modern-workspace.jpg',
    20
  UNION ALL
  SELECT
    'release-20260723-message',
    '版本更新｜消息与会话体验优化\n\n本次更新加强消息同步、会话恢复和群聊资料刷新。切换设备或重新进入会话时，联系人信息与聊天内容的展示更加稳定、清晰。',
    '/uploads/square/release-20260723/business-discussion.jpg',
    32
  UNION ALL
  SELECT
    'release-20260723-collaboration',
    '版本更新｜团队协作能力完善\n\n群组、频道和文件分享流程持续优化。项目成员可以在同一工作空间内沟通进度、共享资料并跟进事项，让日常协作更连贯。',
    '/uploads/square/release-20260723/team-meeting.jpg',
    48
  UNION ALL
  SELECT
    'release-20260723-security',
    '版本更新｜账号安全与隐私保护增强\n\n设备管理、账号状态隔离和消息保护能力进一步完善。用户可以更安心地管理登录设备，并在不同工作场景中保持清晰的数据边界。',
    '/uploads/square/release-20260723/office-collaboration.jpg',
    72
) AS item
WHERE @square_user_id IS NOT NULL
ON DUPLICATE KEY UPDATE
  user_id = VALUES(user_id),
  content = VALUES(content),
  content_type = VALUES(content_type),
  media_urls = VALUES(media_urls),
  video_thumbnail = VALUES(video_thumbnail),
  topics = VALUES(topics),
  visibility = VALUES(visibility),
  selected_contacts = VALUES(selected_contacts),
  like_count = 0,
  comment_count = 0,
  share_count = 0,
  view_count = 0,
  status = 1,
  location = '',
  updated_at = NOW(),
  deleted_at = NULL;

COMMIT;

SELECT
  COUNT(*) AS published_release_notes
FROM moments
WHERE uuid LIKE 'release-20260723-%'
  AND status = 1
  AND visibility = 1
  AND deleted_at IS NULL;
