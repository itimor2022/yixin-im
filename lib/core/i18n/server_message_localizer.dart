// 文件用途：实现 server message localizer 相关逻辑，服务于国际化与文案。
// 核心逻辑：围绕 server message localizer 组织，完成输入校验、核心处理和结果回传。
import 'app_localizations.dart';

// 关键声明：server message localizer 是服务端文案转换入口，负责把错误码或服务端文本映射为当前语言。
String _serverMessageText({
  required String zhCN,
  String? zhTW,
  required String en,
}) {
  switch (AppLocalizations.currentLanguage) {
    case AppLanguage.en:
      return en;
    case AppLanguage.zhTW:
      return zhTW ?? zhCN;
    case AppLanguage.zhCN:
      return zhCN;
  }
}

// 流程逻辑：`containsHanText` 先校验输入并完成空值/格式规范化，再返回稳定结果，不承担页面或网络副作用。
bool containsHanText(String value) {
  return RegExp(r'[\u4e00-\u9fff]').hasMatch(value);
}

String localizeServerMessage(
  String? raw, {
  String? fallbackZhCN,
  String? fallbackZhTW,
  String? fallbackEn,
}) {
  final message = raw?.trim() ?? '';
  if (message.isEmpty) {
    return _serverFallbackMessage(
      fallbackZhCN: fallbackZhCN,
      fallbackZhTW: fallbackZhTW,
      fallbackEn: fallbackEn,
    );
  }

  final localized = _translateKnownServerMessage(message);
  if (localized != null) {
    return localized;
  }

  if (!containsHanText(message)) {
    return message;
  }

  if (fallbackZhCN != null || fallbackZhTW != null || fallbackEn != null) {
    // Keep unknown Chinese server messages visible on Chinese clients. These
    // messages often contain the actionable reason, such as muted chats,
    // blocked users, or temporary message-store failures.
    switch (AppLocalizations.currentLanguage) {
      case AppLanguage.zhCN:
      case AppLanguage.zhTW:
        return message;
      case AppLanguage.en:
        return _serverFallbackMessage(
          fallbackZhCN: fallbackZhCN,
          fallbackZhTW: fallbackZhTW,
          fallbackEn: fallbackEn,
        );
    }
  }

  switch (AppLocalizations.currentLanguage) {
    case AppLanguage.zhCN:
    case AppLanguage.zhTW:
      return message;
    case AppLanguage.en:
      return _serverMessageText(
        zhCN: '请求失败，请稍后重试',
        zhTW: '請求失敗，請稍後重試',
        en: 'Request failed. Please try again.',
      );
  }
}

String _serverFallbackMessage({
  String? fallbackZhCN,
  String? fallbackZhTW,
  String? fallbackEn,
}) {
  return _serverMessageText(
    zhCN: fallbackZhCN ?? '请求失败，请稍后重试',
    zhTW: fallbackZhTW ?? fallbackZhCN ?? '請求失敗，請稍後重試',
    en: fallbackEn ?? 'Request failed. Please try again.',
  );
}

