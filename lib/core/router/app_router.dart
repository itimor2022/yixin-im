// 文件用途：集中定义应用路由、页面跳转规则、重定向和路由级鉴权。
// 核心逻辑：集中创建 GoRouter，依据登录态、设备锁和注册流程执行重定向，同时维护页面参数与导航栈一致性。
import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/pages/login_page.dart';
import '../../features/auth/pages/forgot_password_page.dart';
import '../../features/auth/pages/register_page.dart';
import '../../features/chat/pages/chat_page.dart';
import '../../features/chat/pages/chat_detail_page.dart';
import '../../features/chat/pages/channel_page.dart';
import '../../features/chat/pages/group_edit_page.dart';
import '../../features/chat/pages/user_profile_page.dart';
import '../../features/chat/pages/group_profile_page.dart';
import '../../features/chat/pages/channel_profile_page.dart';
import '../../features/chat/pages/qr_scanner_page.dart';
import '../../features/chat/pages/search_page.dart';
import '../../features/settings/pages/personalization_page.dart';
import '../../features/wallet/wallet.dart';
import '../../features/vip/vip.dart';
import '../../features/contacts/pages/contacts_page.dart';
import '../../features/discover/pages/discover_page.dart';
import '../../features/portal/pages/custom_portal_page.dart';
import '../../features/contacts/pages/new_contact_page.dart';
import '../../features/moments/pages/moments_page.dart';
import '../../features/settings/pages/settings_page.dart';
import '../../features/settings/pages/chat_settings_page.dart';
import '../../features/settings/pages/profile_page.dart';
import '../../features/settings/pages/bind_phone_page.dart';
import '../../features/home/pages/home_page.dart';
import '../../features/meeting/pages/meeting_page.dart';
import '../../features/splash/pages/splash_page.dart';
import '../../features/call/pages/call_page.dart';
import '../../shared/widgets/page_transitions.dart';
import '../i18n/app_localizations.dart';
import '../services/api/auth_service.dart';
import '../services/api/system_settings_service.dart';
import '../utils/platform_utils.dart';
import 'redirect_utils.dart';

String _routerText(
  BuildContext context, {
  required String zhCN,
  String? zhTW,
  required String en,
}) {
  switch (AppLocalizations.of(context).language) {
    case AppLanguage.en:
      return en;
    case AppLanguage.zhTW:
      return zhTW ?? zhCN;
    case AppLanguage.zhCN:
      return zhCN;
  }
}

/// 全局根导航器 Key - 用于在 GoRouter 之外导航（如来电页面）
final GlobalKey<NavigatorState> rootNavigatorKey =
    GlobalKey<NavigatorState>(debugLabel: 'root');

