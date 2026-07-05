import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 支持的语言
enum AppLanguage {
  zhCN('zh_CN', '简体中文', Locale('zh', 'CN')),
  zhTW('zh_TW', '繁體中文', Locale('zh', 'TW')),
  en('en', 'English', Locale('en', 'US'));

  final String code;
  final String displayName;
  final Locale locale;

  const AppLanguage(this.code, this.displayName, this.locale);

  static AppLanguage fromCode(String code) {
    return AppLanguage.values.firstWhere(
      (l) => l.code == code,
      orElse: () => AppLanguage.zhCN,
    );
  }
}

/// 语言状态管理
class LanguageNotifier extends StateNotifier<AppLanguage> {
  LanguageNotifier() : super(AppLanguage.zhCN) {
    _loadLanguage();
  }

  Future<void> _loadLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString('app_language') ?? 'zh_CN';
    state = AppLanguage.fromCode(code);
  }

  Future<void> setLanguage(AppLanguage language) async {
    state = language;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('app_language', language.code);
  }
}

final languageProvider = StateNotifierProvider<LanguageNotifier, AppLanguage>((
  ref,
) {
  return LanguageNotifier();
});

/// 翻译类
class AppLocalizations {
  final AppLanguage language;

  AppLocalizations(this.language);

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations) ??
        AppLocalizations(AppLanguage.zhCN);
  }

  String get(String key) {
    return _translations[language.code]?[key] ??
        _translations['zh_CN']?[key] ??
        key;
  }

  // 简化调用的 getter
  String get appName => get('app_name');

  // 通用
  String get confirm => get('confirm');
  String get cancel => get('cancel');
  String get save => get('save');
  String get delete => get('delete');
  String get edit => get('edit');
  String get done => get('done');
  String get search => get('search');
  String get loading => get('loading');
  String get retry => get('retry');
  String get error => get('error');
  String get success => get('success');
  String get failed => get('failed');
  String get copy => get('copy');
  String get share => get('share');
  String get more => get('more');
  String get close => get('close');
  String get back => get('back');
  String get next => get('next');
  String get submit => get('submit');
  String get send => get('send');

  // 底部导航
  String get tabChat => get('tab_chat');
  String get tabContacts => get('tab_contacts');
  String get tabPortal => get('tab_portal');
  String get tabDiscover => get('tab_discover');
  String get tabSquare => get('tab_square');
  String get tabMe => get('tab_me');

  // 聊天
  String get chats => get('chats');
  String get messages => get('messages');
  String get newChat => get('new_chat');
  String get newGroup => get('new_group');
  String get newChannel => get('new_channel');
  String get typeMessage => get('type_message');
  String get sendFirstMessage => get('send_first_message');
  String get noMessages => get('no_messages');
  String get messageDeleted => get('message_deleted');
  String get photo => get('photo');
  String get video => get('video');
  String get voice => get('voice');
  String get file => get('file');
  String get sticker => get('sticker');
  String get reply => get('reply');
  String get forward => get('forward');
  String get select => get('select_action');
  String get pin => get('pin');
  String get unpin => get('unpin');
  String get mute => get('mute');
  String get unmute => get('unmute');
  String get deleteChat => get('delete_chat');
  String get clearHistory => get('clear_history');
  String get typing => get('typing');
  String get online => get('online');
  String get offline => get('offline');
  String get lastSeen => get('last_seen');
  String get today => get('today');
  String get yesterday => get('yesterday');
  String get readAll => get('read_all');

  // 联系人
  String get contacts => get('contacts');
  String get addContact => get('add_contact');
  String get newContact => get('new_contact');
  String get contactInfo => get('contact_info');
  String get phoneNumber => get('phone_number');
  String get username => get('username');
  String get bio => get('bio');
  String get commonGroups => get('common_groups');
  String get block => get('block');
  String get unblock => get('unblock');
  String get report => get('report');

  // 群组/频道
  String get groupInfo => get('group_info');
  String get channelInfo => get('channel_info');
  String get members => get('members');
  String get admins => get('admins');
  String get addMembers => get('add_members');
  String get removeMember => get('remove_member');
  String get leaveGroup => get('leave_group');
  String get leaveChannel => get('leave_channel');
  String get deleteGroup => get('delete_group');
  String get deleteChannel => get('delete_channel');
  String get groupName => get('group_name');
  String get channelName => get('channel_name');
  String get description => get('description');
  String get inviteLink => get('invite_link');
  String get copyLink => get('copy_link');
  String get permissions => get('permissions');
  String get notifications => get('notifications');

  // 广场/动态
  String get square => get('square');
  String get moments => get('moments');
  String get discoverTitle => get('discover_title');
  String get portalOpen => get('portal_open');
  String get newPost => get('new_post');
  String get like => get('like');
  String get comment => get('comment');
  String get comments => get('comments');
  String get writeComment => get('write_comment');
  String get noMoments => get('no_moments');

  // 设置
  String get settings => get('settings');
  String get profile => get('profile');
  String get editProfile => get('edit_profile');
  String get nickname => get('nickname');
  String get avatar => get('avatar');
  String get account => get('account');
  String get privacy => get('privacy');
  String get security => get('security');
  String get notificationSettings => get('notification_settings');
  String get chatSettings => get('chat_settings');
  String get dataStorage => get('data_storage');
  String get languageText => get('language');
  String get appearance => get('appearance');
  String get darkMode => get('dark_mode');
  String get lightMode => get('light_mode');
  String get systemMode => get('system_mode');
  String get chineseRedMode => get('chinese_red_mode');
  String get fontSize => get('font_size');
  String get chatBackground => get('chat_background');
  String get stickersEmoji => get('stickers_emoji');
  String get devices => get('devices');
  String get faq => get('faq');
  String get about => get('about');
  String get version => get('version');
  String get logout => get('logout');
  String get logoutConfirm => get('logout_confirm');
  String get deleteAccount => get('delete_account');

  // 登录注册
  String get login => get('login');
  String get register => get('register');
  String get loginToAccount => get('login_to_account');
  String get registerAccount => get('register_account');
  String get usernameLabel => get('username_label');
  String get passwordLabel => get('password_label');
  String get confirmPassword => get('confirm_password');
  String get nicknameLabel => get('nickname_label');
  String get nextStep => get('next_step');
  String get completeRegister => get('complete_register');
  String get registerNow => get('register_now');
  String get loginNow => get('login_now');
  String get createAccount => get('create_account');
  String get setupAccountPassword => get('setup_account_password');
  String get completeProfile => get('complete_profile');
  String get setupNicknameAvatar => get('setup_nickname_avatar');
  String get agreeTermsPrefix => get('agree_terms_prefix');
  String get pleaseAgreeTerms => get('please_agree_terms');
  String get pleaseEnterUsername => get('please_enter_username');
  String get pleaseEnterPassword => get('please_enter_password');
  String get pleaseEnterNickname => get('please_enter_nickname');
  String get passwordNotMatch => get('password_not_match');
  String get usernameAlreadyUsed => get('username_already_used');

  // 通话
  String get call => get('call');
  String get voiceCall => get('voice_call');
  String get videoCall => get('video_call');
  String get incomingCall => get('incoming_call');
  String get outgoingCall => get('outgoing_call');
  String get callEnded => get('call_ended');
  String get callDeclined => get('call_declined');
  String get callMissed => get('call_missed');
  String get calling => get('calling');
  String get connecting => get('connecting');
  String get ringing => get('ringing');
  String get endCall => get('end_call');
  String get answer => get('answer');
  String get decline => get('decline');
  String get muted => get('muted');
  String get speaker => get('speaker');
  String get camera => get('camera');
  String get switchCamera => get('switch_camera');

  // 文件操作（桌面端）
  String get saveAs => get('save_as');
  String get showInFolder => get('show_in_folder');
  String get openWith => get('open_with');
  String get download => get('download');
  String get downloading => get('downloading');
  String get downloaded => get('downloaded');
  String get fileSaved => get('file_saved');
  String get saveFailed => get('save_failed');

  // 权限
  String get permissionRequired => get('permission_required');
  String get microphonePermission => get('microphone_permission');
  String get cameraPermission => get('camera_permission');
  String get storagePermission => get('storage_permission');
  String get notificationPermission => get('notification_permission');
  String get goToSettings => get('go_to_settings');

  // 错误消息
  String get networkError => get('network_error');
  String get serverError => get('server_error');
  String get timeoutError => get('timeout_error');
  String get unknownError => get('unknown_error');
  String get noInternet => get('no_internet');
  String get sessionExpired => get('session_expired');

  // 时间格式
  String get justNow => get('just_now');
  String get minutesAgo => get('minutes_ago');
  String get hoursAgo => get('hours_ago');
  String get daysAgo => get('days_ago');

  // 个人资料页
  String get setNewPhoto => get('set_new_photo');
  String get name => get('name');
  String get enterYourName => get('enter_your_name');
  String get usernameHint => get('username_hint');
  String get bioHint => get('bio_hint');
  String get noPhoneBound => get('no_phone_bound');
  String get bind => get('bind');
  String get change => get('change');
  String get yourColor => get('your_color');
  String get qrCode => get('qr_code');
  String get inviteFriends => get('invite_friends');
  String get myQrCode => get('my_qr_code');
  String get scanToAddFriend => get('scan_to_add_friend');
  String get saveImage => get('save_image');
  String get usernameCopied => get('username_copied');
  String get uploadAvatarFailed => get('upload_avatar_failed');
  String get avatarDeleted => get('avatar_deleted');
  String get linkCopied => get('link_copied');
  String get verifyUsernameFirst => get('verify_username_first');
  String get confirmChangeUsername => get('confirm_change_username');
  String get confirmChange => get('confirm_change');
  String get changePhone => get('change_phone');
  String get verifyNewPhone => get('verify_new_phone');
  String get takePhoto => get('take_photo');
  String get gallery => get('gallery');
  String get deletePhoto => get('delete_photo');
  String get cropAvatar => get('crop_avatar');

  // 通知设置
  String get notificationsAndSounds => get('notifications_and_sounds');
  String get messageNotifications => get('message_notifications');
  String get privateMessages => get('private_messages');
  String get groupMessages => get('group_messages');
  String get channelMessages => get('channel_messages');
  String get momentNotifications => get('moment_notifications');
  String get likesCommentsReplies => get('likes_comments_replies');
  String get notificationContent => get('notification_content');
  String get showMessagePreview => get('show_message_preview');
  String get showMessageInNotification => get('show_message_in_notification');
  String get soundAndVibration => get('sound_and_vibration');
  String get notificationSound => get('notification_sound');
  String get alertTone => get('alert_tone');
  String get momentSound => get('moment_sound');
  String get vibration => get('vibration');
  String get inAppNotifications => get('in_app_notifications');
  String get inAppSound => get('in_app_sound');
  String get inAppVibration => get('in_app_vibration');
  String get resetAllNotificationSettings =>
      get('reset_all_notification_settings');
  String get selectAlertTone => get('select_alert_tone');
  String get tapToPreview => get('tap_to_preview');
  String get resetToDefault => get('reset_to_default');
  String get confirmResetNotifications => get('confirm_reset_notifications');
  String get reset => get('reset');

  // 数据存储
  String get dataAndStorage => get('data_and_storage');
  String get storage => get('storage');
  String get usedStorageSpace => get('used_storage_space');
  String get manageStorageSpace => get('manage_storage_space');
  String get clearCache => get('clear_cache');
  String get calculating => get('calculating');
  String get autoDownloadMedia => get('auto_download_media');
  String get images => get('images');
  String get videos => get('videos');
  String get files => get('files');
  String get cache => get('cache');
  String get autoDownloadHint => get('auto_download_hint');
  String get network => get('network');
  String get whenUsingWifi => get('when_using_wifi');
  String get whenUsingMobile => get('when_using_mobile');
  String get whenRoaming => get('when_roaming');
  String get downloadAllMedia => get('download_all_media');
  String get downloadImagesOnly => get('download_images_only');
  String get downloadSmallFilesOnly => get('download_small_files_only');
  String get noDownload => get('no_download');
  String get saveSettings => get('save_settings');
  String get saveToGallery => get('save_to_gallery');
  String get autoSaveToGallery => get('auto_save_to_gallery');
  String get dataUsage => get('data_usage');
  String get networkUsageStats => get('network_usage_stats');
  String get sent => get('sent');
  String get received => get('received');
  String get resetNetworkUsage => get('reset_network_usage');
  String get cacheCleared => get('cache_cleared');
  String get clearFailed => get('clear_failed');
  String get confirmClearCache => get('confirm_clear_cache');
  String get total => get('total');
  String get lastReset => get('last_reset');
  String get neverReset => get('never_reset');
  String get sentData => get('sent_data');
  String get receivedData => get('received_data');
  String get statsReset => get('stats_reset');
  String get confirmResetStats => get('confirm_reset_stats');
  String get otherFiles => get('other_files');
  String get clearAllCache => get('clear_all_cache');
  String get resetDataStats => get('reset_data_stats');

  // 设备管理
  String get currentDevice => get('current_device');
  String get linkNewDevice => get('link_new_device');
  String get scanQrCode => get('scan_qr_code');
  String get loginToOtherDevice => get('login_to_other_device');
  String get scanQrCodeHint => get('scan_qr_code_hint');
  String get activeSessions => get('active_sessions');
  String get devicesCount => get('devices_count');
  String get noOtherDevices => get('no_other_devices');
  String get suspiciousDeviceHint => get('suspicious_device_hint');
  String get terminateAllOtherDevices => get('terminate_all_other_devices');
  String get confirmTerminateAll => get('confirm_terminate_all');
  String get terminateAll => get('terminate_all');
  String get allDevicesTerminated => get('all_devices_terminated');
  String get loggingOut => get('logging_out');
  String get confirmLogout => get('confirm_logout');
  String get logoutHint => get('logout_hint');
  String get terminateDeviceSession => get('terminate_device_session');
  String get confirmTerminateDevice => get('confirm_terminate_device');
  String get deviceSessionTerminated => get('device_session_terminated');
  String get operationFailed => get('operation_failed');
  String get terminate => get('terminate');
  String get scanFunction => get('scan_function');
  String get developing => get('developing');

  // 贴纸和表情
  String get installed => get('installed');
  String get discoverMore => get('discover_more');
  String get recentlyUsed => get('recently_used');
  String get noStickerPacks => get('no_sticker_packs');
  String get goDiscover => get('go_discover');
  String get stickerSettings => get('sticker_settings');
  String get showAnimationOnSend => get('show_animation_on_send');
  String get autoPlayStickers => get('auto_play_stickers');
  String get emojiSuggestions => get('emoji_suggestions');
  String get available => get('available');
  String get allPacksInstalled => get('all_packs_installed');
  String get createStickerPack => get('create_sticker_pack');
  String get createStickerHint => get('create_sticker_hint');
  String get stickersCount => get('stickers_count');
  String get builtIn => get('built_in');
  String get install => get('install');
  String get preview => get('preview');
  String get uninstall => get('uninstall');

  // FAQ
  String get faqTitle => get('faq_title');
  String get searchQuestion => get('search_question');
  String get noQuestionsFound => get('no_questions_found');
  String get contactSupportForHelp => get('contact_support_for_help');
  String get contactSupport => get('contact_support');
  String get supportDescription => get('support_description');
  String get onlineSupport => get('online_support');
  String get onlineSupportHint => get('online_support_hint');
  String get qqSupport => get('qq_support');
  String get questionsCount => get('questions_count');
  String get thankYouFeedback => get('thank_you_feedback');
  String get wasThisHelpful => get('was_this_helpful');
  String get helpful => get('helpful');
  String get notHelpful => get('not_helpful');

  // 聊天页
  String get selectChat => get('select_chat');
  String get selectedCount => get('selected_count');
  String get selectAll => get('select_all');
  String get deselectAll => get('deselect_all');
  String get refreshing => get('refreshing');
  String get markAsRead => get('mark_as_read');
  String get noChats => get('no_chats');
  String get startNewChat => get('start_new_chat');
  String get deleteChatsConfirm => get('delete_chats_confirm');
  String get chatWillBeRemoved => get('chat_will_be_removed');
  String get searchUser => get('search_user');
  String get searchUserHint => get('search_user_hint');
  String get createGroupHint => get('create_group_hint');
  String get createChannelHint => get('create_channel_hint');
  String get scanQrCodeHintChat => get('scan_qr_code_hint_chat');
  String get all => get('all');
  String get removeFromList => get('remove_from_list');
  String get removeFromListHint => get('remove_from_list_hint');
  String get deleteChatHistory => get('delete_chat_history');
  String get deleteChatHistoryHint => get('delete_chat_history_hint');
  String get removedFromList => get('removed_from_list');
  String get confirmDeleteTitle => get('confirm_delete_title');
  String get confirmDeleteContent => get('confirm_delete_content');
  String get chatHistoryDeleted => get('chat_history_deleted');
  String get deleted => get('deleted');
  String get markAsUnread => get('mark_as_unread');
  String get membersCount => get('members_count');
  String get subscribersCount => get('subscribers_count');
  String get newPrivateChat => get('new_private_chat');
  String get searchContacts => get('search_contacts');
  String get noContactsFound => get('no_contacts_found');
  String get noContactsYet => get('no_contacts_yet');
  String get clickToAddFriends => get('click_to_add_friends');
  String get longTimeAgo => get('long_time_ago');
  String get openChatFailed => get('open_chat_failed');
  String get mediaMessage => get('media_message');
  String get lastSeenAt => get('last_seen_at');

  // 关于页
  String get aboutTitle => get('about_title');
  String get copyright => get('copyright');

  // 空状态
  String get selectChatToStart => get('select_chat_to_start');
  String get pressToStartChat => get('press_to_start_chat');

  // 创建聊天
  String get create => get('create');
  String get createGroup => get('create_group');
  String get createChannel => get('create_channel');
  String get enterGroupName => get('enter_group_name');
  String get enterChannelName => get('enter_channel_name');
  String get selectMembers => get('select_members');
  String get publicGroup => get('public_group');
  String get privateGroup => get('private_group');
  String get publicChannel => get('public_channel');
  String get privateChannel => get('private_channel');
  String get anyoneCanJoin => get('anyone_can_join');
  String get inviteOnly => get('invite_only');
  String get createGroupFailed => get('create_group_failed');
  String get createChannelFailed => get('create_channel_failed');
  String get noContacts => get('no_contacts');
  String get addContactsFirst => get('add_contacts_first');
  String get clear => get('clear');
  String get recentlyOnline => get('recently_online');
  String get channelDescriptionOptional => get('channel_description_optional');
  String get anyoneCanSubscribe => get('anyone_can_subscribe');
  String get inviteOnlySubscribe => get('invite_only_subscribe');
  String get cropGroupAvatar => get('crop_group_avatar');
  String get cropChannelAvatar => get('crop_channel_avatar');
}

