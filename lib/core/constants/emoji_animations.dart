// 文件用途：集中定义表情动画资源和播放参数相关常量，供表情选择器和消息渲染统一复用。
// 核心逻辑：集中维护 EmojiAnimations 的稳定常量，作为界面、服务和校验逻辑共享的单一配置来源。
import '../i18n/app_localizations.dart';

/// 动画表情资源映射

// 关键声明：emoji animations 是共享常量入口，修改时需要同步检查使用它的 UI、服务和校验规则。
class EmojiAnimations {
  EmojiAnimations._();

  static const String _basePath = 'assets/emoji/lottie';

  /// 所有动画表情
  static const List<AnimatedEmoji> all = [
    // ========== 笑脸表情 ==========
    AnimatedEmoji(
        emoji: '😂',
        name: '笑哭',
        file: 'joy.json',
        category: EmojiCategory.faces),
    AnimatedEmoji(
        emoji: '😆',
        name: '大笑',
        file: 'laughing.json',
        category: EmojiCategory.faces),
    AnimatedEmoji(
        emoji: '😊',
        name: '微笑',
        file: 'smiling.json',
        category: EmojiCategory.faces),
    AnimatedEmoji(
        emoji: '😉',
        name: '眨眼',
        file: 'wink.json',
        category: EmojiCategory.faces),
    AnimatedEmoji(
        emoji: '😍',
        name: '花痴',
        file: 'heart_eyes.json',
        category: EmojiCategory.faces),
    AnimatedEmoji(
        emoji: '🥰',
        name: '脸红',
        file: 'blush.json',
        category: EmojiCategory.faces),
    AnimatedEmoji(
        emoji: '😋',
        name: '好吃',
        file: 'yum.json',
        category: EmojiCategory.faces),
    AnimatedEmoji(
        emoji: '😌',
        name: '放松',
        file: 'relieved.json',
        category: EmojiCategory.faces),
    AnimatedEmoji(
        emoji: '🤩',
        name: '星星眼',
        file: 'star_eyes.json',
        category: EmojiCategory.faces),
    AnimatedEmoji(
        emoji: '😏',
        name: '得意',
        file: 'smirk.json',
        category: EmojiCategory.faces),
    AnimatedEmoji(
        emoji: '😒',
        name: '不高兴',
        file: 'unamused.json',
        category: EmojiCategory.faces),
    AnimatedEmoji(
        emoji: '😓',
        name: '冷汗',
        file: 'sweat.json',
        category: EmojiCategory.faces),
    AnimatedEmoji(
        emoji: '😔',
        name: '沉思',
        file: 'pensive.json',
        category: EmojiCategory.faces),
    AnimatedEmoji(
        emoji: '😕',
        name: '困惑',
        file: 'confused.json',
        category: EmojiCategory.faces),
    AnimatedEmoji(
        emoji: '😖',
        name: '纠结',
        file: 'confounded.json',
        category: EmojiCategory.faces),
    AnimatedEmoji(
        emoji: '😗',
        name: '亲亲',
        file: 'kissing.json',
        category: EmojiCategory.faces),
    AnimatedEmoji(
        emoji: '😘',
        name: '飞吻',
        file: 'kiss.json',
        category: EmojiCategory.faces),
    AnimatedEmoji(
        emoji: '😚',
        name: '羞涩亲',
        file: 'kissing_closed.json',
        category: EmojiCategory.faces),
    AnimatedEmoji(
        emoji: '😛',
        name: '吐舌',
        file: 'stuck_out.json',
        category: EmojiCategory.faces),
    AnimatedEmoji(
        emoji: '😜',
        name: '调皮',
        file: 'wink_tongue.json',
        category: EmojiCategory.faces),
    AnimatedEmoji(
        emoji: '😞',
        name: '失望',
        file: 'disappointed.json',
        category: EmojiCategory.faces),
    AnimatedEmoji(
        emoji: '😟',
        name: '担心',
        file: 'worried.json',
        category: EmojiCategory.faces),
    AnimatedEmoji(
        emoji: '😮',
        name: '惊讶',
        file: 'surprised.json',
        category: EmojiCategory.faces),
    AnimatedEmoji(
        emoji: '😢',
        name: '难过',
        file: 'crying.json',
        category: EmojiCategory.faces),
    AnimatedEmoji(
        emoji: '😤',
        name: '哼',
        file: 'triumph.json',
        category: EmojiCategory.faces),
    AnimatedEmoji(
        emoji: '😦',
        name: '皱眉',
        file: 'frowning.json',
        category: EmojiCategory.faces),
    AnimatedEmoji(
        emoji: '😧',
        name: '痛苦',
        file: 'anguished.json',
        category: EmojiCategory.faces),
    AnimatedEmoji(
        emoji: '😨',
        name: '害怕',
        file: 'fearful.json',
        category: EmojiCategory.faces),
    AnimatedEmoji(
        emoji: '😩',
        name: '疲惫',
        file: 'weary.json',
        category: EmojiCategory.faces),
    AnimatedEmoji(
        emoji: '😪',
        name: '困了',
        file: 'sleepy.json',
        category: EmojiCategory.faces),
    AnimatedEmoji(
        emoji: '😫',
        name: '累坏了',
        file: 'tired.json',
        category: EmojiCategory.faces),
    AnimatedEmoji(
        emoji: '😬',
        name: '龇牙',
        file: 'grimacing.json',
        category: EmojiCategory.faces),
    AnimatedEmoji(
        emoji: '😭',
        name: '大哭',
        file: 'loudly_crying.json',
        category: EmojiCategory.faces),
    AnimatedEmoji(
        emoji: '😱',
        name: '尖叫',
        file: 'scream.json',
        category: EmojiCategory.faces),
    AnimatedEmoji(
        emoji: '😲',
        name: '震惊',
        file: 'astonished.json',
        category: EmojiCategory.faces),
    AnimatedEmoji(
        emoji: '😳',
        name: '脸红',
        file: 'flushed.json',
        category: EmojiCategory.faces),
    AnimatedEmoji(
        emoji: '😡',
        name: '愤怒',
        file: 'angry.json',
        category: EmojiCategory.faces),
    AnimatedEmoji(
        emoji: '🤔',
        name: '思考',
        file: 'thinking.json',
        category: EmojiCategory.faces),
    AnimatedEmoji(
        emoji: '😎',
        name: '墨镜酷',
        file: 'sunglasses.json',
        category: EmojiCategory.faces),
    AnimatedEmoji(
        emoji: '🥵',
        name: '热',
        file: 'hot.json',
        category: EmojiCategory.faces),
    AnimatedEmoji(
        emoji: '🥶',
        name: '冷',
        file: 'cold.json',
        category: EmojiCategory.faces),
    AnimatedEmoji(
        emoji: '🤗',
        name: '拥抱',
        file: 'hug.json',
        category: EmojiCategory.faces),
    AnimatedEmoji(
        emoji: '🤫',
        name: '嘘',
        file: 'shush.json',
        category: EmojiCategory.faces),
    AnimatedEmoji(
        emoji: '🤮',
        name: '呕吐',
        file: 'vomit.json',
        category: EmojiCategory.faces),
    AnimatedEmoji(
        emoji: '😴',
        name: '睡觉',
        file: 'sleeping.json',
        category: EmojiCategory.faces),
    AnimatedEmoji(
        emoji: '😈',
        name: '恶魔',
        file: 'devil.json',
        category: EmojiCategory.faces),
    AnimatedEmoji(
        emoji: '😇',
        name: '天使',
        file: 'angel.json',
        category: EmojiCategory.faces),
    AnimatedEmoji(
        emoji: '🤯',
        name: '爆炸',
        file: 'exploding_head.json',
        category: EmojiCategory.faces),

    // ========== 动物 ==========
    AnimatedEmoji(
        emoji: '🐶',
        name: '狗',
        file: 'dog.json',
        category: EmojiCategory.animals),
    AnimatedEmoji(
        emoji: '🐱',
        name: '猫',
        file: 'cat.json',
        category: EmojiCategory.animals),
    AnimatedEmoji(
        emoji: '🐷',
        name: '猪',
        file: 'pig.json',
        category: EmojiCategory.animals),
    AnimatedEmoji(
        emoji: '🐵',
        name: '猴子',
        file: 'monkey.json',
        category: EmojiCategory.animals),
    AnimatedEmoji(
        emoji: '🙈',
        name: '捂眼猴',
        file: 'monkey_face.json',
        category: EmojiCategory.animals),
    AnimatedEmoji(
        emoji: '🐰',
        name: '兔子',
        file: 'rabbit.json',
        category: EmojiCategory.animals),
    AnimatedEmoji(
        emoji: '🐯',
        name: '老虎',
        file: 'tiger.json',
        category: EmojiCategory.animals),
    AnimatedEmoji(
        emoji: '🐸',
        name: '青蛙',
        file: 'frog.json',
        category: EmojiCategory.animals),
    AnimatedEmoji(
        emoji: '🐦',
        name: '小鸟',
        file: 'bird.json',
        category: EmojiCategory.animals),
    AnimatedEmoji(
        emoji: '🐣',
        name: '破壳鸡',
        file: 'hatching_chick.json',
        category: EmojiCategory.animals),
    AnimatedEmoji(
        emoji: '🐤',
        name: '小鸡',
        file: 'baby_chick.json',
        category: EmojiCategory.animals),
    AnimatedEmoji(
        emoji: '🐥',
        name: '正面鸡',
        file: 'hatched_chick.json',
        category: EmojiCategory.animals),
    AnimatedEmoji(
        emoji: '🦋',
        name: '蝴蝶',
        file: 'butterfly.json',
        category: EmojiCategory.animals),
    AnimatedEmoji(
        emoji: '🐝',
        name: '蜜蜂',
        file: 'bee.json',
        category: EmojiCategory.animals),
    AnimatedEmoji(
        emoji: '🐢',
        name: '乌龟',
        file: 'turtle.json',
        category: EmojiCategory.animals),
    AnimatedEmoji(
        emoji: '🐍',
        name: '蛇',
        file: 'snake.json',
        category: EmojiCategory.animals),
    AnimatedEmoji(
        emoji: '🐉',
        name: '龙',
        file: 'dragon.json',
        category: EmojiCategory.animals),
    AnimatedEmoji(
        emoji: '🐙',
        name: '章鱼',
        file: 'octopus.json',
        category: EmojiCategory.animals),
    AnimatedEmoji(
        emoji: '🐬',
        name: '海豚',
        file: 'dolphin.json',
        category: EmojiCategory.animals),
    AnimatedEmoji(
        emoji: '🐳',
        name: '鲸鱼',
        file: 'whale.json',
        category: EmojiCategory.animals),
    AnimatedEmoji(
        emoji: '🐟',
        name: '鱼',
        file: 'fish.json',
        category: EmojiCategory.animals),
    AnimatedEmoji(
        emoji: '🦄',
        name: '独角兽',
        file: 'unicorn.json',
        category: EmojiCategory.animals),

    // ========== 自然 ==========
    AnimatedEmoji(
        emoji: '🌈',
        name: '彩虹',
        file: 'rainbow.json',
        category: EmojiCategory.nature),
    AnimatedEmoji(
        emoji: '❄️',
        name: '雪花',
        file: 'snowflake.json',
        category: EmojiCategory.nature),
    AnimatedEmoji(
        emoji: '⚡',
        name: '闪电',
        file: 'lightning.json',
        category: EmojiCategory.nature),
    AnimatedEmoji(
        emoji: '🌹',
        name: '玫瑰',
        file: 'rose.json',
        category: EmojiCategory.nature),
    AnimatedEmoji(
        emoji: '🍀',
        name: '四叶草',
        file: 'four_leaf.json',
        category: EmojiCategory.nature),

    // ========== 食物 ==========
    AnimatedEmoji(
        emoji: '🍜',
        name: '拉面',
        file: 'ramen.json',
        category: EmojiCategory.food),
    AnimatedEmoji(
        emoji: '☕',
        name: '咖啡',
        file: 'coffee.json',
        category: EmojiCategory.food),
    AnimatedEmoji(
        emoji: '🍷',
        name: '红酒',
        file: 'wine.json',
        category: EmojiCategory.food),

    // ========== 活动 ==========
    AnimatedEmoji(
        emoji: '⚽',
        name: '足球',
        file: 'soccer.json',
        category: EmojiCategory.activities),
    AnimatedEmoji(
        emoji: '🎾',
        name: '网球',
        file: 'tennis.json',
        category: EmojiCategory.activities),
    AnimatedEmoji(
        emoji: '🏆',
        name: '奖杯',
        file: 'trophy.json',
        category: EmojiCategory.activities),
    AnimatedEmoji(
        emoji: '🎲',
        name: '骰子',
        file: 'dice.json',
        category: EmojiCategory.activities),

    // ========== 手势 ==========
    AnimatedEmoji(
        emoji: '👍',
        name: '点赞',
        file: 'thumbs_up.json',
        category: EmojiCategory.gestures),
    AnimatedEmoji(
        emoji: '👎',
        name: '反对',
        file: 'thumbs_down.json',
        category: EmojiCategory.gestures),
    AnimatedEmoji(
        emoji: '👏',
        name: '鼓掌',
        file: 'clap.json',
        category: EmojiCategory.gestures),
    AnimatedEmoji(
        emoji: '👋',
        name: '挥手',
        file: 'wave.json',
        category: EmojiCategory.gestures),
    AnimatedEmoji(
        emoji: '👌',
        name: 'OK',
        file: 'ok.json',
        category: EmojiCategory.gestures),
    AnimatedEmoji(
        emoji: '💪',
        name: '肌肉',
        file: 'muscle.json',
        category: EmojiCategory.gestures),
    AnimatedEmoji(
        emoji: '🙏',
        name: '祈祷',
        file: 'pray.json',
        category: EmojiCategory.gestures),
    AnimatedEmoji(
        emoji: '👀',
        name: '眼睛',
        file: 'eyes.json',
        category: EmojiCategory.gestures),
    AnimatedEmoji(
        emoji: '🙌',
        name: '举手',
        file: 'raised_hands.json',
        category: EmojiCategory.gestures),
    AnimatedEmoji(
        emoji: '☝️',
        name: '指上',
        file: 'point_up.json',
        category: EmojiCategory.gestures),
    AnimatedEmoji(
        emoji: '👇',
        name: '指下',
        file: 'point_down.json',
        category: EmojiCategory.gestures),
    AnimatedEmoji(
        emoji: '👈',
        name: '指左',
        file: 'point_left.json',
        category: EmojiCategory.gestures),
    AnimatedEmoji(
        emoji: '👉',
        name: '指右',
        file: 'point_right.json',
        category: EmojiCategory.gestures),
    AnimatedEmoji(
        emoji: '✊',
        name: '拳头',
        file: 'fist.json',
        category: EmojiCategory.gestures),
    AnimatedEmoji(
        emoji: '✌️',
        name: '胜利',
        file: 'v_sign.json',
        category: EmojiCategory.gestures),
    AnimatedEmoji(
        emoji: '🤙',
        name: '打电话',
        file: 'call_me.json',
        category: EmojiCategory.gestures),
    AnimatedEmoji(
        emoji: '🤟',
        name: '爱你',
        file: 'love_you.json',
        category: EmojiCategory.gestures),

    // ========== 符号和爱心 ==========
    AnimatedEmoji(
        emoji: '❤️',
        name: '红心',
        file: 'heart.json',
        category: EmojiCategory.symbols),
    AnimatedEmoji(
        emoji: '🧡',
        name: '橙心',
        file: 'orange_heart.json',
        category: EmojiCategory.symbols),
    AnimatedEmoji(
        emoji: '💛',
        name: '黄心',
        file: 'yellow_heart.json',
        category: EmojiCategory.symbols),
    AnimatedEmoji(
        emoji: '💚',
        name: '绿心',
        file: 'green_heart.json',
        category: EmojiCategory.symbols),
    AnimatedEmoji(
        emoji: '💙',
        name: '蓝心',
        file: 'blue_heart.json',
        category: EmojiCategory.symbols),
    AnimatedEmoji(
        emoji: '💜',
        name: '紫心',
        file: 'purple_heart.json',
        category: EmojiCategory.symbols),
    AnimatedEmoji(
        emoji: '💔',
        name: '心碎',
        file: 'broken_heart.json',
        category: EmojiCategory.symbols),
    AnimatedEmoji(
        emoji: '💖',
        name: '闪亮心',
        file: 'sparkling_heart.json',
        category: EmojiCategory.symbols),
    AnimatedEmoji(
        emoji: '💓',
        name: '心跳',
        file: 'heartbeat.json',
        category: EmojiCategory.symbols),
    AnimatedEmoji(
        emoji: '🔥',
        name: '火焰',
        file: 'fire.json',
        category: EmojiCategory.symbols),
    AnimatedEmoji(
        emoji: '💯',
        name: '满分',
        file: 'hundred.json',
        category: EmojiCategory.symbols),
    AnimatedEmoji(
        emoji: '✨',
        name: '闪光',
        file: 'sparkles.json',
        category: EmojiCategory.symbols),
    AnimatedEmoji(
        emoji: '🎉',
        name: '庆祝',
        file: 'party.json',
        category: EmojiCategory.symbols),
    AnimatedEmoji(
        emoji: '🎊',
        name: '彩带',
        file: 'tada.json',
        category: EmojiCategory.symbols),
    AnimatedEmoji(
        emoji: '🚀',
        name: '火箭',
        file: 'rocket.json',
        category: EmojiCategory.symbols),
    AnimatedEmoji(
        emoji: '👻',
        name: '幽灵',
        file: 'ghost.json',
        category: EmojiCategory.symbols),
    AnimatedEmoji(
        emoji: '💀',
        name: '骷髅',
        file: 'skull.json',
        category: EmojiCategory.symbols),
    AnimatedEmoji(
        emoji: '💩',
        name: '便便',
        file: 'poop.json',
        category: EmojiCategory.symbols),
  ];