/// 路由器只监听会改变访问权限的认证和系统设置；页面业务状态不应触发整棵路由树重建。
final appRouterProvider = Provider<GoRouter>((ref) {
  // 创建 refresh notifier
  final refreshNotifier =
      GoRouterRefreshStream(ref.read(authServiceProvider.notifier).stream);
  ref.listen(systemSettingsProvider, (_, __) {
    refreshNotifier.refresh();
  });

  return GoRouter(
    // 使用根导航器 Key
    navigatorKey: rootNavigatorKey,
    // Web needs the browser URL as the initial location for deep links.
    initialLocation: kIsWeb ? null : '/',
    debugLogDiagnostics: false,

    // 路由重定向 - 检查认证状态
    // 注意：使用 ref.read 而不是 ref.watch，避免整个路由器重建
    redirect: (context, state) {
      // 重定向按启动占位、认证恢复、账号约束、平台合规的顺序收敛，前面的状态拥有更高优先级。
      // 在 redirect 回调内读取最新状态
      final authState = ref.read(authServiceProvider);
      final isLoggedIn = authState.status == AuthStatus.authenticated;
      final isOnSplash = state.matchedLocation == '/';
      final isOnAuth = state.matchedLocation == '/login' ||
          state.matchedLocation == '/register' ||
          state.matchedLocation == '/forgot-password';
      final isOnBindPhone = state.matchedLocation == '/bind-phone';
      final isInitializing = authState.status == AuthStatus.initial;
      final isLoading = authState.status == AuthStatus.loading;

      // Keep splash in charge of its own timing. If redirect moves away from
      // "/" as soon as auth resolves, the configured splash duration is skipped.
      if (isOnSplash) return null;

      // 初始化中（仅 initial 状态），停留在启动页
      if (isInitializing) {
        return splashLocationWithRedirect(state.uri);
      }

      // loading 状态时：如果已在启动页/登录页则保持；否则重定向到启动页
      // 防止深链接直接打开受保护路由时，loading 期间短暂停留在该页面
      if (isLoading) {
        if (isOnSplash || isOnAuth) return null;
        return splashLocationWithRedirect(state.uri);
      }

      // 已登录
      if (isLoggedIn) {
        final settings = ref.read(systemSettingsServiceProvider).cachedSettings;
        final requirePhoneBind = !kIsWeb && settings?.requirePhoneBind == true;
        final hasPhone = (authState.user?.phone ?? '').trim().isNotEmpty;
        if (requirePhoneBind && !hasPhone) {
          if (isOnBindPhone) return null;
          return '/bind-phone';
        }
        if (isOnBindPhone) return '/home';

        if (PlatformUtils.isIOS && settings != null) {
          final compliance = settings.iosCompliance;
          final path = state.matchedLocation;
          if (path.startsWith('/vip') && !compliance.allowsVIP) {
            return '/settings';
          }
          if (path.startsWith('/wallet/recharge') &&
              !compliance.allowsWalletRecharge) {
            return compliance.allowsWallet ? '/wallet' : '/settings';
          }
          if (path.startsWith('/wallet') && !compliance.allowsWallet) {
            return '/settings';
          }
          if (path.startsWith('/portal') && !compliance.allowsCustomPortal) {
            return '/home';
          }
        }

        // 在启动页或登录页，跳转到目标页或首页
        if (isOnAuth) {
          return safeInAppRedirect(state.uri.queryParameters['redirect']) ??
              '/home';
        }
        return null;
      }

      // 未登录
      // 在启动页，跳转到登录页
      if (isOnSplash) return '/login';
      // 在登录/注册页，保持不变
      if (isOnAuth) return null;
      // 其他页面，跳转到登录，并保留站内目标地址供登录后回跳。
      return loginLocationWithRedirect(state.uri);
    },

    // 刷新监听 - 当认证状态变化时触发 redirect 重新评估
    refreshListenable: refreshNotifier,

    routes: [
      // 启动页
      GoRoute(
        path: '/',
        name: 'splash',
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const SplashPage(),
          transitionsBuilder: fadeTransition,
        ),
      ),

      // 聊天详情页 - 独立页面，不显示底部导航
      GoRoute(
        path: '/chat/:chatId',
        name: 'chatDetail',
        pageBuilder: (context, state) {
          final chatId = state.pathParameters['chatId']!;
          final chatName = state.uri.queryParameters['name'] ?? '';
          final avatar = state.uri.queryParameters['avatar'];
          final typeStr = state.uri.queryParameters['type'] ?? 'private';
          final messageId = state.uri.queryParameters['messageId'];
          final messageSeq =
              int.tryParse(state.uri.queryParameters['messageSeq'] ?? '');
          final action =
              state.uri.queryParameters['action']; // 'call' 或 'video'
          final chatType = ChatType.values.firstWhere(
            (t) => t.name == typeStr,
            orElse: () => ChatType.private,
          );
          final container = ProviderScope.containerOf(context);
          final uid = container.read(authServiceProvider).user?.uuid ?? '';
          return IOSPage(
            key: state.pageKey,
            child: ChatDetailPage(
              key: ValueKey('chatDetail_${chatId}_$uid'),
              chatId: chatId,
              chatName: chatName,
              avatar: avatar,
              chatType: chatType,
              action: action,
              initialMessageId: messageId,
              initialMessageSeq: messageSeq,
            ),
          );
        },
      ),

      // 频道页面（公告/只读）
      GoRoute(
        path: '/channel/:channelId',
        name: 'channel',
        pageBuilder: (context, state) {
          final channelId = state.pathParameters['channelId']!;
          final channelName = state.uri.queryParameters['name'] ?? '';
          final avatar = state.uri.queryParameters['avatar'];
          final container = ProviderScope.containerOf(context);
          final uid = container.read(authServiceProvider).user?.uuid ?? '';
          return IOSPage(
            key: state.pageKey,
            child: ChannelPage(
              key: ValueKey('channel_${channelId}_$uid'),
              channelId: channelId,
              channelName: channelName,
              avatar: avatar,
            ),
          );
        },
      ),

      // 搜索页面
      GoRoute(
        path: '/search',
        name: 'search',
        pageBuilder: (context, state) {
          final query = state.uri.queryParameters['query'];
          return IOSPage(
            key: state.pageKey,
            child: SearchPage(initialQuery: query),
          );
        },
      ),

      // 群组/频道编辑页
      GoRoute(
        path: '/group/edit/:chatId',
        name: 'groupEdit',
        pageBuilder: (context, state) {
          final chatId = state.pathParameters['chatId']!;
          return IOSPage(
            key: state.pageKey,
            child: GroupEditPage(chatId: chatId),
          );
        },
      ),

      // 用户资料页
      GoRoute(
        path: '/user/:userId',
        name: 'userProfile',
        pageBuilder: (context, state) {
          final userId = state.pathParameters['userId']!;
          final name = state.uri.queryParameters['name'];
          final avatar = state.uri.queryParameters['avatar'];
          final chatId = state.uri.queryParameters['chat_id'];
          return IOSPage(
            key: state.pageKey,
            child: UserProfilePage(
              userId: userId,
              name: name,
              avatar: avatar,
              chatId: chatId,
            ),
          );
        },
      ),

      // 群组资料页
      GoRoute(
        path: '/group/:groupId/profile',
        name: 'groupProfile',
        pageBuilder: (context, state) {
          final groupId = state.pathParameters['groupId']!;
          final name = state.uri.queryParameters['name'];
          final avatar = state.uri.queryParameters['avatar'];
          return IOSPage(
            key: state.pageKey,
            child: GroupProfilePage(
              groupId: groupId,
              name: name,
              avatar: avatar,
            ),
          );
        },
      ),

      // 频道资料页
      GoRoute(
        path: '/channel/:channelId/profile',
        name: 'channelProfile',
        pageBuilder: (context, state) {
          final channelId = state.pathParameters['channelId']!;
          final name = state.uri.queryParameters['name'];
          final avatar = state.uri.queryParameters['avatar'];
          return IOSPage(
            key: state.pageKey,
            child: ChannelProfilePage(
              channelId: channelId,
              name: name,
              avatar: avatar,
            ),
          );
        },
      ),

      // 二维码扫描
      GoRoute(
        path: '/scan',
        name: 'qrScanner',
        pageBuilder: (context, state) => IOSPage(
          key: state.pageKey,
          child: const QRScannerPage(),
        ),
      ),

      // 搜索用户页面（全局可访问，不依赖 shell 路由）
      GoRoute(
        path: '/search-users',
        name: 'searchUsers',
        pageBuilder: (context, state) {
          final query = state.uri.queryParameters['query'];
          return IOSModalPage(
            key: state.pageKey,
            child: NewContactPage(initialQuery: query),
          );
        },
      ),

      // 通话页面 - iOS 风格从底部滑入动画
      GoRoute(
        path: '/call',
        name: 'call',
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const CallPage(),
          opaque: true,
          transitionDuration: const Duration(milliseconds: 350),
          reverseTransitionDuration: const Duration(milliseconds: 300),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            // 使用曲线动画，更流畅
            final curvedAnimation = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
              reverseCurve: Curves.easeInCubic,
            );

            // 从底部滑入 + 淡入组合效果
            return SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.15), // 只从底部偏移 15%，更微妙
                end: Offset.zero,
              ).animate(curvedAnimation),
              child: FadeTransition(
                opacity: Tween<double>(begin: 0.0, end: 1.0)
                    .animate(curvedAnimation),
                child: child,
              ),
            );
          },
        ),
      ),

      // 群会议页面
      GoRoute(
        path: '/meeting/:meetingId',
        name: 'meeting',
        pageBuilder: (context, state) {
          final meetingId = state.pathParameters['meetingId']!;
          final chatId = state.uri.queryParameters['chat_id'];
          final chatName = state.uri.queryParameters['name'];
          return IOSPage(
            key: state.pageKey,
            child: MeetingPage(
              meetingId: meetingId,
              chatId: chatId,
              chatName: chatName,
            ),
          );
        },
      ),

      // 主页 - 带底部导航
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return HomePage(navigationShell: navigationShell);
        },
        branches: [
          // 聊天列表
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/home',
                name: 'chats',
                pageBuilder: (context, state) => CustomTransitionPage(
                  key: state.pageKey,
                  child: const ChatPage(),
                  transitionsBuilder: noTransition, // Tab 页面使用无过渡，更流畅
                ),
              ),
            ],
          ),

          // 联系人
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/contacts',
                name: 'contacts',
                pageBuilder: (context, state) => CustomTransitionPage(
                  key: state.pageKey,
                  child: const ContactsPage(),
                  transitionsBuilder: noTransition, // Tab 页面使用无过渡，更流畅
                ),
                routes: [
                  GoRoute(
                    path: 'new',
                    name: 'newContact',
                    pageBuilder: (context, state) => IOSModalPage(
                      key: state.pageKey,
                      child: const NewContactPage(),
                    ),
                  ),
                ],
              ),
            ],
          ),

          // 自定义网站栏目
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/portal',
                name: 'portal',
                pageBuilder: (context, state) => CustomTransitionPage(
                  key: state.pageKey,
                  child: const CustomPortalPage(),
                  transitionsBuilder: noTransition,
                ),
              ),
            ],
          ),

          // 发现
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/discover',
                name: 'discover',
                pageBuilder: (context, state) => CustomTransitionPage(
                  key: state.pageKey,
                  child: const DiscoverPage(),
                  transitionsBuilder: noTransition,
                ),
                routes: [
                  GoRoute(
                    path: 'square',
                    name: 'discoverSquare',
                    pageBuilder: (context, state) => IOSPage(
                      key: state.pageKey,
                      child: const MomentsPage(
                        isSecondaryPage: true,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),

          // 设置
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/settings',
                name: 'settings',
                pageBuilder: (context, state) => CustomTransitionPage(
                  key: state.pageKey,
                  child: const SettingsPage(),
                  transitionsBuilder: noTransition, // Tab 页面使用无过渡，更流畅
                ),
                routes: [
                  GoRoute(
                    path: 'profile',
                    name: 'profile',
                    pageBuilder: (context, state) => IOSPage(
                      key: state.pageKey,
                      child: const ProfilePage(),
                    ),
                  ),
                  GoRoute(
                    path: 'chat-settings',
                    name: 'chatSettings',
                    pageBuilder: (context, state) => IOSPage(
                      key: state.pageKey,
                      child: const ChatSettingsPage(),
                    ),
                  ),
                  GoRoute(
                    path: 'personalization',
                    name: 'personalization',
                    pageBuilder: (context, state) => IOSPage(
                      key: state.pageKey,
                      child: const PersonalizationPage(),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),

      GoRoute(
        path: '/wallet',
        name: 'wallet',
        pageBuilder: (context, state) => IOSPage(
          key: state.pageKey,
          child: const WalletPage(),
        ),
        routes: [
          GoRoute(
            path: 'recharge',
            name: 'recharge',
            pageBuilder: (context, state) => IOSPage(
              key: state.pageKey,
              child: const RechargePage(),
            ),
          ),
          GoRoute(
            path: 'payment-result',
            name: 'paymentResult',
            pageBuilder: (context, state) => IOSPage(
              key: state.pageKey,
              child: const PaymentResultPage(),
            ),
          ),
          GoRoute(
            path: 'withdraw',
            name: 'withdraw',
            pageBuilder: (context, state) => IOSPage(
              key: state.pageKey,
              child: const WithdrawPage(),
            ),
          ),
          GoRoute(
            path: 'transactions',
            name: 'transactions',
            pageBuilder: (context, state) => IOSPage(
              key: state.pageKey,
              child: const TransactionListPage(),
            ),
          ),
          GoRoute(
            path: 'set-password',
            name: 'setPayPassword',
            pageBuilder: (context, state) {
              final isUpdate = state.uri.queryParameters['update'] == 'true';
              return IOSPage(
                key: state.pageKey,
                child: SetPayPasswordPage(isUpdate: isUpdate),
              );
            },
          ),
        ],
      ),

      GoRoute(
        path: '/vip',
        name: 'vip',
        pageBuilder: (context, state) => IOSPage(
          key: state.pageKey,
          child: const VipCenterPage(),
        ),
        routes: [
          GoRoute(
            path: 'orders',
            name: 'vipOrders',
            pageBuilder: (context, state) => IOSPage(
              key: state.pageKey,
              child: const VipOrdersPage(),
            ),
          ),
        ],
      ),

      // 登录
      GoRoute(
        path: '/login',
        name: 'login',
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const LoginPage(),
          transitionsBuilder: fadeTransition,
        ),
      ),

      GoRoute(
        path: '/forgot-password',
        name: 'forgotPassword',
        pageBuilder: (context, state) => IOSPage(
          key: state.pageKey,
          child: const ForgotPasswordPage(),
        ),
      ),

      // 注册
      GoRoute(
        path: '/bind-phone',
        name: 'bindPhone',
        pageBuilder: (context, state) => IOSPage(
          key: state.pageKey,
          child: const BindPhonePage(),
        ),
      ),

      GoRoute(
        path: '/register',
        name: 'register',
        pageBuilder: (context, state) => IOSPage(
          key: state.pageKey,
          child: const RegisterPage(),
        ),
      ),
    ],

    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Text(
          '${_routerText(
            context,
            zhCN: '页面不存在',
            zhTW: '頁面不存在',
            en: 'Page not found',
          )}: ${state.uri}',
        ),
      ),
    ),
  );
});

// 关键声明：app router 维护导航状态与访问控制，重定向只读取权限相关状态，避免业务刷新触发整棵路由树重建。
/// GoRouter 刷新流监听器
class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Stream<dynamic> stream) {
    notifyListeners();
    _subscription = stream.asBroadcastStream().listen((_) => notifyListeners());
  }

  late final StreamSubscription<dynamic> _subscription;

  void refresh() => notifyListeners();

  // 流程逻辑：`dispose` 先阻止新的输入或回调，再按创建顺序的逆序取消订阅、定时器和临时资源，保证清理可重复执行。
  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