/// 翻译字典
const Map<String, Map<String, String>> _translations = {
  'zh_CN': _zhCN,
  'zh_TW': _zhTW,
  'en': _en,
};

const Map<String, String> _zhCN = {
  'app_name': '壹信',

  // 通用
  'confirm': '确认',
  'cancel': '取消',
  'save': '保存',
  'delete': '删除',
  'edit': '编辑',
  'done': '完成',
  'search': '搜索',
  'loading': '加载中...',
  'retry': '重试',
  'error': '错误',
  'success': '成功',
  'failed': '失败',
  'copy': '复制',
  'share': '分享',
  'more': '更多',
  'close': '关闭',
  'back': '返回',
  'next': '下一步',
  'submit': '提交',
  'send': '发送',

  // 底部导航
  'tab_chat': '聊天',
  'tab_contacts': '联系人',
  'tab_portal': '网站',
  'tab_discover': '发现',
  'tab_square': '广场',
  'tab_me': '我的',

  // 聊天
  'chats': '聊天',
  'message': '消息',
  'groups': '群组',
  'channels': '频道',
  'messages': '消息',
  'new_chat': '新建聊天',
  'new_group': '新建群组',
  'new_channel': '新建频道',
  'type_message': '输入消息...',
  'send_first_message': '快来发送第一条消息吧～',
  'no_messages': '暂无消息',
  'message_deleted': '消息已删除',
  'photo': '图片',
  'video': '视频',
  'voice': '语音',
  'file': '文件',
  'sticker': '贴纸',
  'reply': '回复',
  'forward': '转发',
  'select_action': '选择',
  'pin': '置顶',
  'unpin': '取消置顶',
  'mute': '静音',
  'unmute': '取消静音',
  'delete_chat': '删除对话',
  'clear_history': '清空记录',
  'typing': '正在输入...',
  'online': '在线',
  'offline': '离线',
  'last_seen': '最后上线',
  'today': '今天',
  'yesterday': '昨天',
  'read_all': '全部已读',

  // 联系人
  'contacts': '联系人',
  'add_contact': '添加联系人',
  'new_contact': '新联系人',
  'contact_info': '联系人信息',
  'phone_number': '手机号',
  'username': '用户名',
  'username_format_error': '用户名只能包含英文、数字和下划线',
  'username_min_length': '用户名至少3位',
  'phone_min_length': '手机号位数至少11位',
  'password_min_length': '密码至少6位',
  'bio': '个人简介',
  'common_groups': '共同群组',
  'block': '拉黑',
  'unblock': '取消拉黑',
  'report': '举报',
  'no_contacts_yet': '还没有联系人',
  'click_to_add_friends': '点击右上角添加新朋友',
  'long_time_ago': '很久以前',

  // 群组/频道
  'group_info': '群组信息',
  'channel_info': '频道信息',
  'members': '成员',
  'admins': '管理员',
  'add_members': '添加成员',
  'remove_member': '移除成员',
  'leave_group': '退出群组',
  'leave_channel': '退出频道',
  'delete_group': '解散群组',
  'delete_channel': '删除频道',
  'group_name': '群组名称',
  'channel_name': '频道名称',
  'description': '描述',
  'invite_link': '邀请链接',
  'copy_link': '复制链接',
  'permissions': '权限',
  'notifications': '通知',

  // 广场/动态
  'square': '广场',
  'moments': '动态',
  'discover_title': '发现',
  'portal_open': '打开网站',
  'portal_open_hint': '点击后将在应用内打开指定网站',
  'portal_external_hint': '桌面端将使用系统浏览器打开指定网站',
  'portal_unavailable': '该栏目暂未开放',
  'portal_disabled_hint': '后台未开启该栏目，或尚未配置可访问的网址',
  'discover_subtitle': '这里展示后台配置的发现入口，点击后可直接在应用内访问',
  'discover_demo_notice': '当前页面内容已经接入后台配置，后续新增、修改或停用入口都可直接在后台管理。',
  'discover_open': '打开',
  'discover_demo_tag': '演示',
  'discover_live_tag': '已接入',
  'discover_empty': '暂无发现入口',
  'new_post': '发布动态',
  'like': '点赞',
  'comment': '评论',
  'comments': '评论',
  'write_comment': '写评论...',
  'no_moments': '暂无动态',

  // 设置
  'settings': '设置',
  'profile': '个人资料',
  'edit_profile': '编辑资料',
  'nickname': '昵称',
  'avatar': '头像',
  'account': '账户',
  'privacy': '隐私',
  'security': '安全',
  'notification_settings': '通知和声音',
  'chat_settings': '聊天设置',
  'data_storage': '数据和存储',
  'language': '语言',
  'appearance': '外观',
  'dark_mode': '深色模式',
  'light_mode': '浅色模式',
  'system_mode': '跟随系统',
  'chinese_red_mode': '中国红',
  'chat_background': '聊天背景',
  'stickers_emoji': '贴纸和表情',
  'devices': '设备',
  'faq': '常见问题',
  'about': '关于',
  'version': '版本',
  'logout': '退出登录',
  'logout_confirm': '确定要退出登录吗？',
  'delete_account': '删除账户',

  // 登录注册
  'login': '登录',
  'register': '注册',
  'no_account_yet': '还没有账号？',
  'login_to_account': '登录您的账号',
  'register_account': '注册账号',
  'username_label': '用户名',
  'password_label': '密码',
  'confirm_password': '确认密码',
  'nickname_label': '昵称',
  'next_step': '下一步',
  'complete_register': '完成注册',
  'register_now': '立即注册',
  'login_now': '立即登录',
  'create_account': '创建账号',
  'setup_account_password': '设置您的登录账号和密码',
  'complete_profile': '完善资料',
  'setup_nickname_avatar': '设置您的昵称和头像',
  'agree_terms_prefix': '我已阅读并同意',
  'please_agree_terms': '请先阅读并同意用户协议和隐私政策',
  'please_enter_username': '请输入用户名',
  'please_enter_password': '请输入密码',
  'please_enter_nickname': '请输入昵称',
  'password_not_match': '两次输入的密码不一致',
  'username_already_used': '该用户名已被使用',

  // 通话
  'call': '通话',
  'voice_call': '语音通话',
  'video_call': '视频通话',
  'incoming_call': '来电',
  'outgoing_call': '呼叫中',
  'call_ended': '通话结束',
  'call_declined': '已拒绝',
  'call_missed': '未接来电',
  'calling': '呼叫中...',
  'connecting': '连接中...',
  'ringing': '响铃中...',
  'end_call': '挂断',
  'answer': '接听',
  'decline': '拒绝',
  'muted': '已静音',
  'speaker': '扬声器',
  'camera': '摄像头',
  'switch_camera': '切换摄像头',

  // 文件操作
  'save_as': '存储到...',
  'show_in_folder': '在 Finder 中显示',
  'open_with': '使用默认应用打开',
  'download': '下载',
  'downloading': '下载中...',
  'downloaded': '已下载',
  'file_saved': '文件已保存',
  'save_failed': '保存失败',

  // 权限
  'permission_required': '需要权限',
  'microphone_permission': '需要麦克风权限才能进行通话',
  'camera_permission': '需要摄像头权限才能进行视频通话',
  'storage_permission': '需要存储权限才能保存文件',
  'notification_permission': '需要通知权限才能接收消息提醒',
  'go_to_settings': '前往设置',

  // 错误消息
  'network_error': '网络错误',
  'server_error': '服务器错误',
  'timeout_error': '请求超时',
  'unknown_error': '未知错误',
  'no_internet': '无网络连接',
  'session_expired': '登录已过期，请重新登录',

  // 时间
  'just_now': '刚刚',
  'minutes_ago': '分钟前',
  'hours_ago': '小时前',
  'days_ago': '天前',

  // 个人资料页
  'set_new_photo': '设置新照片',
  'name': '名字',
  'enter_your_name': '输入你的名字。',
  'username_hint': '你可以选择一个用户名，这样其他人就能通过用户名找到你。\n\n可使用 a-z、0-9 和下划线，最短 5 个字符。',
  'bio_hint': '添加关于你自己的介绍。',
  'no_phone_bound': '未绑定手机',
  'bind': '绑定',
  'change': '更改',
  'your_color': '您的颜色',
  'qr_code': '二维码',
  'invite_friends': '邀请朋友',
  'my_qr_code': '我的二维码',
  'scan_to_add_friend': '扫描二维码添加好友',
  'save_image': '保存图片',
  'username_copied': '用户名已复制',
  'upload_avatar_failed': '上传头像失败',
  'avatar_deleted': '头像已删除',
  'link_copied': '链接已复制',
  'verify_username_first': '请先验证用户名',
  'confirm_change_username': '确认修改用户名？',
  'confirm_change': '确认修改',
  'change_phone': '更换手机号',
  'verify_new_phone': '需要验证新手机号码，确定继续？',
  'take_photo': '拍照',
  'gallery': '相册',
  'delete_photo': '删除照片',
  'crop_avatar': '裁剪头像',

  // 通知设置
  'notifications_and_sounds': '通知和声音',
  'message_notifications': '消息通知',
  'private_messages': '私聊消息',
  'group_messages': '群组消息',
  'channel_messages': '频道消息',
  'moment_notifications': '动态通知',
  'likes_comments_replies': '点赞、评论、回复通知',
  'notification_content': '通知内容',
  'show_message_preview': '显示消息预览',
  'show_message_in_notification': '在通知中显示消息内容',
  'sound_and_vibration': '声音和振动',
  'notification_sound': '通知声音',
  'alert_tone': '提示音',
  'moment_sound': '动态声音',
  'vibration': '振动',
  'in_app_notifications': '应用内通知',
  'in_app_sound': '应用内声音',
  'in_app_vibration': '应用内振动',
  'reset_all_notification_settings': '重置所有通知设置',
  'select_alert_tone': '选择提示音',
  'tap_to_preview': '点击播放预览',
  'reset_to_default': '已重置为默认设置',
  'confirm_reset_notifications': '确定要将所有通知设置恢复为默认值吗？',
  'reset': '重置',

  // 数据存储
  'data_and_storage': '数据和存储',
  'storage': '存储',
  'used_storage_space': '已使用存储空间',
  'manage_storage_space': '管理存储空间',
  'clear_cache': '清除缓存',
  'calculating': '计算中...',
  'auto_download_media': '自动下载媒体',
  'images': '图片',
  'videos': '视频',
  'files': '文件',
  'cache': '缓存',
  'auto_download_hint': '选择是否在 Wi-Fi 和移动网络下自动下载媒体文件',
  'network': '网络',
  'when_using_wifi': '使用 Wi-Fi 时',
  'when_using_mobile': '使用移动网络时',
  'when_roaming': '使用漫游时',
  'download_all_media': '下载所有媒体',
  'download_images_only': '仅下载图片',
  'download_small_files_only': '仅下载小文件',
  'no_download': '不下载',
  'save_settings': '保存',
  'save_to_gallery': '保存到相册',
  'auto_save_to_gallery': '自动将收到的图片和视频保存到相册',
  'data_usage': '数据使用',
  'network_usage_stats': '网络使用统计',
  'sent': '发送',
  'received': '接收',
  'reset_network_usage': '重置网络使用统计',
  'cache_cleared': '缓存已清除',
  'clear_failed': '清除失败',
  'confirm_clear_cache': '确定要清除所有缓存数据吗？\n\n这将删除临时文件，但不会影响你的聊天记录。',
  'total': '总计',
  'last_reset': '上次重置',
  'never_reset': '从未重置',
  'sent_data': '发送数据',
  'received_data': '接收数据',
  'stats_reset': '统计已重置',
  'confirm_reset_stats': '确定要重置网络使用统计吗？这将清除所有已记录的流量数据。',
  'other_files': '其他文件',
  'clear_all_cache': '清除所有缓存',
  'reset_data_stats': '重置数据统计',

  // 设备管理
  'current_device': '当前设备',
  'link_new_device': '链接新设备',
  'scan_qr_code': '扫描二维码',
  'login_to_other_device': '登录到其他设备',
  'scan_qr_code_hint': '在其他设备上打开应用，点击"扫描二维码"即可快速登录。',
  'active_sessions': '活跃会话',
  'devices_count': '台设备',
  'no_other_devices': '暂无其他设备登录',
  'suspicious_device_hint': '如果你发现了可疑的设备登录，可以终止该设备的会话以保护账号安全。',
  'terminate_all_other_devices': '终止所有其他设备',
  'confirm_terminate_all': '确定要终止所有其他设备的会话吗？这将使其他设备上的登录失效。',
  'terminate_all': '终止全部',
  'all_devices_terminated': '已终止所有其他设备',
  'logging_out': '正在退出...',
  'confirm_logout': '确定要离开吗？',
  'logout_hint': '退出后需要重新登录才能使用',
  'terminate_device_session': '终止设备会话',
  'confirm_terminate_device': '确定要终止该设备的会话吗？',
  'device_session_terminated': '已终止该设备会话',
  'operation_failed': '操作失败',
  'terminate': '终止',
  'scan_function': '扫码功能',
  'developing': '开发中',

  // 贴纸和表情
  'installed': '已安装',
  'discover_more': '发现更多',
  'recently_used': '最近使用',
  'no_sticker_packs': '还没有安装贴纸包',
  'go_discover': '去发现更多',
  'sticker_settings': '设置',
  'show_animation_on_send': '发送贴纸时显示动画',
  'auto_play_stickers': '自动播放动态贴纸',
  'emoji_suggestions': '表情包建议',
  'available': '可安装',
  'all_packs_installed': '已安装全部贴纸包',
  'create_sticker_pack': '新建贴纸包',
  'create_sticker_hint': '使用照片创建专属贴纸',
  'stickers_count': '个贴纸',
  'built_in': '内置',
  'install': '安装',
  'preview': '预览',
  'uninstall': '卸载',

  // FAQ
  'faq_title': '常见问题',
  'search_question': '搜索问题...',
  'no_questions_found': '未找到相关问题',
  'contact_support_for_help': '联系客服获取帮助',
  'contact_support': '联系客服',
  'support_description': '在线客服，我们将尽快为您解答',
  'online_support': '在线客服',
  'online_support_hint': '点击打开壹信客服系统，在线沟通',
  'qq_support': 'QQ 客服',
  'questions_count': '个问题',
  'thank_you_feedback': '感谢您的反馈！',
  'was_this_helpful': '这个回答对您有帮助吗？',
  'helpful': '有帮助',
  'not_helpful': '没帮助',

  // 聊天页
  'select_chat': '选择聊天',
  'selected_count': '已选择',
  'select_all': '全选',
  'deselect_all': '取消全选',
  'refreshing': '刷新中...',
  'mark_as_read': '标记已读',
  'no_chats': '暂无聊天',
  'start_new_chat': '开始新的聊天',
  'delete_chats_confirm': '删除聊天？',
  'chat_will_be_removed': '聊天将从列表中移除，但不会删除聊天记录',
  'search_user': '搜索用户',
  'search_user_hint': '搜索用户开始聊天',
  'create_group_hint': '创建一个群聊',
  'create_channel_hint': '创建一个频道发布消息',
  'scan_qr_code_hint_chat': '扫码添加好友或群组',
  'all': '全部',
  'remove_from_list': '从列表中删除',
  'remove_from_list_hint': '仅从聊天列表移除，保留聊天记录',
  'delete_chat_history': '删除聊天记录',
  'delete_chat_history_hint': '清空本地聊天记录，对方的记录不受影响',
  'removed_from_list': '已从列表中移除',
  'confirm_delete_title': '确认删除',
  'confirm_delete_content': '确定要删除所有聊天记录吗？\n\n此操作仅删除您本地的记录，对方手机上的聊天记录不会被删除。',
  'chat_history_deleted': '聊天记录已删除',
  'deleted': '已删除',
  'mark_as_unread': '标记为未读',
  'members_count': '位成员',
  'subscribers_count': '位订阅者',
  'new_private_chat': '新建私聊',
  'search_contacts': '搜索联系人',
  'no_contacts_found': '未找到联系人',
  'open_chat_failed': '打开聊天失败，请重试',
  'media_message': '媒体消息',
  'last_seen_at': '最近上线于',

  // 关于页
  'about_title': '关于',
  'copyright': '© 2024 壹信网络',

  // 空状态
  'select_chat_to_start': '选择一个聊天开始消息',
  'press_to_start_chat': '或按下 ⌘N 开始新聊天',

  // 额外翻译
  'likes_comments_play_sound': '点赞、评论时播放声音',
  'view_sent_received_data': '查看发送和接收的数据量',
  'mobile_network': '移动网络',
  'roaming': '漫游',

  // 创建聊天
  'create': '创建',
  'create_group': '新建群组',
  'create_channel': '新建频道',
  'enter_group_name': '输入群组名称',
  'enter_channel_name': '输入频道名称',
  'select_members': '选择成员',
  'public_group': '公开群组',
  'private_group': '私密群组',
  'public_channel': '公开频道',
  'private_channel': '私密频道',
  'anyone_can_join': '任何人都可以搜索并加入',
  'invite_only': '仅限邀请',
  'create_group_failed': '创建群组失败',
  'create_channel_failed': '创建频道失败',
  'no_contacts': '暂无联系人',
  'add_contacts_first': '请先添加联系人',
  'clear': '清除',
  'recently_online': '最近在线',
  'channel_description_optional': '频道描述（可选）',
  'anyone_can_subscribe': '任何人都可以搜索并订阅',
  'invite_only_subscribe': '只有被邀请才能订阅，不可被搜索',
  'crop_group_avatar': '裁剪群组头像',
  'crop_channel_avatar': '裁剪频道头像',

  // 搜索页面
  'search_user_group_channel': '请输入手机号/群名/频道名',
  'search_user_to_chat': '搜索用户开始聊天',
  'no_need_add_friend': '无需添加好友，直接发起私聊',
  'also_search_public_groups': '也可搜索公开群组和频道',
  'search_chats_contacts_messages': '搜索聊天、联系人和消息',
  'no_search_results': '无搜索结果',
  'chat_history': '聊天记录',

  // 个性化设置
  'personalization_settings': '个性化设置',
  'profile_background': '资料背景',
  'profile_background_hint': '其他人查看您的资料时会看到此背景',
  'nickname_color': '昵称颜色',
  'nickname_color_hint': '在群聊和频道中显示的昵称颜色',
  'user': '用户',

  // 屏蔽用户
  'blocked_users': '已屏蔽用户',
  'no_blocked_users': '没有已屏蔽的用户',
  'blocked_users_hint': '被屏蔽的用户将无法向你发送消息',
  'confirm_unblock': '确定要解除对',
  'unblock_suffix': '的屏蔽吗？',

  // 动态
  'me': '我',
  'publish': '发布',
  'share_your_thoughts': '分享你的想法...',
  'emoji': '表情',
  'album': '相册',
  'topic': '话题',
  'public_visibility': '公开',
  'contacts_visibility': '联系人',
  'private_visibility': '私密',
  'all_loaded': '已加载全部动态',
  'moment_detail': '动态详情',

  // 隐私与安全
  'online_status': '在线状态',
  'who_can_add_to_group': '谁可以将你添加到群组',
  'privacy_hint': '选择谁可以看到你的在线状态、手机号等信息',
  'two_step_verification': '两步验证',
  'add_extra_protection': '为账号添加额外保护',
  'biometric_unlock': '面容/指纹解锁',
  'use_biometric_to_unlock': '使用生物识别解锁应用',
  'app_lock_password': '应用锁定密码',
  'set': '已设置',
  'not_set': '未设置',
  'auto_lock': '自动锁定',
  'auto_delete_account': '账号自动注销',
  'auto_delete_hint': '如果你在此期间未登录过，账号将被自动删除',
  'delete_my_account': '删除我的账号',

  // 聊天设置
  'message_preview': '消息预览',
  'link_preview': '链接预览',
  'show_link_preview_in_message': '在消息中显示网页预览',
  'small': '小',
  'large': '大',
  'media': '媒体',
  'custom_chat_background': '自定义聊天背景',
  'bubble_color': '气泡颜色',
  'default': '默认',
  'auto_download_images': '自动下载图片',
  'auto_download_videos': '自动下载视频',
  'auto_play_gif': '自动播放GIF',

  // 贴纸页
  'auto_play_animated_stickers': '自动播放动态贴纸',
  'sticker_suggestions': '表情包建议',

  // 用户资料页
  'no_bio': '这个人很懒，什么都没留下',
  'photos_and_videos': '照片和视频',
  'shared_links': '共享链接',
  'voice_messages': '语音消息',
  'count_suffix': '个',
  'block_user': '屏蔽用户',
  'unblock_user': '取消屏蔽',

  // 群组/频道资料页
  'no_description': '暂无简介',
  'group_id': '群组号',
  'channel_id': '频道号',
  'copied': '已复制',
  'links': '链接',
  'join_requests': '加入请求',
  'loading_failed': '加载失败',
  'leave_confirm_message': '退出后将不再接收此群组的消息',
  'subscribers': '订阅者',
  'subscribe_requests': '订阅请求',
  'share_channel': '分享频道',
  'subscribe_channel': '订阅频道',
  'unsubscribe': '取消订阅',
  'disband_channel': '解散频道',
  'channel_disbanded': '频道已解散',
  'disband_failed': '解散失败',
  'spam': '垃圾信息',
  'false_info': '虚假信息',
  'violence': '暴力内容',
  'adult_content': '色情内容',
};