  /// 获取表情动画路径
  static String getPath(String fileName) {
    if (fileName.startsWith('assets/') ||
        fileName.startsWith('/uploads/') ||
        fileName.startsWith('uploads/') ||
        fileName.startsWith('http://') ||
        fileName.startsWith('https://')) {
      return fileName;
    }
    return '$_basePath/$fileName';
  }

  /// emoji 到 lottie 文件名的映射
  static final Map<String, String> emojiToFile = {
    for (final e in all) e.emoji: e.file,
  };

  /// 按分类获取表情
  static List<AnimatedEmoji> getByCategory(EmojiCategory category) {
    return all.where((e) => e.category == category).toList();
  }

  /// 根据emoji查找动画
  static AnimatedEmoji? findByEmoji(String emoji) {
    try {
      return all.firstWhere((e) => e.emoji == emoji);
    } catch (_) {
      return null;
    }
  }

  /// 快速反应表情（消息长按用）
  static const List<AnimatedEmoji> quickReactions = [
    AnimatedEmoji(
        emoji: '👍',
        name: '点赞',
        file: 'thumbs_up.json',
        category: EmojiCategory.gestures),
    AnimatedEmoji(
        emoji: '❤️',
        name: '红心',
        file: 'heart.json',
        category: EmojiCategory.symbols),
    AnimatedEmoji(
        emoji: '😂',
        name: '笑哭',
        file: 'joy.json',
        category: EmojiCategory.faces),
    AnimatedEmoji(
        emoji: '😮',
        name: '惊讶',
        file: 'surprised.json',
        category: EmojiCategory.faces),
    AnimatedEmoji(
        emoji: '😢',
        name: '难过',
        file: 'crying.json',
        category: EmojiCategory.faces),
    AnimatedEmoji(
        emoji: '🙏',
        name: '祈祷',
        file: 'pray.json',
        category: EmojiCategory.gestures),
  ];
}