String? _translateKnownServerMessage(String message) {
  switch (message) {
    case '参数错误':
      return _serverMessageText(
        zhCN: '参数错误',
        zhTW: '參數錯誤',
        en: 'Invalid parameters',
      );
    case '请先登录':
      return _serverMessageText(
        zhCN: '请先登录',
        zhTW: '請先登入',
        en: 'Please sign in first',
      );
    case '用户未登录':
      return _serverMessageText(
        zhCN: '用户未登录',
        zhTW: '使用者未登入',
        en: 'User is not signed in',
      );
    case '用户不存在':
      return _serverMessageText(
        zhCN: '用户不存在',
        zhTW: '使用者不存在',
        en: 'User does not exist',
      );
    case '请先绑定手机号':
      return _serverMessageText(
        zhCN: '请先绑定手机号',
        zhTW: '請先綁定手機號',
        en: 'Please bind your phone number first',
      );
    case 'Token格式错误':
      return _serverMessageText(
        zhCN: 'Token格式错误',
        zhTW: 'Token 格式錯誤',
        en: 'Invalid token format',
      );
    case 'Token无效或已过期':
      return _serverMessageText(
        zhCN: 'Token无效或已过期',
        zhTW: 'Token 無效或已過期',
        en: 'The token is invalid or expired',
      );
    case '请求过于频繁，请稍后再试':
      return _serverMessageText(
        zhCN: '请求过于频繁，请稍后再试',
        zhTW: '請求過於頻繁，請稍後再試',
        en: 'Too many requests. Please try again later.',
      );
    case '操作过于频繁，请稍后再试':
      return _serverMessageText(
        zhCN: '操作过于频繁，请稍后再试',
        zhTW: '操作過於頻繁，請稍後再試',
        en: 'Too many actions. Please try again later.',
      );
    case '开通 VIP 后可创建群聊':
      return _serverMessageText(
        zhCN: '开通 VIP 后可创建群聊',
        zhTW: '開通 VIP 後可建立群聊',
        en: 'Activate VIP to create groups',
      );
    case '开通 SVIP 后可创建频道':
      return _serverMessageText(
        zhCN: '开通 SVIP 后可创建频道',
        zhTW: '開通 SVIP 後可建立頻道',
        en: 'Activate SVIP to create channels',
      );
    case '开通 SVIP 后可设置公开群号和公开频道':
      return _serverMessageText(
        zhCN: '开通 SVIP 后可设置公开群号和公开频道',
        zhTW: '開通 SVIP 後可設定公開群號和公開頻道',
        en: 'Activate SVIP to set public group and channel IDs',
      );
    case '开通 SVIP 后可开启群成员保护':
      return _serverMessageText(
        zhCN: '开通 SVIP 后可开启群成员保护',
        zhTW: '開通 SVIP 後可開啟群成員保護',
        en: 'Activate SVIP to protect the member list',
      );
    case '当前会员权限不足':
      return _serverMessageText(
        zhCN: '当前会员权限不足',
        zhTW: '目前會員權限不足',
        en: 'Your current VIP plan does not include this benefit',
      );
    case '校验会员权限失败':
      return _serverMessageText(
        zhCN: '校验会员权限失败',
        zhTW: '檢查會員權限失敗',
        en: 'Failed to check VIP permissions',
      );
    case '请选择会员套餐':
      return _serverMessageText(
        zhCN: '请选择会员套餐',
        zhTW: '請選擇會員套餐',
        en: 'Please choose a VIP plan',
      );
    case '会员套餐不存在':
      return _serverMessageText(
        zhCN: '会员套餐不存在',
        zhTW: '會員套餐不存在',
        en: 'The VIP plan does not exist',
      );
    case '会员套餐不存在或已下架':
      return _serverMessageText(
        zhCN: '会员套餐不存在或已下架',
        zhTW: '會員套餐不存在或已下架',
        en: 'The VIP plan does not exist or is no longer available',
      );
    case '钱包余额不足':
      return _serverMessageText(
        zhCN: '钱包余额不足',
        zhTW: '錢包餘額不足',
        en: 'Insufficient wallet balance',
      );
    case '钱包已锁定，无法购买会员':
      return _serverMessageText(
        zhCN: '钱包已锁定，无法购买会员',
        zhTW: '錢包已鎖定，無法購買會員',
        en: 'Your wallet is locked and cannot purchase VIP',
      );
    case '当前已是更高等级会员，请选择同级或更高级套餐':
      return _serverMessageText(
        zhCN: '当前已是更高等级会员，请选择同级或更高级套餐',
        zhTW: '目前已是更高等級會員，請選擇同級或更高級套餐',
        en: 'You already have a higher VIP level. Choose the same or a higher plan.',
      );
    case '获取会员套餐失败':
      return _serverMessageText(
        zhCN: '获取会员套餐失败',
        zhTW: '取得會員套餐失敗',
        en: 'Failed to load VIP plans',
      );
    case '获取会员状态失败':
      return _serverMessageText(
        zhCN: '获取会员状态失败',
        zhTW: '取得會員狀態失敗',
        en: 'Failed to load VIP status',
      );
    case '获取会员订单失败':
      return _serverMessageText(
        zhCN: '获取会员订单失败',
        zhTW: '取得會員訂單失敗',
        en: 'Failed to load VIP orders',
      );
    case '用户名至少3位':
      return _serverMessageText(
        zhCN: '用户名至少3位',
        zhTW: '使用者名稱至少 3 位',
        en: 'Username must be at least 3 characters',
      );
    case '用户名最多20位':
      return _serverMessageText(
        zhCN: '用户名最多20位',
        zhTW: '使用者名稱最多 20 位',
        en: 'Username can be up to 20 characters',
      );
    case '该用户名已被使用':
      return _serverMessageText(
        zhCN: '该用户名已被使用',
        zhTW: '該使用者名稱已被使用',
        en: 'This username is already taken',
      );
    case '用户名可用':
      return _serverMessageText(
        zhCN: '用户名可用',
        zhTW: '使用者名稱可用',
        en: 'Username is available',
      );
    case '系统暂不开放注册，请联系管理员':
      return _serverMessageText(
        zhCN: '系统暂不开放注册，请联系管理员',
        zhTW: '系統暫不開放註冊，請聯絡管理員',
        en: 'Registration is currently unavailable. Please contact the administrator.',
      );
    case '参数错误：用户名3-20位，密码6-20位':
      return _serverMessageText(
        zhCN: '参数错误：用户名3-20位，密码6-20位',
        zhTW: '參數錯誤：使用者名稱 3-20 位，密碼 6-20 位',
        en: 'Invalid parameters: username must be 3-20 characters and password must be 6-20 characters',
      );
    case '用户名长度需为3-20位':
      return _serverMessageText(
        zhCN: '用户名长度需为3-20位',
        zhTW: '使用者名稱長度需為 3-20 位',
        en: 'Username length must be 3-20 characters',
      );
    case '用户名只能包含字母、数字和下划线':
      return _serverMessageText(
        zhCN: '用户名只能包含字母、数字和下划线',
        zhTW: '使用者名稱只能包含字母、數字和底線',
        en: 'Username can only contain letters, numbers, and underscores',
      );
    case '昵称不能为空':
      return _serverMessageText(
        zhCN: '昵称不能为空',
        zhTW: '暱稱不能為空',
        en: 'Nickname cannot be empty',
      );
    case '当前注册必须填写邀请码':
      return _serverMessageText(
        zhCN: '当前注册必须填写邀请码',
        zhTW: '目前註冊必須填寫邀請碼',
        en: 'An invite code is required for registration',
      );
    case '用户名已存在':
      return _serverMessageText(
        zhCN: '用户名已存在',
        zhTW: '使用者名稱已存在',
        en: 'Username already exists',
      );
    case '注册失败':
      return _serverMessageText(
        zhCN: '注册失败',
        zhTW: '註冊失敗',
        en: 'Registration failed',
      );
    case '生成Token失败':
      return _serverMessageText(
        zhCN: '生成Token失败',
        zhTW: '產生 Token 失敗',
        en: 'Failed to generate token',
      );
    case '记录登录会话失败':
      return _serverMessageText(
        zhCN: '记录登录会话失败',
        zhTW: '記錄登入會話失敗',
        en: 'Failed to record the login session',
      );
    case '用户名或密码错误':
      return _serverMessageText(
        zhCN: '用户名或密码错误',
        zhTW: '使用者名稱或密碼錯誤',
        en: 'Incorrect username or password',
      );
    case '登录失败，请稍后重试':
      return _serverMessageText(
        zhCN: '登录失败，请稍后重试',
        zhTW: '登入失敗，請稍後重試',
        en: 'Login failed. Please try again later.',
      );
    case '账号已被禁用':
      return _serverMessageText(
        zhCN: '账号已被禁用',
        zhTW: '帳號已被停用',
        en: 'This account has been disabled',
      );
    case '新设备登录需要短信验证':
      return _serverMessageText(
        zhCN: '新设备登录需要短信验证',
        zhTW: '新裝置登入需要簡訊驗證',
        en: 'This new device requires SMS verification to sign in',
      );
    case '已开启设备锁，请先绑定手机号':
      return _serverMessageText(
        zhCN: '已开启设备锁，请先绑定手机号',
        zhTW: '已開啟裝置鎖，請先綁定手機號',
        en: 'Device lock is enabled. Please bind your phone number first',
      );
    case '设备锁已开启，但短信服务不可用':
      return _serverMessageText(
        zhCN: '设备锁已开启，但短信服务不可用',
        zhTW: '裝置鎖已開啟，但簡訊服務不可用',
        en: 'Device lock is enabled, but the SMS service is unavailable',
      );
    case '请求过于频繁，请1分钟后再试':
      return _serverMessageText(
        zhCN: '请求过于频繁，请1分钟后再试',
        zhTW: '請求過於頻繁，請 1 分鐘後再試',
        en: 'Too many requests. Please try again in 1 minute.',
      );
    case '验证码缓存失败':
      return _serverMessageText(
        zhCN: '验证码缓存失败',
        zhTW: '驗證碼快取失敗',
        en: 'Failed to cache the verification code',
      );
    case '短信发送失败，请稍后重试':
      return _serverMessageText(
        zhCN: '短信发送失败，请稍后重试',
        zhTW: '簡訊發送失敗，請稍後重試',
        en: 'Failed to send the SMS. Please try again later.',
      );
    case '验证已过期，请重新登录':
      return _serverMessageText(
        zhCN: '验证已过期，请重新登录',
        zhTW: '驗證已過期，請重新登入',
        en: 'Verification expired. Please sign in again.',
      );
    case '验证码错误':
      return _serverMessageText(
        zhCN: '验证码错误',
        zhTW: '驗證碼錯誤',
        en: 'Incorrect verification code',
      );
    case '发送失败':
      return _serverMessageText(
        zhCN: '发送失败',
        zhTW: '發送失敗',
        en: 'Send failed',
      );
    case '绑定失败':
      return _serverMessageText(
        zhCN: '绑定失败',
        zhTW: '綁定失敗',
        en: 'Binding failed',
      );
    case '验证失败':
      return _serverMessageText(
        zhCN: '验证失败',
        zhTW: '驗證失敗',
        en: 'Verification failed',
      );
    case '修改失败':
      return _serverMessageText(
        zhCN: '修改失败',
        zhTW: '修改失敗',
        en: 'Update failed',
      );
    case '重置失败':
      return _serverMessageText(
        zhCN: '重置失败',
        zhTW: '重置失敗',
        en: 'Reset failed',
      );
    case '创建二维码登录失败':
      return _serverMessageText(
        zhCN: '创建二维码登录失败',
        zhTW: '建立 QR 碼登入失敗',
        en: 'Failed to create QR login',
      );
    case '获取二维码登录状态失败':
      return _serverMessageText(
        zhCN: '获取二维码登录状态失败',
        zhTW: '取得 QR 碼登入狀態失敗',
        en: 'Failed to get QR login status',
      );
    case '确认登录失败':
      return _serverMessageText(
        zhCN: '确认登录失败',
        zhTW: '確認登入失敗',
        en: 'Login confirmation failed',
      );
    case '二维码已过期':
      return _serverMessageText(
        zhCN: '二维码已过期',
        zhTW: 'QR 碼已過期',
        en: 'The QR code has expired',
      );
    case '登录确认成功':
      return _serverMessageText(
        zhCN: '登录确认成功',
        zhTW: '登入確認成功',
        en: 'Login confirmed successfully',
      );
    case '加载失败':
      return _serverMessageText(
        zhCN: '加载失败',
        zhTW: '載入失敗',
        en: 'Load failed',
      );
    case '网络错误，请稍后重试':
      return _serverMessageText(
        zhCN: '网络错误，请稍后重试',
        zhTW: '網路錯誤，請稍後重試',
        en: 'Network error. Please try again later.',
      );
    case '操作失败':
      return _serverMessageText(
        zhCN: '操作失败',
        zhTW: '操作失敗',
        en: 'Action failed',
      );
    case '保存失败':
      return _serverMessageText(
        zhCN: '保存失败',
        zhTW: '保存失敗',
        en: 'Save failed',
      );
    case '获取钱包失败':
      return _serverMessageText(
        zhCN: '获取钱包失败',
        zhTW: '取得錢包失敗',
        en: 'Failed to load wallet',
      );
    case '设置密码失败':
      return _serverMessageText(
        zhCN: '设置密码失败',
        zhTW: '設定密碼失敗',
        en: 'Failed to set password',
      );
    case '未设置支付密码':
      return _serverMessageText(
        zhCN: '未设置支付密码',
        zhTW: '尚未設定支付密碼',
        en: 'Payment password is not set',
      );
    case '支付密码错误':
      return _serverMessageText(
        zhCN: '支付密码错误',
        zhTW: '支付密碼錯誤',
        en: 'Incorrect payment password',
      );
    case '请输入密码':
      return _serverMessageText(
        zhCN: '请输入密码',
        zhTW: '請輸入密碼',
        en: 'Please enter your password',
      );
    case '请输入旧密码':
      return _serverMessageText(
        zhCN: '请输入旧密码',
        zhTW: '請輸入舊密碼',
        en: 'Please enter your current password',
      );
    case '旧密码错误':
      return _serverMessageText(
        zhCN: '旧密码错误',
        zhTW: '舊密碼錯誤',
        en: 'Incorrect current password',
      );
    case '请输入6位数字密码':
      return _serverMessageText(
        zhCN: '请输入6位数字密码',
        zhTW: '請輸入 6 位數字密碼',
        en: 'Please enter a 6-digit numeric password',
      );
    case '请输入有效金额':
      return _serverMessageText(
        zhCN: '请输入有效金额',
        zhTW: '請輸入有效金額',
        en: 'Please enter a valid amount',
      );
    case '提现失败':
      return _serverMessageText(
        zhCN: '提现失败',
        zhTW: '提現失敗',
        en: 'Withdrawal failed',
      );
    case '充值失败':
      return _serverMessageText(
        zhCN: '充值失败',
        zhTW: '儲值失敗',
        en: 'Recharge failed',
      );
    case '领取失败':
      return _serverMessageText(
        zhCN: '领取失败',
        zhTW: '領取失敗',
        en: 'Claim failed',
      );
    case '接收失败':
      return _serverMessageText(
        zhCN: '接收失败',
        zhTW: '接收失敗',
        en: 'Accept failed',
      );
    case '退款失败':
      return _serverMessageText(
        zhCN: '退款失败',
        zhTW: '退款失敗',
        en: 'Refund failed',
      );
    case '转账失败':
      return _serverMessageText(
        zhCN: '转账失败',
        zhTW: '轉帳失敗',
        en: 'Transfer failed',
      );
    case '红包不存在':
      return _serverMessageText(
        zhCN: '红包不存在',
        zhTW: '紅包不存在',
        en: 'Red packet does not exist',
      );
    case '红包已过期':
      return _serverMessageText(
        zhCN: '红包已过期',
        zhTW: '紅包已過期',
        en: 'Red packet expired',
      );
    case '红包已被领完':
      return _serverMessageText(
        zhCN: '红包已被领完',
        zhTW: '紅包已被領完',
        en: 'The red packet has been fully claimed',
      );
    case '转账不存在':
      return _serverMessageText(
        zhCN: '转账不存在',
        zhTW: '轉帳不存在',
        en: 'Transfer does not exist',
      );
    case '转账已过期':
      return _serverMessageText(
        zhCN: '转账已过期',
        zhTW: '轉帳已過期',
        en: 'Transfer expired',
      );
    case '私聊会话不存在或不可用':
      return _serverMessageText(
        zhCN: '私聊会话不存在或不可用',
        zhTW: '私聊會話不存在或不可用',
        en: 'The private chat does not exist or is unavailable',
      );
    case '充值方式不存在':
      return _serverMessageText(
        zhCN: '充值方式不存在',
        zhTW: '儲值方式不存在',
        en: 'Recharge method does not exist',
      );
    case '提现方式不存在':
      return _serverMessageText(
        zhCN: '提现方式不存在',
        zhTW: '提現方式不存在',
        en: 'Withdrawal method does not exist',
      );
    case '会话不存在':
      return _serverMessageText(
        zhCN: '会话不存在',
        zhTW: '會話不存在',
        en: 'Conversation does not exist',
      );
    case '消息不存在':
      return _serverMessageText(
        zhCN: '消息不存在',
        zhTW: '訊息不存在',
        en: 'Message does not exist',
      );
  }

  if (message.startsWith('参数错误')) {
    return _serverMessageText(
      zhCN: message,
      zhTW: message.replaceFirst('参数错误', '參數錯誤'),
      en: 'Invalid request parameters',
    );
  }

  if (message.contains('登录态已失效')) {
    return _serverMessageText(
      zhCN: '登录态已失效，请重新登录',
      zhTW: '登入狀態已失效，請重新登入',
      en: 'Your session has expired. Please sign in again.',
    );
  }
  if (message.contains('密码已被修改')) {
    return _serverMessageText(
      zhCN: '密码已被修改，请重新登录',
      zhTW: '密碼已被修改，請重新登入',
      en: 'Your password was changed. Please sign in again.',
    );
  }
  if (message.contains('当前设备登录态已失效')) {
    return _serverMessageText(
      zhCN: '当前设备登录态已失效，请重新登录',
      zhTW: '目前裝置登入狀態已失效，請重新登入',
      en: 'This device session is no longer valid. Please sign in again.',
    );
  }
  if (message.contains('会话已更新')) {
    return _serverMessageText(
      zhCN: '会话已更新，请重新登录',
      zhTW: '會話已更新，請重新登入',
      en: 'The session has changed. Please sign in again.',
    );
  }
  if (message.contains('账号已被冻结')) {
    return _serverMessageText(
      zhCN: '您的账号已被冻结',
      zhTW: '您的帳號已被凍結',
      en: 'Your account has been frozen.',
    );
  }
  if (message.contains('Token无效或已过期')) {
    return _serverMessageText(
      zhCN: 'Token无效或已过期',
      zhTW: 'Token 無效或已過期',
      en: 'The token is invalid or expired',
    );
  }
  if (message.contains('短信发送失败')) {
    return _serverMessageText(
      zhCN: '短信发送失败，请稍后重试',
      zhTW: '簡訊發送失敗，請稍後重試',
      en: 'Failed to send the SMS. Please try again later.',
    );
  }
  if (message.contains('验证码错误')) {
    return _serverMessageText(
      zhCN: '验证码错误',
      zhTW: '驗證碼錯誤',
      en: 'Incorrect verification code',
    );
  }
  if (message.contains('二维码已过期')) {
    return _serverMessageText(
      zhCN: '二维码已过期',
      zhTW: 'QR 碼已過期',
      en: 'The QR code has expired',
    );
  }

  final vipGroupLimitMatch =
      RegExp(r'^当前会员最多可创建 (\d+) 个群聊$').firstMatch(message);
  if (vipGroupLimitMatch != null) {
    final limit = vipGroupLimitMatch.group(1) ?? '';
    return _serverMessageText(
      zhCN: message,
      zhTW: '目前會員最多可建立 $limit 個群聊',
      en: 'Your current VIP plan can create up to $limit groups',
    );
  }

  final vipChannelLimitMatch =
      RegExp(r'^当前会员最多可创建 (\d+) 个频道$').firstMatch(message);
  if (vipChannelLimitMatch != null) {
    final limit = vipChannelLimitMatch.group(1) ?? '';
    return _serverMessageText(
      zhCN: message,
      zhTW: '目前會員最多可建立 $limit 個頻道',
      en: 'Your current VIP plan can create up to $limit channels',
    );
  }

  if (message.contains('\u5df2\u7ecf\u662f\u8054\u7cfb\u4eba') ||
      message.contains('\u5df2\u662f\u8054\u7cfb\u4eba')) {
    return _serverMessageText(
      zhCN: '\u5df2\u7ecf\u662f\u8054\u7cfb\u4eba',
      zhTW: '\u5df2\u662f\u806f\u7d61\u4eba',
      en: 'This user is already in your contacts',
    );
  }
  if (message.contains(
      '\u4e0d\u80fd\u5c06\u81ea\u5df1\u6dfb\u52a0\u4e3a\u8054\u7cfb\u4eba')) {
    return _serverMessageText(
      zhCN:
          '\u4e0d\u80fd\u5c06\u81ea\u5df1\u6dfb\u52a0\u4e3a\u8054\u7cfb\u4eba',
      zhTW:
          '\u4e0d\u80fd\u5c07\u81ea\u5df1\u65b0\u589e\u70ba\u806f\u7d61\u4eba',
      en: 'You cannot add yourself as a contact',
    );
  }
  if (message.contains('\u6dfb\u52a0\u8054\u7cfb\u4eba\u5931\u8d25')) {
    return _serverMessageText(
      zhCN: '\u6dfb\u52a0\u8054\u7cfb\u4eba\u5931\u8d25',
      zhTW: '\u65b0\u589e\u806f\u7d61\u4eba\u5931\u6557',
      en: 'Failed to add contact',
    );
  }
  if (message.contains('\u83b7\u53d6\u8054\u7cfb\u4eba\u5931\u8d25')) {
    return _serverMessageText(
      zhCN: '\u83b7\u53d6\u8054\u7cfb\u4eba\u5931\u8d25',
      zhTW: '\u53d6\u5f97\u806f\u7d61\u4eba\u5931\u6557',
      en: 'Failed to load contacts',
    );
  }
  if (message.contains('\u8054\u7cfb\u4eba\u4e0d\u5b58\u5728')) {
    return _serverMessageText(
      zhCN: '\u8054\u7cfb\u4eba\u4e0d\u5b58\u5728',
      zhTW: '\u806f\u7d61\u4eba\u4e0d\u5b58\u5728',
      en: 'Contact does not exist',
    );
  }

  return null;
}