const Map<String, String> _zhTW = {
  'app_name': '壹信',

  // 通用
  'confirm': '確認',
  'cancel': '取消',
  'save': '儲存',
  'delete': '刪除',
  'edit': '編輯',
  'done': '完成',
  'search': '搜尋',
  'loading': '載入中...',
  'retry': '重試',
  'error': '錯誤',
  'success': '成功',
  'failed': '失敗',
  'copy': '複製',
  'share': '分享',
  'more': '更多',
  'close': '關閉',
  'back': '返回',
  'next': '下一步',
  'submit': '提交',
  'send': '發送',

  // 底部導航
  'tab_chat': '聊天',
  'tab_contacts': '聯絡人',
  'tab_portal': '網站',
  'tab_discover': '發現',
  'tab_square': '廣場',
  'tab_me': '我的',

  // 聊天
  'chats': '聊天',
  'message': '訊息',
  'groups': '群組',
  'channels': '頻道',
  'messages': '訊息',
  'new_chat': '新建聊天',
  'new_group': '新建群組',
  'new_channel': '新建頻道',
  'type_message': '輸入訊息...',
  'send_first_message': '快來發送第一條訊息吧～',
  'no_messages': '暫無訊息',
  'message_deleted': '訊息已刪除',
  'photo': '圖片',
  'video': '影片',
  'voice': '語音',
  'file': '檔案',
  'sticker': '貼圖',
  'reply': '回覆',
  'forward': '轉發',
  'select_action': '選擇',
  'pin': '置頂',
  'unpin': '取消置頂',
  'mute': '靜音',
  'unmute': '取消靜音',
  'delete_chat': '刪除對話',
  'clear_history': '清空記錄',
  'typing': '正在輸入...',
  'online': '在線',
  'offline': '離線',
  'last_seen': '最後上線',
  'today': '今天',
  'yesterday': '昨天',
  'read_all': '全部已讀',

  // 聯絡人
  'contacts': '聯絡人',
  'add_contact': '新增聯絡人',
  'new_contact': '新聯絡人',
  'contact_info': '聯絡人資訊',
  'phone_number': '手機號碼',
  'username': '使用者名稱',
  'username_format_error': '使用者名稱只能包含英文、數字和底線',
  'username_min_length': '使用者名稱至少3位',
  'phone_min_length': '手機號碼至少11位',
  'password_min_length': '密碼至少6位',
  'bio': '個人簡介',
  'common_groups': '共同群組',
  'block': '封鎖',
  'unblock': '解除封鎖',
  'report': '檢舉',
  'no_contacts_yet': '還沒有聯絡人',
  'click_to_add_friends': '點擊右上角新增好友',
  'long_time_ago': '很久以前',

  // 群組/頻道
  'group_info': '群組資訊',
  'channel_info': '頻道資訊',
  'members': '成員',
  'admins': '管理員',
  'add_members': '新增成員',
  'remove_member': '移除成員',
  'leave_group': '退出群組',
  'leave_channel': '退出頻道',
  'delete_group': '解散群組',
  'delete_channel': '刪除頻道',
  'group_name': '群組名稱',
  'channel_name': '頻道名稱',
  'description': '描述',
  'invite_link': '邀請連結',
  'copy_link': '複製連結',
  'permissions': '權限',
  'notifications': '通知',

  // 廣場/動態
  'square': '廣場',
  'moments': '動態',
  'discover_title': '發現',
  'portal_open': '打開網站',
  'portal_open_hint': '點擊後會在應用內打開指定網站',
  'portal_external_hint': '桌面端會使用系統瀏覽器打開指定網站',
  'portal_unavailable': '此欄目暫未開放',
  'portal_disabled_hint': '後台未啟用此欄目，或尚未配置可訪問網址',
  'discover_subtitle': '這裡展示後台配置的發現入口，點擊後可直接在應用內訪問',
  'discover_demo_notice': '目前頁面內容已接入後台配置，之後新增、修改或停用入口都可直接在後台管理。',
  'discover_open': '打開',
  'discover_demo_tag': '演示',
  'discover_live_tag': '已接入',
  'discover_empty': '暫無發現入口',
  'new_post': '發布動態',
  'like': '按讚',
  'comment': '留言',
  'comments': '留言',
  'write_comment': '寫留言...',
  'no_moments': '暫無動態',

  // 設定
  'settings': '設定',
  'profile': '個人資料',
  'edit_profile': '編輯資料',
  'nickname': '暱稱',
  'avatar': '頭像',
  'account': '帳戶',
  'privacy': '隱私',
  'security': '安全',
  'notification_settings': '通知和聲音',
  'chat_settings': '聊天設定',
  'data_storage': '資料和儲存',
  'language': '語言',
  'appearance': '外觀',
  'dark_mode': '深色模式',
  'light_mode': '淺色模式',
  'system_mode': '跟隨系統',
  'chinese_red_mode': '中國紅',
  'chat_background': '聊天背景',
  'stickers_emoji': '貼圖和表情',
  'devices': '裝置',
  'faq': '常見問題',
  'about': '關於',
  'version': '版本',
  'logout': '登出',
  'logout_confirm': '確定要登出嗎？',
  'delete_account': '刪除帳戶',

  // 登入註冊
  'login': '登入',
  'register': '註冊',
  'no_account_yet': '還沒有帳號？',
  'login_to_account': '登入您的帳號',
  'register_account': '註冊帳號',
  'username_label': '使用者名稱',
  'password_label': '密碼',
  'confirm_password': '確認密碼',
  'nickname_label': '暱稱',
  'next_step': '下一步',
  'complete_register': '完成註冊',
  'register_now': '立即註冊',
  'login_now': '立即登入',
  'create_account': '建立帳號',
  'setup_account_password': '設定您的登入帳號和密碼',
  'complete_profile': '完善資料',
  'setup_nickname_avatar': '設定您的暱稱和頭像',
  'agree_terms_prefix': '我已閱讀並同意',
  'please_agree_terms': '請先閱讀並同意使用者協議和隱私政策',
  'please_enter_username': '請輸入使用者名稱',
  'please_enter_password': '請輸入密碼',
  'please_enter_nickname': '請輸入暱稱',
  'password_not_match': '兩次輸入的密碼不一致',
  'username_already_used': '該使用者名稱已被使用',

  // 通話
  'call': '通話',
  'voice_call': '語音通話',
  'video_call': '視訊通話',
  'incoming_call': '來電',
  'outgoing_call': '撥號中',
  'call_ended': '通話結束',
  'call_declined': '已拒絕',
  'call_missed': '未接來電',
  'calling': '撥號中...',
  'connecting': '連接中...',
  'ringing': '響鈴中...',
  'end_call': '掛斷',
  'answer': '接聽',
  'decline': '拒絕',
  'muted': '已靜音',
  'speaker': '揚聲器',
  'camera': '攝影機',
  'switch_camera': '切換攝影機',

  // 檔案操作
  'save_as': '儲存至...',
  'show_in_folder': '在 Finder 中顯示',
  'open_with': '使用預設應用程式開啟',
  'download': '下載',
  'downloading': '下載中...',
  'downloaded': '已下載',
  'file_saved': '檔案已儲存',
  'save_failed': '儲存失敗',

  // 權限
  'permission_required': '需要權限',
  'microphone_permission': '需要麥克風權限才能進行通話',
  'camera_permission': '需要攝影機權限才能進行視訊通話',
  'storage_permission': '需要儲存權限才能儲存檔案',
  'notification_permission': '需要通知權限才能接收訊息提醒',
  'go_to_settings': '前往設定',

  // 錯誤訊息
  'network_error': '網路錯誤',
  'server_error': '伺服器錯誤',
  'timeout_error': '請求逾時',
  'unknown_error': '未知錯誤',
  'no_internet': '無網路連線',
  'session_expired': '登入已過期，請重新登入',

  // 時間
  'just_now': '剛剛',
  'minutes_ago': '分鐘前',
  'hours_ago': '小時前',
  'days_ago': '天前',

  // 個人資料頁
  'set_new_photo': '設定新照片',
  'name': '名字',
  'enter_your_name': '輸入你的名字。',
  'username_hint':
      '你可以選擇一個使用者名稱，這樣其他人就能通過使用者名稱找到你。\n\n可使用 a-z、0-9 和底線，最短 5 個字元。',
  'bio_hint': '新增關於你自己的介紹。',
  'no_phone_bound': '未綁定手機',
  'bind': '綁定',
  'change': '更改',
  'your_color': '您的顏色',
  'qr_code': 'QR 碼',
  'invite_friends': '邀請朋友',
  'my_qr_code': '我的 QR 碼',
  'scan_to_add_friend': '掃描 QR 碼新增好友',
  'save_image': '儲存圖片',
  'username_copied': '使用者名稱已複製',
  'upload_avatar_failed': '上傳頭像失敗',
  'avatar_deleted': '頭像已刪除',
  'link_copied': '連結已複製',
  'verify_username_first': '請先驗證使用者名稱',
  'confirm_change_username': '確認修改使用者名稱？',
  'confirm_change': '確認修改',
  'change_phone': '更換手機號',
  'verify_new_phone': '需要驗證新手機號碼，確定繼續？',
  'take_photo': '拍照',
  'gallery': '相簿',
  'delete_photo': '刪除照片',
  'crop_avatar': '裁剪頭像',

  // 通知設定
  'notifications_and_sounds': '通知和聲音',
  'message_notifications': '訊息通知',
  'private_messages': '私聊訊息',
  'group_messages': '群組訊息',
  'channel_messages': '頻道訊息',
  'moment_notifications': '動態通知',
  'likes_comments_replies': '按讚、留言、回覆通知',
  'notification_content': '通知內容',
  'show_message_preview': '顯示訊息預覽',
  'show_message_in_notification': '在通知中顯示訊息內容',
  'sound_and_vibration': '聲音和震動',
  'notification_sound': '通知聲音',
  'alert_tone': '提示音',
  'moment_sound': '動態聲音',
  'vibration': '震動',
  'in_app_notifications': '應用程式內通知',
  'in_app_sound': '應用程式內聲音',
  'in_app_vibration': '應用程式內震動',
  'reset_all_notification_settings': '重置所有通知設定',
  'select_alert_tone': '選擇提示音',
  'tap_to_preview': '點擊播放預覽',
  'reset_to_default': '已重置為預設設定',
  'confirm_reset_notifications': '確定要將所有通知設定恢復為預設值嗎？',
  'reset': '重置',

  // 資料儲存
  'data_and_storage': '資料和儲存',
  'storage': '儲存',
  'used_storage_space': '已使用儲存空間',
  'manage_storage_space': '管理儲存空間',
  'clear_cache': '清除快取',
  'calculating': '計算中...',
  'auto_download_media': '自動下載媒體',
  'images': '圖片',
  'videos': '影片',
  'files': '檔案',
  'cache': '快取',
  'auto_download_hint': '選擇是否在 Wi-Fi 和行動網路下自動下載媒體檔案',
  'network': '網路',
  'when_using_wifi': '使用 Wi-Fi 時',
  'when_using_mobile': '使用行動網路時',
  'when_roaming': '使用漫遊時',
  'download_all_media': '下載所有媒體',
  'download_images_only': '僅下載圖片',
  'download_small_files_only': '僅下載小檔案',
  'no_download': '不下載',
  'save_settings': '儲存',
  'save_to_gallery': '儲存到相簿',
  'auto_save_to_gallery': '自動將收到的圖片和影片儲存到相簿',
  'data_usage': '資料使用',
  'network_usage_stats': '網路使用統計',
  'sent': '發送',
  'received': '接收',
  'reset_network_usage': '重置網路使用統計',
  'cache_cleared': '快取已清除',
  'clear_failed': '清除失敗',
  'confirm_clear_cache': '確定要清除所有快取資料嗎？\n\n這將刪除暫存檔案，但不會影響你的聊天記錄。',
  'total': '總計',
  'last_reset': '上次重置',
  'never_reset': '從未重置',
  'sent_data': '發送資料',
  'received_data': '接收資料',
  'stats_reset': '統計已重置',
  'confirm_reset_stats': '確定要重置網路使用統計嗎？這將清除所有已記錄的流量資料。',
  'other_files': '其他檔案',
  'clear_all_cache': '清除所有快取',
  'reset_data_stats': '重置資料統計',

  // 裝置管理
  'current_device': '目前裝置',
  'link_new_device': '連結新裝置',
  'scan_qr_code': '掃描 QR 碼',
  'login_to_other_device': '登入到其他裝置',
  'scan_qr_code_hint': '在其他裝置上開啟應用，點擊「掃描 QR 碼」即可快速登入。',
  'active_sessions': '活躍工作階段',
  'devices_count': '台裝置',
  'no_other_devices': '暫無其他裝置登入',
  'suspicious_device_hint': '如果你發現了可疑的裝置登入，可以終止該裝置的工作階段以保護帳號安全。',
  'terminate_all_other_devices': '終止所有其他裝置',
  'confirm_terminate_all': '確定要終止所有其他裝置的工作階段嗎？這將使其他裝置上的登入失效。',
  'terminate_all': '終止全部',
  'all_devices_terminated': '已終止所有其他裝置',
  'logging_out': '正在登出...',
  'confirm_logout': '確定要離開嗎？',
  'logout_hint': '登出後需要重新登入才能使用',
  'terminate_device_session': '終止裝置工作階段',
  'confirm_terminate_device': '確定要終止該裝置的工作階段嗎？',
  'device_session_terminated': '已終止該裝置工作階段',
  'operation_failed': '操作失敗',
  'terminate': '終止',
  'scan_function': '掃碼功能',
  'developing': '開發中',

  // 貼圖和表情
  'installed': '已安裝',
  'discover_more': '發現更多',
  'recently_used': '最近使用',
  'no_sticker_packs': '還沒有安裝貼圖包',
  'go_discover': '去發現更多',
  'sticker_settings': '設定',
  'show_animation_on_send': '發送貼圖時顯示動畫',
  'auto_play_stickers': '自動播放動態貼圖',
  'emoji_suggestions': '表情包建議',
  'available': '可安裝',
  'all_packs_installed': '已安裝全部貼圖包',
  'create_sticker_pack': '新建貼圖包',
  'create_sticker_hint': '使用照片建立專屬貼圖',
  'stickers_count': '個貼圖',
  'built_in': '內建',
  'install': '安裝',
  'preview': '預覽',
  'uninstall': '解除安裝',

  // FAQ
  'faq_title': '常見問題',
  'search_question': '搜尋問題...',
  'no_questions_found': '未找到相關問題',
  'contact_support_for_help': '聯絡客服獲取幫助',
  'contact_support': '聯絡客服',
  'support_description': '線上客服，我們將盡快為您解答',
  'online_support': '線上客服',
  'online_support_hint': '點擊開啟壹信客服系統，線上溝通',
  'qq_support': 'QQ 客服',
  'questions_count': '個問題',
  'thank_you_feedback': '感謝您的回饋！',
  'was_this_helpful': '這個回答對您有幫助嗎？',
  'helpful': '有幫助',
  'not_helpful': '沒幫助',

  // 聊天頁
  'select_chat': '選擇聊天',
  'selected_count': '已選擇',
  'select_all': '全選',
  'deselect_all': '取消全選',
  'refreshing': '重新整理中...',
  'mark_as_read': '標記已讀',
  'no_chats': '暫無聊天',
  'start_new_chat': '開始新的聊天',
  'delete_chats_confirm': '刪除聊天？',
  'chat_will_be_removed': '聊天將從列表中移除，但不會刪除聊天記錄',
  'search_user': '搜尋使用者',
  'search_user_hint': '搜尋使用者開始聊天',
  'create_group_hint': '建立一個群聊',
  'create_channel_hint': '建立一個頻道發布訊息',
  'scan_qr_code_hint_chat': '掃碼新增好友或群組',
  'all': '全部',
  'remove_from_list': '從列表中刪除',
  'remove_from_list_hint': '僅從聊天列表移除，保留聊天記錄',
  'delete_chat_history': '刪除聊天記錄',
  'delete_chat_history_hint': '清空本地聊天記錄，對方的記錄不受影響',
  'removed_from_list': '已從列表中移除',
  'confirm_delete_title': '確認刪除',
  'confirm_delete_content': '確定要刪除所有聊天記錄嗎？\n\n此操作僅刪除您本地的記錄，對方手機上的聊天記錄不會被刪除。',
  'chat_history_deleted': '聊天記錄已刪除',
  'deleted': '已刪除',
  'mark_as_unread': '標記為未讀',
  'members_count': '位成員',
  'subscribers_count': '位訂閱者',
  'new_private_chat': '新建私聊',
  'search_contacts': '搜尋聯絡人',
  'no_contacts_found': '未找到聯絡人',
  'open_chat_failed': '開啟聊天失敗，請重試',
  'media_message': '媒體訊息',
  'last_seen_at': '最近上線於',

  // 關於頁
  'about_title': '關於',
  'copyright': '© 2024 壹信網路',

  // 空狀態
  'select_chat_to_start': '選擇一個聊天開始訊息',
  'press_to_start_chat': '或按下 ⌘N 開始新聊天',

  // 額外翻譯
  'likes_comments_play_sound': '按讚、留言時播放聲音',
  'view_sent_received_data': '查看發送和接收的資料量',
  'mobile_network': '行動網路',
  'roaming': '漫遊',

  // 建立聊天
  'create': '建立',
  'create_group': '新建群組',
  'create_channel': '新建頻道',
  'enter_group_name': '輸入群組名稱',
  'enter_channel_name': '輸入頻道名稱',
  'select_members': '選擇成員',
  'public_group': '公開群組',
  'private_group': '私密群組',
  'public_channel': '公開頻道',
  'private_channel': '私密頻道',
  'anyone_can_join': '任何人都可以搜尋並加入',
  'invite_only': '僅限邀請',
  'create_group_failed': '建立群組失敗',
  'create_channel_failed': '建立頻道失敗',
  'no_contacts': '暫無聯絡人',
  'add_contacts_first': '請先新增聯絡人',
  'clear': '清除',
  'recently_online': '最近在線',
  'channel_description_optional': '頻道描述（可選）',
  'anyone_can_subscribe': '任何人都可以搜尋並訂閱',
  'invite_only_subscribe': '只有被邀請才能訂閱，不可被搜尋',
  'crop_group_avatar': '裁剪群組頭像',
  'crop_channel_avatar': '裁剪頻道頭像',

  // 搜尋頁面
  'search_user_group_channel': '搜尋用戶、群組或頻道',
  'search_user_to_chat': '搜尋用戶開始聊天',
  'no_need_add_friend': '無需新增好友，直接發起私聊',
  'also_search_public_groups': '也可搜尋公開群組和頻道',
  'search_chats_contacts_messages': '搜尋聊天、聯絡人和訊息',
  'no_search_results': '無搜尋結果',
  'chat_history': '聊天記錄',

  // 個人化設定
  'personalization_settings': '個人化設定',
  'profile_background': '資料背景',
  'profile_background_hint': '其他人查看您的資料時會看到此背景',
  'nickname_color': '暱稱顏色',
  'nickname_color_hint': '在群聊和頻道中顯示的暱稱顏色',
  'user': '用戶',

  // 封鎖用戶
  'blocked_users': '已封鎖用戶',
  'no_blocked_users': '沒有已封鎖的用戶',
  'blocked_users_hint': '被封鎖的用戶將無法向你發送訊息',
  'confirm_unblock': '確定要解除對',
  'unblock_suffix': '的封鎖嗎？',

  // 動態
  'me': '我',
  'publish': '發布',
  'share_your_thoughts': '分享你的想法...',
  'emoji': '表情',
  'album': '相簿',
  'topic': '話題',
  'public_visibility': '公開',
  'contacts_visibility': '聯絡人',
  'private_visibility': '私密',
  'all_loaded': '已載入全部動態',
  'moment_detail': '動態詳情',

  // 隱私與安全
  'online_status': '在線狀態',
  'who_can_add_to_group': '誰可以將你添加到群組',
  'privacy_hint': '選擇誰可以看到你的在線狀態、手機號等資訊',
  'two_step_verification': '兩步驟驗證',
  'add_extra_protection': '為帳號添加額外保護',
  'biometric_unlock': '面容/指紋解鎖',
  'use_biometric_to_unlock': '使用生物識別解鎖應用',
  'app_lock_password': '應用鎖定密碼',
  'set': '已設定',
  'not_set': '未設定',
  'auto_lock': '自動鎖定',
  'auto_delete_account': '帳號自動註銷',
  'auto_delete_hint': '如果你在此期間未登入過，帳號將被自動刪除',
  'delete_my_account': '刪除我的帳號',

  // 聊天設定
  'message_preview': '訊息預覽',
  'link_preview': '連結預覽',
  'show_link_preview_in_message': '在訊息中顯示網頁預覽',
  'small': '小',
  'large': '大',
  'media': '媒體',
  'custom_chat_background': '自訂聊天背景',
  'bubble_color': '氣泡顏色',
  'default': '預設',
  'auto_download_images': '自動下載圖片',
  'auto_download_videos': '自動下載影片',
  'auto_play_gif': '自動播放GIF',

  // 貼圖頁
  'auto_play_animated_stickers': '自動播放動態貼圖',
  'sticker_suggestions': '表情包建議',

  // 用戶資料頁
  'no_bio': '這個人很懶，什麼都沒留下',
  'photos_and_videos': '照片和影片',
  'shared_links': '共享連結',
  'voice_messages': '語音訊息',
  'count_suffix': '個',
  'block_user': '封鎖用戶',
  'unblock_user': '取消封鎖',

  // 群組/頻道資料頁
  'no_description': '暫無簡介',
  'group_id': '群組號',
  'channel_id': '頻道號',
  'copied': '已複製',
  'links': '連結',
  'join_requests': '加入請求',
  'loading_failed': '載入失敗',
  'leave_confirm_message': '退出後將不再接收此群組的訊息',
  'subscribers': '訂閱者',
  'subscribe_requests': '訂閱請求',
  'share_channel': '分享頻道',
  'subscribe_channel': '訂閱頻道',
  'unsubscribe': '取消訂閱',
  'disband_channel': '解散頻道',
  'channel_disbanded': '頻道已解散',
  'disband_failed': '解散失敗',
  'spam': '垃圾訊息',
  'false_info': '虛假訊息',
  'violence': '暴力內容',
  'adult_content': '色情內容',
};