/// 表情分类
enum EmojiCategory {
  faces('笑脸', '😂'),
  animals('动物', '🐱'),
  nature('自然', '🌈'),
  food('美食', '☕'),
  activities('活动', '⚽'),
  gestures('手势', '👍'),
  symbols('爱心', '❤️');

  final String label;
  final String icon;

  const EmojiCategory(this.label, this.icon);
}

/// 动画表情数据
class AnimatedEmoji {
  final String emoji;
  final String name;
  final String file;
  final EmojiCategory category;

  const AnimatedEmoji({
    required this.emoji,
    required this.name,
    required this.file,
    required this.category,
  });

  String get path => EmojiAnimations.getPath(file);
}

/// 贴纸包数据
class StickerPack {
  final String id;
  final String name;
  final String description;
  final String previewEmoji;
  final String previewFile; // 动画预览文件
  final List<String> stickerFiles;
  final bool isBuiltIn;

  const StickerPack({
    required this.id,
    required this.name,
    required this.description,
    required this.previewEmoji,
    required this.previewFile,
    required this.stickerFiles,
    this.isBuiltIn = false,
  });

  int get count => stickerFiles.length;

  String get previewPath => EmojiAnimations.getPath(previewFile);

  // 流程逻辑：`localizedName` 先校验输入并完成空值/格式规范化，再返回稳定结果，不承担页面或网络副作用。
  String localizedName(AppLanguage language) {
    switch (id) {
      case 'animated_faces':
        switch (language) {
          case AppLanguage.en:
            return 'Animated Faces';
          case AppLanguage.zhTW:
            return '動態笑臉';
          case AppLanguage.zhCN:
            return '动态笑脸';
        }
      case 'animated_animals':
        switch (language) {
          case AppLanguage.en:
            return 'Animated Animals';
          case AppLanguage.zhTW:
            return '動態動物';
          case AppLanguage.zhCN:
            return '动态动物';
        }
      case 'animated_nature':
        switch (language) {
          case AppLanguage.en:
            return 'Animated Nature';
          case AppLanguage.zhTW:
            return '動態自然';
          case AppLanguage.zhCN:
            return '动态自然';
        }
      case 'animated_gestures':
        switch (language) {
          case AppLanguage.en:
            return 'Animated Gestures';
          case AppLanguage.zhTW:
            return '動態手勢';
          case AppLanguage.zhCN:
            return '动态手势';
        }
      case 'animated_symbols':
        switch (language) {
          case AppLanguage.en:
            return 'Animated Symbols';
          case AppLanguage.zhTW:
            return '動態愛心';
          case AppLanguage.zhCN:
            return '动态爱心';
        }
      case 'cubigator':
        switch (language) {
          case AppLanguage.en:
            return 'Cubigator';
          case AppLanguage.zhTW:
            return '小恐龍';
          case AppLanguage.zhCN:
            return '小恐龙';
        }
      case 'duck':
        switch (language) {
          case AppLanguage.en:
            return 'Duck';
          case AppLanguage.zhTW:
            return '小黃鴨';
          case AppLanguage.zhCN:
            return '小黄鸭';
        }
      case 'premium_gifts':
        switch (language) {
          case AppLanguage.en:
            return 'Premium Gifts';
          case AppLanguage.zhTW:
            return '高級禮品';
          case AppLanguage.zhCN:
            return '高级礼品';
        }
    }
    return name;
  }