const Map<String, String> _en = {
  'app_name': 'RanChat',

  // Common
  'confirm': 'Confirm',
  'cancel': 'Cancel',
  'save': 'Save',
  'delete': 'Delete',
  'edit': 'Edit',
  'done': 'Done',
  'search': 'Search',
  'loading': 'Loading...',
  'retry': 'Retry',
  'error': 'Error',
  'success': 'Success',
  'failed': 'Failed',
  'copy': 'Copy',
  'share': 'Share',
  'more': 'More',
  'close': 'Close',
  'back': 'Back',
  'next': 'Next',
  'submit': 'Submit',
  'send': 'Send',

  // Bottom Navigation
  'tab_chat': 'Chats',
  'tab_contacts': 'Contacts',
  'tab_portal': 'Web',
  'tab_discover': 'Discover',
  'tab_square': 'Square',
  'tab_me': 'Me',

  // Chat
  'chats': 'Chats',
  'message': 'Message',
  'groups': 'Groups',
  'channels': 'Channels',
  'messages': 'Messages',
  'new_chat': 'New Chat',
  'new_group': 'New Group',
  'new_channel': 'New Channel',
  'type_message': 'Type a message...',
  'send_first_message': 'Send the first message!',
  'no_messages': 'No messages yet',
  'message_deleted': 'Message deleted',
  'photo': 'Photo',
  'video': 'Video',
  'voice': 'Voice',
  'file': 'File',
  'sticker': 'Sticker',
  'reply': 'Reply',
  'forward': 'Forward',
  'select_action': 'Select',
  'pin': 'Pin',
  'unpin': 'Unpin',
  'mute': 'Mute',
  'unmute': 'Unmute',
  'delete_chat': 'Delete Chat',
  'clear_history': 'Clear History',
  'typing': 'typing...',
  'online': 'online',
  'offline': 'offline',
  'last_seen': 'last seen',
  'today': 'Today',
  'yesterday': 'Yesterday',
  'read_all': 'Mark all as read',

  // Contacts
  'contacts': 'Contacts',
  'add_contact': 'Add Contact',
  'new_contact': 'New Contact',
  'contact_info': 'Contact Info',
  'phone_number': 'Phone',
  'username': 'Username',
  'username_format_error':
      'Username can only contain letters, numbers and underscores',
  'username_min_length': 'Username must be at least 3 characters',
  'phone_min_length': 'Phone number must be at least 11 characters',
  'password_min_length': 'Password must be at least 6 characters',
  'bio': 'Bio',
  'common_groups': 'Groups in Common',
  'block': 'Block',
  'unblock': 'Unblock',
  'report': 'Report',
  'no_contacts_yet': 'No contacts yet',
  'click_to_add_friends': 'Tap the + button to add friends',
  'long_time_ago': 'long time ago',

  // Group/Channel
  'group_info': 'Group Info',
  'channel_info': 'Channel Info',
  'members': 'Members',
  'admins': 'Admins',
  'add_members': 'Add Members',
  'remove_member': 'Remove',
  'leave_group': 'Leave Group',
  'leave_channel': 'Leave Channel',
  'delete_group': 'Delete Group',
  'delete_channel': 'Delete Channel',
  'group_name': 'Group Name',
  'channel_name': 'Channel Name',
  'description': 'Description',
  'invite_link': 'Invite Link',
  'copy_link': 'Copy Link',
  'permissions': 'Permissions',
  'notifications': 'Notifications',

  // Square/Moments
  'square': 'Square',
  'moments': 'Moments',
  'discover_title': 'Discover',
  'portal_open': 'Open Website',
  'portal_open_hint': 'Tap to open the configured website inside the app',
  'portal_external_hint':
      'Desktop opens the configured website in your system browser',
  'portal_unavailable': 'This section is unavailable',
  'portal_disabled_hint':
      'The admin panel has not enabled this section or no website has been configured yet',
  'discover_subtitle':
      'This page shows backend-managed discovery entries that open directly inside the app',
  'discover_demo_notice':
      'This page is now connected to backend configuration. New, updated, or disabled entries can be managed from the admin panel.',
  'discover_open': 'Open',
  'discover_demo_tag': 'Demo',
  'discover_live_tag': 'Live',
  'discover_empty': 'No discover items yet',
  'new_post': 'New Post',
  'like': 'Like',
  'comment': 'Comment',
  'comments': 'Comments',
  'write_comment': 'Write a comment...',
  'no_moments': 'No posts yet',

  // Settings
  'settings': 'Settings',
  'profile': 'Profile',
  'edit_profile': 'Edit Profile',
  'nickname': 'Nickname',
  'avatar': 'Avatar',
  'account': 'Account',
  'privacy': 'Privacy',
  'security': 'Security',
  'notification_settings': 'Notifications and Sounds',
  'chat_settings': 'Chat Settings',
  'data_storage': 'Data and Storage',
  'language': 'Language',
  'appearance': 'Appearance',
  'dark_mode': 'Dark',
  'light_mode': 'Light',
  'system_mode': 'System',
  'chinese_red_mode': 'Chinese Red',
  'chat_background': 'Chat Background',
  'stickers_emoji': 'Stickers and Emoji',
  'devices': 'Devices',
  'faq': 'FAQ',
  'about': 'About',
  'version': 'Version',
  'logout': 'Log Out',
  'logout_confirm': 'Are you sure you want to log out?',
  'delete_account': 'Delete Account',

  // Login/Register
  'login': 'Login',
  'register': 'Register',
  'no_account_yet': 'No account yet?',
  'login_to_account': 'Login to your account',
  'register_account': 'Create Account',
  'username_label': 'Username',
  'password_label': 'Password',
  'confirm_password': 'Confirm Password',
  'nickname_label': 'Nickname',
  'next_step': 'Next',
  'complete_register': 'Complete',
  'register_now': 'Register Now',
  'login_now': 'Login Now',
  'create_account': 'Create Account',
  'setup_account_password': 'Set up your username and password',
  'complete_profile': 'Complete Profile',
  'setup_nickname_avatar': 'Set your nickname and avatar',
  'agree_terms_prefix': 'I have read and agree to',
  'please_agree_terms': 'Please read and agree to the Terms and Privacy Policy',
  'please_enter_username': 'Please enter username',
  'please_enter_password': 'Please enter password',
  'please_enter_nickname': 'Please enter nickname',
  'password_not_match': 'Passwords do not match',
  'username_already_used': 'This username is already taken',

  // Call
  'call': 'Call',
  'voice_call': 'Voice Call',
  'video_call': 'Video Call',
  'incoming_call': 'Incoming Call',
  'outgoing_call': 'Calling',
  'call_ended': 'Call Ended',
  'call_declined': 'Declined',
  'call_missed': 'Missed Call',
  'calling': 'Calling...',
  'connecting': 'Connecting...',
  'ringing': 'Ringing...',
  'end_call': 'End',
  'answer': 'Answer',
  'decline': 'Decline',
  'muted': 'Muted',
  'speaker': 'Speaker',
  'camera': 'Camera',
  'switch_camera': 'Switch Camera',

  // File Operations
  'save_as': 'Save As...',
  'show_in_folder': 'Show in Finder',
  'open_with': 'Open with Default App',
  'download': 'Download',
  'downloading': 'Downloading...',
  'downloaded': 'Downloaded',
  'file_saved': 'File saved',
  'save_failed': 'Save failed',

  // Permissions
  'permission_required': 'Permission Required',
  'microphone_permission': 'Microphone permission is required for calls',
  'camera_permission': 'Camera permission is required for video calls',
  'storage_permission': 'Storage permission is required to save files',
  'notification_permission':
      'Notification permission is required for message alerts',
  'go_to_settings': 'Go to Settings',

  // Error Messages
  'network_error': 'Network Error',
  'server_error': 'Server Error',
  'timeout_error': 'Request Timeout',
  'unknown_error': 'Unknown Error',
  'no_internet': 'No Internet Connection',
  'session_expired': 'Session expired. Please log in again.',

  // Time
  'just_now': 'just now',
  'minutes_ago': 'min ago',
  'hours_ago': 'hr ago',
  'days_ago': 'd ago',

  // Profile Page
  'set_new_photo': 'Set New Photo',
  'name': 'Name',
  'enter_your_name': 'Enter your name.',
  'username_hint':
      'You can choose a username so others can find you.\n\nYou can use a-z, 0-9 and underscores. Minimum 5 characters.',
  'bio_hint': 'Add a few words about yourself.',
  'no_phone_bound': 'No phone linked',
  'bind': 'Link',
  'change': 'Change',
  'your_color': 'Your Color',
  'qr_code': 'QR Code',
  'invite_friends': 'Invite Friends',
  'my_qr_code': 'My QR Code',
  'scan_to_add_friend': 'Scan to add friend',
  'save_image': 'Save Image',
  'username_copied': 'Username copied',
  'upload_avatar_failed': 'Failed to upload avatar',
  'avatar_deleted': 'Avatar deleted',
  'link_copied': 'Link copied',
  'verify_username_first': 'Please verify username first',
  'confirm_change_username': 'Confirm change username?',
  'confirm_change': 'Confirm',
  'change_phone': 'Change Phone',
  'verify_new_phone': 'You need to verify your new phone number. Continue?',
  'take_photo': 'Take Photo',
  'gallery': 'Gallery',
  'delete_photo': 'Delete Photo',
  'crop_avatar': 'Crop Avatar',

  // Notification Settings
  'notifications_and_sounds': 'Notifications and Sounds',
  'message_notifications': 'Message Notifications',
  'private_messages': 'Private Messages',
  'group_messages': 'Group Messages',
  'channel_messages': 'Channel Messages',
  'moment_notifications': 'Moment Notifications',
  'likes_comments_replies': 'Likes, comments, replies',
  'notification_content': 'Notification Content',
  'show_message_preview': 'Show Message Preview',
  'show_message_in_notification': 'Show message content in notifications',
  'sound_and_vibration': 'Sound and Vibration',
  'notification_sound': 'Notification Sound',
  'alert_tone': 'Alert Tone',
  'moment_sound': 'Moment Sound',
  'vibration': 'Vibration',
  'in_app_notifications': 'In-App Notifications',
  'in_app_sound': 'In-App Sound',
  'in_app_vibration': 'In-App Vibration',
  'reset_all_notification_settings': 'Reset All Notification Settings',
  'select_alert_tone': 'Select Alert Tone',
  'tap_to_preview': 'Tap to preview',
  'reset_to_default': 'Reset to default',
  'confirm_reset_notifications':
      'Are you sure you want to reset all notification settings to default?',
  'reset': 'Reset',

  // Data Storage
  'data_and_storage': 'Data and Storage',
  'storage': 'Storage',
  'used_storage_space': 'Used Storage Space',
  'manage_storage_space': 'Manage Storage',
  'clear_cache': 'Clear Cache',
  'calculating': 'Calculating...',
  'auto_download_media': 'Auto-Download Media',
  'images': 'Images',
  'videos': 'Videos',
  'files': 'Files',
  'cache': 'Cache',
  'auto_download_hint':
      'Choose whether to automatically download media on Wi-Fi and mobile data',
  'network': 'Network',
  'when_using_wifi': 'When Using Wi-Fi',
  'when_using_mobile': 'When Using Mobile Data',
  'when_roaming': 'When Roaming',
  'download_all_media': 'Download All Media',
  'download_images_only': 'Download Images Only',
  'download_small_files_only': 'Download Small Files Only',
  'no_download': 'No Download',
  'save_settings': 'Save',
  'save_to_gallery': 'Save to Gallery',
  'auto_save_to_gallery':
      'Automatically save received photos and videos to gallery',
  'data_usage': 'Data Usage',
  'network_usage_stats': 'Network Usage Stats',
  'sent': 'Sent',
  'received': 'Received',
  'reset_network_usage': 'Reset Network Usage',
  'cache_cleared': 'Cache cleared',
  'clear_failed': 'Clear failed',
  'confirm_clear_cache':
      'Are you sure you want to clear all cache?\n\nThis will delete temporary files but won\'t affect your chat history.',
  'total': 'Total',
  'last_reset': 'Last Reset',
  'never_reset': 'Never',
  'sent_data': 'Sent Data',
  'received_data': 'Received Data',
  'stats_reset': 'Stats reset',
  'confirm_reset_stats':
      'Are you sure you want to reset network usage stats? This will clear all recorded data.',
  'other_files': 'Other Files',
  'clear_all_cache': 'Clear All Cache',
  'reset_data_stats': 'Reset Data Stats',

  // Device Management
  'current_device': 'Current Device',
  'link_new_device': 'Link New Device',
  'scan_qr_code': 'Scan QR Code',
  'login_to_other_device': 'Log in to another device',
  'scan_qr_code_hint':
      'Open RanChat on another device and tap "Scan QR Code" to log in quickly.',
  'active_sessions': 'Active Sessions',
  'devices_count': 'devices',
  'no_other_devices': 'No other devices logged in',
  'suspicious_device_hint':
      'If you notice a suspicious login, you can terminate that device\'s session to protect your account.',
  'terminate_all_other_devices': 'Terminate All Other Devices',
  'confirm_terminate_all':
      'Are you sure you want to terminate all other sessions? This will log out all other devices.',
  'terminate_all': 'Terminate All',
  'all_devices_terminated': 'All other devices terminated',
  'logging_out': 'Logging out...',
  'confirm_logout': 'Are you sure you want to leave?',
  'logout_hint': 'You will need to log in again to use the app',
  'terminate_device_session': 'Terminate Device Session',
  'confirm_terminate_device':
      'Are you sure you want to terminate this device session?',
  'device_session_terminated': 'Device session terminated',
  'operation_failed': 'Operation failed',
  'terminate': 'Terminate',
  'scan_function': 'Scan Feature',
  'developing': 'Coming soon',

  // Stickers and Emoji
  'installed': 'Installed',
  'discover_more': 'Discover More',
  'recently_used': 'Recently Used',
  'no_sticker_packs': 'No sticker packs installed',
  'go_discover': 'Discover More',
  'sticker_settings': 'Settings',
  'show_animation_on_send': 'Show Animation on Send',
  'auto_play_stickers': 'Auto-Play Animated Stickers',
  'emoji_suggestions': 'Emoji Suggestions',
  'available': 'Available',
  'all_packs_installed': 'All packs installed',
  'create_sticker_pack': 'Create Sticker Pack',
  'create_sticker_hint': 'Create custom stickers from your photos',
  'stickers_count': 'stickers',
  'built_in': 'Built-in',
  'install': 'Install',
  'preview': 'Preview',
  'uninstall': 'Uninstall',

  // FAQ
  'faq_title': 'FAQ',
  'search_question': 'Search questions...',
  'no_questions_found': 'No questions found',
  'contact_support_for_help': 'Contact support for help',
  'contact_support': 'Contact Support',
  'support_description': 'Online support, we\'ll get back to you soon',
  'online_support': 'Online Support',
  'online_support_hint': 'Click to open support chat',
  'qq_support': 'QQ Support',
  'questions_count': 'questions',
  'thank_you_feedback': 'Thank you for your feedback!',
  'was_this_helpful': 'Was this helpful?',
  'helpful': 'Helpful',
  'not_helpful': 'Not Helpful',

  // Chat Page
  'select_chat': 'Select Chat',
  'selected_count': 'selected',
  'select_all': 'Select All',
  'deselect_all': 'Deselect All',
  'refreshing': 'Refreshing...',
  'mark_as_read': 'Mark as Read',
  'no_chats': 'No chats',
  'start_new_chat': 'Start a new chat',
  'delete_chats_confirm': 'Delete chats?',
  'chat_will_be_removed':
      'Chats will be removed from the list, but chat history will be kept',
  'search_user': 'Search Users',
  'search_user_hint': 'Search users to start chatting',
  'create_group_hint': 'Create a group chat',
  'create_channel_hint': 'Create a channel to broadcast messages',
  'scan_qr_code_hint_chat': 'Scan to add friends or join groups',
  'all': 'All',
  'remove_from_list': 'Remove from List',
  'remove_from_list_hint': 'Only removes from chat list, keeps chat history',
  'delete_chat_history': 'Delete Chat History',
  'delete_chat_history_hint':
      'Clears local chat history, other party\'s history is unaffected',
  'removed_from_list': 'Removed from list',
  'confirm_delete_title': 'Confirm Delete',
  'confirm_delete_content':
      'Are you sure you want to delete all chat history?\n\nThis only deletes your local copy. The other party\'s history won\'t be affected.',
  'chat_history_deleted': 'Chat history deleted',
  'deleted': 'Deleted',
  'mark_as_unread': 'Mark as Unread',
  'members_count': 'members',
  'subscribers_count': 'subscribers',
  'new_private_chat': 'New Private Chat',
  'search_contacts': 'Search contacts',
  'no_contacts_found': 'No contacts found',
  'open_chat_failed': 'Failed to open chat. Please try again.',
  'media_message': 'Media message',
  'last_seen_at': 'last seen',

  // About Page
  'about_title': 'About',
  'copyright': '© 2024 GaoRan Network',

  // Empty State
  'select_chat_to_start': 'Select a chat to start messaging',
  'press_to_start_chat': 'or press ⌘N to start a new chat',

  // Additional translations
  'likes_comments_play_sound': 'Play sound for likes and comments',
  'view_sent_received_data': 'View sent and received data',
  'mobile_network': 'Mobile Network',
  'roaming': 'Roaming',

  // Create chat
  'create': 'Create',
  'create_group': 'New Group',
  'create_channel': 'New Channel',
  'enter_group_name': 'Enter group name',
  'enter_channel_name': 'Enter channel name',
  'select_members': 'Select Members',
  'public_group': 'Public Group',
  'private_group': 'Private Group',
  'public_channel': 'Public Channel',
  'private_channel': 'Private Channel',
  'anyone_can_join': 'Anyone can search and join',
  'invite_only': 'Invite only',
  'create_group_failed': 'Failed to create group',
  'create_channel_failed': 'Failed to create channel',
  'no_contacts': 'No contacts',
  'add_contacts_first': 'Please add contacts first',
  'clear': 'Clear',
  'recently_online': 'Recently online',
  'channel_description_optional': 'Channel description (optional)',
  'anyone_can_subscribe': 'Anyone can search and subscribe',
  'invite_only_subscribe': 'Invite only, not searchable',
  'crop_group_avatar': 'Crop Group Avatar',
  'crop_channel_avatar': 'Crop Channel Avatar',

  // Search page
  'search_user_group_channel': 'Search users, groups or channels',
  'search_user_to_chat': 'Search users to start chatting',
  'no_need_add_friend': 'Start chatting without adding as friend',
  'also_search_public_groups': 'You can also search public groups and channels',
  'search_chats_contacts_messages': 'Search chats, contacts and messages',
  'no_search_results': 'No results found',
  'chat_history': 'Chat History',

  // Personalization settings
  'personalization_settings': 'Personalization',
  'profile_background': 'Profile Background',
  'profile_background_hint':
      'Others will see this background when viewing your profile',
  'nickname_color': 'Nickname Color',
  'nickname_color_hint': 'Your nickname color in groups and channels',
  'user': 'User',

  // Blocked users
  'blocked_users': 'Blocked Users',
  'no_blocked_users': 'No blocked users',
  'blocked_users_hint': 'Blocked users cannot send you messages',
  'confirm_unblock': 'Are you sure you want to unblock',
  'unblock_suffix': '?',

  // Moments
  'me': 'Me',
  'publish': 'Publish',
  'share_your_thoughts': 'Share your thoughts...',
  'emoji': 'Emoji',
  'album': 'Album',
  'topic': 'Topic',
  'public_visibility': 'Public',
  'contacts_visibility': 'Contacts',
  'private_visibility': 'Private',
  'all_loaded': 'All posts loaded',
  'moment_detail': 'Moment Detail',

  // Privacy & Security
  'online_status': 'Online Status',
  'who_can_add_to_group': 'Who can add you to groups',
  'privacy_hint': 'Choose who can see your online status, phone number, etc.',
  'two_step_verification': 'Two-Step Verification',
  'add_extra_protection': 'Add extra protection to your account',
  'biometric_unlock': 'Face/Fingerprint Unlock',
  'use_biometric_to_unlock': 'Use biometrics to unlock app',
  'app_lock_password': 'App Lock Password',
  'set': 'Set',
  'not_set': 'Not Set',
  'auto_lock': 'Auto Lock',
  'auto_delete_account': 'Auto-Delete Account',
  'auto_delete_hint':
      'If you don\'t log in during this period, your account will be deleted',
  'delete_my_account': 'Delete My Account',

  // Chat Settings
  'message_preview': 'Message Preview',
  'link_preview': 'Link Preview',
  'show_link_preview_in_message': 'Show website preview in messages',
  'small': 'Small',
  'large': 'Large',
  'media': 'Media',
  'custom_chat_background': 'Custom chat background',
  'bubble_color': 'Bubble Color',
  'default': 'Default',
  'auto_download_images': 'Auto Download Images',
  'auto_download_videos': 'Auto Download Videos',
  'auto_play_gif': 'Auto Play GIF',

  // Stickers Page
  'auto_play_animated_stickers': 'Auto play animated stickers',
  'sticker_suggestions': 'Sticker Suggestions',

  // User Profile Page
  'no_bio': 'No bio yet',
  'photos_and_videos': 'Photos & Videos',
  'shared_links': 'Shared Links',
  'voice_messages': 'Voice Messages',
  'count_suffix': '',
  'block_user': 'Block User',
  'unblock_user': 'Unblock User',

  // Group/Channel Profile Page
  'no_description': 'No description',
  'group_id': 'Group ID',
  'channel_id': 'Channel ID',
  'copied': 'Copied',
  'links': 'Links',
  'join_requests': 'Join Requests',
  'loading_failed': 'Loading failed',
  'leave_confirm_message':
      'You will no longer receive messages from this group',
  'subscribers': 'Subscribers',
  'subscribe_requests': 'Subscribe Requests',
  'share_channel': 'Share Channel',
  'subscribe_channel': 'Subscribe Channel',
  'unsubscribe': 'Unsubscribe',
  'disband_channel': 'Disband Channel',
  'channel_disbanded': 'Channel disbanded',
  'disband_failed': 'Disband failed',
  'spam': 'Spam',
  'false_info': 'False Information',
  'violence': 'Violence',
  'adult_content': 'Adult Content',
};