  String localizedDescription(AppLanguage language) {
    switch (id) {
      case 'animated_faces':
        switch (language) {
          case AppLanguage.en:
            return 'A rich set of expressive animated faces';
          case AppLanguage.zhTW:
            return '豐富的表情動畫';
          case AppLanguage.zhCN:
            return '丰富的表情动画';
        }
      case 'animated_animals':
        switch (language) {
          case AppLanguage.en:
            return 'Cute animated animal stickers';
          case AppLanguage.zhTW:
            return '可愛的動物動畫';
          case AppLanguage.zhCN:
            return '可爱的动物动画';
        }
      case 'animated_nature':
        switch (language) {
          case AppLanguage.en:
            return 'Nature-themed animated stickers';
          case AppLanguage.zhTW:
            return '自然元素動畫';
          case AppLanguage.zhCN:
            return '自然元素动画';
        }
      case 'animated_gestures':
        switch (language) {
          case AppLanguage.en:
            return 'Animated reactions and gestures';
          case AppLanguage.zhTW:
            return '手勢表情動畫';
          case AppLanguage.zhCN:
            return '手势表情动画';
        }
      case 'animated_symbols':
        switch (language) {
          case AppLanguage.en:
            return 'Hearts and symbol animations';
          case AppLanguage.zhTW:
            return '愛心和符號動畫';
          case AppLanguage.zhCN:
            return '爱心和符号动画';
        }
      case 'cubigator':
        switch (language) {
          case AppLanguage.en:
            return 'Animated green dinosaur stickers';
          case AppLanguage.zhTW:
            return '小恐龍動畫貼紙';
          case AppLanguage.zhCN:
            return '小恐龙动画贴纸';
        }
      case 'duck':
        switch (language) {
          case AppLanguage.en:
            return 'Animated yellow duck stickers';
          case AppLanguage.zhTW:
            return '小黃鴨動畫貼紙';
          case AppLanguage.zhCN:
            return '小黄鸭动画贴纸';
        }
      case 'premium_gifts':
        switch (language) {
          case AppLanguage.en:
            return 'Premium animated gift stickers';
          case AppLanguage.zhTW:
            return '高級禮品動畫貼紙';
          case AppLanguage.zhCN:
            return '高级礼品动画贴纸';
        }
    }
    return description;
  }
}

/// 内置贴纸包
class BuiltInStickerPacks {
  BuiltInStickerPacks._();

  static List<String> _numberedFiles(
    String dir,
    String prefix,
    int count, {
    String extension = 'json',
    String basePath = 'assets/stickers',
    Set<int> skip = const {},
  }) {
    final files = <String>[];
    for (var i = 1; i <= count; i++) {
      if (skip.contains(i)) continue;
      files.add(
          '$basePath/$dir/${prefix}_${i.toString().padLeft(2, '0')}.$extension');
    }
    return files;
  }

  static final List<StickerPack> all = [
    StickerPack(
      id: 'animated_faces',
      name: '动态笑脸',
      description: '丰富的表情动画',
      previewEmoji: '😂',
      previewFile: 'joy.json',
      stickerFiles: [
        'joy.json',
        'laughing.json',
        'smiling.json',
        'wink.json',
        'heart_eyes.json',
        'blush.json',
        'yum.json',
        'relieved.json',
        'star_eyes.json',
        'smirk.json',
        'unamused.json',
        'sweat.json',
        'pensive.json',
        'confused.json',
        'confounded.json',
        'kissing.json',
        'kiss.json',
        'kissing_closed.json',
        'stuck_out.json',
        'wink_tongue.json',
        'disappointed.json',
        'worried.json',
        'surprised.json',
        'crying.json',
        'triumph.json',
        'frowning.json',
        'anguished.json',
        'fearful.json',
        'weary.json',
        'sleepy.json',
        'tired.json',
        'grimacing.json',
        'loudly_crying.json',
        'scream.json',
        'astonished.json',
        'flushed.json',
        'angry.json',
        'thinking.json',
        'sunglasses.json',
        'hot.json',
        'cold.json',
        'hug.json',
        'shush.json',
        'vomit.json',
        'sleeping.json',
        'devil.json',
        'angel.json',
        'exploding_head.json',
      ],
      isBuiltIn: true,
    ),
    StickerPack(
      id: 'animated_animals',
      name: '动态动物',
      description: '可爱的动物动画',
      previewEmoji: '🐱',
      previewFile: 'cat.json',
      stickerFiles: [
        'dog.json',
        'cat.json',
        'pig.json',
        'monkey.json',
        'monkey_face.json',
        'rabbit.json',
        'tiger.json',
        'frog.json',
        'bird.json',
        'hatching_chick.json',
        'baby_chick.json',
        'hatched_chick.json',
        'butterfly.json',
        'bee.json',
        'turtle.json',
        'snake.json',
        'dragon.json',
        'octopus.json',
        'dolphin.json',
        'whale.json',
        'fish.json',
        'unicorn.json',
      ],
      isBuiltIn: true,
    ),
    StickerPack(
      id: 'animated_nature',
      name: '动态自然',
      description: '自然元素动画',
      previewEmoji: '🌈',
      previewFile: 'rainbow.json',
      stickerFiles: [
        'rainbow.json',
        'snowflake.json',
        'lightning.json',
        'rose.json',
        'four_leaf.json',
      ],
      isBuiltIn: true,
    ),
    StickerPack(
      id: 'animated_gestures',
      name: '动态手势',
      description: '手势表情动画',
      previewEmoji: '👍',
      previewFile: 'thumbs_up.json',
      stickerFiles: [
        'thumbs_up.json',
        'thumbs_down.json',
        'clap.json',
        'wave.json',
        'ok.json',
        'muscle.json',
        'pray.json',
        'eyes.json',
        'raised_hands.json',
        'point_up.json',
        'point_down.json',
        'point_left.json',
        'point_right.json',
        'fist.json',
        'v_sign.json',
        'call_me.json',
        'love_you.json',
      ],
      isBuiltIn: true,
    ),
    StickerPack(
      id: 'animated_symbols',
      name: '动态爱心',
      description: '爱心和符号动画',
      previewEmoji: '❤️',
      previewFile: 'heart.json',
      stickerFiles: [
        'heart.json',
        'orange_heart.json',
        'yellow_heart.json',
        'green_heart.json',
        'blue_heart.json',
        'purple_heart.json',
        'broken_heart.json',
        'sparkling_heart.json',
        'heartbeat.json',
        'fire.json',
        'hundred.json',
        'sparkles.json',
        'party.json',
        'tada.json',
        'rocket.json',
        'ghost.json',
        'skull.json',
        'poop.json',
      ],
      isBuiltIn: true,
    ),
    StickerPack(
      id: 'cubigator',
      name: '小恐龙',
      description: '小恐龙动画贴纸',
      previewEmoji: '🦖',
      previewFile: 'assets/stickers/cubigator/cubigator_01.json',
      stickerFiles: _numberedFiles(
        'cubigator',
        'cubigator',
        30,
      ),
      isBuiltIn: true,
    ),
    StickerPack(
      id: 'duck',
      name: '小黄鸭',
      description: '小黄鸭动画贴纸',
      previewEmoji: '🐤',
      previewFile: 'assets/stickers/duck/duck_01.json',
      stickerFiles: _numberedFiles(
        'duck',
        'duck',
        29,
      ),
      isBuiltIn: true,
    ),
    StickerPack(
      id: 'premium_gifts',
      name: '高级礼品',
      description: '高级礼品动画贴纸',
      previewEmoji: '🎁',
      previewFile: 'assets/stickers/premium_gifts/premium_gifts_01.json',
      stickerFiles: _numberedFiles(
        'premium_gifts',
        'premium_gifts',
        30,
      ),
      isBuiltIn: true,
    ),
  ];
}
