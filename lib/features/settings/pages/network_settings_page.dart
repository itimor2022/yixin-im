import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/server_discovery.dart';
import '../../../core/services/api/api_client.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';

// ── 节点状态 ────────────────────────────────────────────
enum NodeStatus { idle, testing, ok, failed }

class NodeInfo {
  final String url;
  NodeStatus status;
  int? latencyMs;
  bool isSelected;

  NodeInfo({
    required this.url,
    this.status = NodeStatus.idle,
    this.latencyMs,
    this.isSelected = false,
  });

  NodeInfo copyWith({
    NodeStatus? status,
    int? latencyMs,
    bool? isSelected,
  }) =>
      NodeInfo(
        url: url,
        status: status ?? this.status,
        latencyMs: latencyMs ?? this.latencyMs,
        isSelected: isSelected ?? this.isSelected,
      );
}

// ── Provider ────────────────────────────────────────────
class NetworkSettingsNotifier extends StateNotifier<List<NodeInfo>> {
  NetworkSettingsNotifier() : super([]) {
    _init();
  }

  static const _pingPath = '/api/v1/ping';
  static const _pingTimeout = Duration(seconds: 8);

 void _init() {
    if (!mounted) return;
    String normalize(String u) => u.trim().replaceAll(RegExp(r'/+$'), '');
    final current = normalize(ApiConfig.serverUrl);

    final all = ServerDiscovery.instance.allKnownNodes;

    // ⚠️ 不要在这里自动 rediscover。以前的写法是：
    //   if (all.length <= 1) { Future(rediscover); }
    // 它会形成死循环：
    //   _init → rediscover → ServerDiscovery.forceRefresh → _discover
    //   → 所有节点 ping 不通时 _lastCandidates 被收窄成 1 条
    //   → rediscover 再次调用 _init → 又只看到 1 条 → 又 Future(rediscover) …
    // 而且 Future(rediscover) 是 fire-and-forget，加上 ServerDiscovery 是全局单例，
    // 用户离开测速页后队列里的 forceRefresh 仍在跑，表现为「一直 ping、停不下来」。

    // 但是「首次进入只显示 1 条」这个用户可见的坑仍然需要处理：
    // 它是 initialize() 缓存命中时 _lastCandidates 没被填充导致的。
    // 修复：这里只在候选池 <= 1 条时，触发 refreshCandidatesOnly（只拉列表、
    // 不重跑 _discover），拉完在同一个方法里重新 setState，不再递归 rediscover。
    if (all.length <= 1) {
      unawaited(_hydrateCandidates());
    }

    // ⚠️ 保留 api.txt 的原始顺序（域名在前、IP 在后 或反过来），
    // 之前 .sort((a, b) => a.compareTo(b)) 会按字典序把顺序搅乱。
    state = all
        .map((url) => NodeInfo(
              url: url,
              isSelected: normalize(url) == current,
            ))
        .toList();

    testAll();
  }

  /// 后台补齐候选节点（用于"首次进入只有 1 条"的场景）。
  /// 只更新候选池，不改变用户当前正在使用的节点，也不递归调用 rediscover，
  /// 避免曾经出现过的"离开页面还在 ping"的死循环。
  Future<void> _hydrateCandidates() async {
    try {
      // ★ 确保 ServerDiscovery 已完成初始化
      if (ServerDiscovery.instance.currentNode == null) {
        await ServerDiscovery.instance.initialize().timeout(
          const Duration(seconds: 8),
          onTimeout: () => '',
        );
      } else {
        await ServerDiscovery.instance.refreshCandidatesOnly();
      }
    } catch (_) {}
    if (!mounted) return;

    String normalize(String u) => u.trim().replaceAll(RegExp(r'/+$'), '');
    final current = normalize(ApiConfig.serverUrl);
    final all = ServerDiscovery.instance.allKnownNodes;

    // 保留已经测好速的节点结果，只把新拉到的节点补进去
    final existing = <String, NodeInfo>{
      for (final n in state) n.url: n,
    };
    state = all.map((url) {
      final prev = existing[url];
      if (prev != null) {
        return prev.copyWith(isSelected: normalize(url) == current);
      }
      return NodeInfo(url: url, isSelected: normalize(url) == current);
    }).toList();

    // 只测那些还没结果的新节点，避免整表重测打断用户
    final untested = state
        .where((n) => n.status == NodeStatus.idle)
        .map((n) => n.url)
        .toList();
    for (final url in untested) {
      unawaited(_testNode(url));
    }
  }

  Future<void> rediscover() async {
    if (!mounted) return;
    // ⭐ 关键变更：改用 refreshCandidatesOnly，而不是 forceRefresh。
    //   forceRefresh 会重跑 _discover 并把 _currentNode 换成"最快节点"，
    //   用户手动切到 IP 之后一点重新发现就被自动换回域名 —— 这就是用户报的
    //   "切换了 ip, 默认还是域名线路" bug。
    //   现在这个按钮只做"重新拉 api.txt + 重测所有节点"，不动当前节点。
    try {
      await ServerDiscovery.instance.refreshCandidatesOnly();
    } catch (_) {}
    if (!mounted) return;
    _init();
  }

  Future<void> testAll() async {
    if (!mounted) return;
    state = state
        .map((n) => NodeInfo(
              url: n.url,
              status: NodeStatus.testing,
              latencyMs: null,
              isSelected: n.isSelected,
            ))
        .toList();

    await Future.wait(state.map((n) => _testNode(n.url)));
  }

  Future<void> testOne(String url) async {
    _updateNode(url, status: NodeStatus.testing, latencyMs: null);
    await _testNode(url);
  }

  Future<void> _testNode(String url) async {
    final stopwatch = Stopwatch()..start();
    try {
      final dio = Dio(BaseOptions(
        connectTimeout: _pingTimeout,
        receiveTimeout: _pingTimeout,
      ));

      // ★ 修复 Web 上"所有线路都不可用"的问题：
      //   `IOHttpClientAdapter` 来自 dart:io，Flutter Web 里默认适配器是
      //   `BrowserHttpClientAdapter`，直接强转会在运行期抛 `TypeError`
      //   进而被下面的 `catch (_)` 吞掉、然后一律标记 failed。
      //   Web 端的 HTTPS 证书校验完全由浏览器沙箱负责，也不允许业务代码去
      //   忽略证书——所以只在 Android / iOS / 桌面上保留 badCertificateCallback。
      //   这跟 [server_discovery.dart] 里同样位置的写法保持一致。
      if (!kIsWeb) {
        (dio.httpClientAdapter as IOHttpClientAdapter).onHttpClientCreate =
            (client) {
          client.badCertificateCallback = (cert, host, port) => true;
          return client;
        };
      }
      final resp = await dio.get<dynamic>(
        '$url$_pingPath',
        options: Options(validateStatus: (s) => s == 200),
      );
      stopwatch.stop();
      if ((resp.statusCode ?? 0) == 200) {
        _updateNode(url,
            status: NodeStatus.ok, latencyMs: stopwatch.elapsedMilliseconds);
      } else {
        _updateNode(url, status: NodeStatus.failed);
      }
    } catch (_) {
      stopwatch.stop();
      _updateNode(url, status: NodeStatus.failed);
    }
  }

  /// 用户手动切换节点。返回 `Future<void>` 是为了 UI 层想 await 可以 await，
  /// 但不 await 也没关系（内部 state 已经在同步阶段更新完了）。
  ///
  /// ⚠️ 一定要 await 缓存写入：
  ///   老实现是 `ServerDiscovery.instance.clearCacheAndSet(url);` 一发就走，
  ///   如果用户点完立刻杀 App / 系统内存不足回收进程，SharedPreferences 的
  ///   `setString` 可能还没落盘，下次冷启动 initialize() 读到的还是旧节点，
  ///   表现为"我明明选了 IP，重启又跳回域名"。
  Future<void> selectNode(String url) async {
    ApiConfig.updateServer(url);

    String normalize(String u) => u.trim().replaceAll(RegExp(r'/+$'), '');
    final target = normalize(url);

    state = state
        .map((n) => NodeInfo(
              url: n.url,
              status: n.status,
              latencyMs: n.latencyMs,
              isSelected: normalize(n.url) == target,
            ))
        .toList();

    // 落盘放在 state 更新之后，避免 await 期间 UI 卡一帧才高亮。
    await ServerDiscovery.instance.clearCacheAndSet(url);
  }

  void _updateNode(String url, {NodeStatus? status, int? latencyMs}) {
    // 页面已经 dispose（比如用户测速中途返回）就不要再动 state，
    // 否则 StateNotifier 会抛 setState-after-dispose。
    if (!mounted) return;
    state = state.map((n) {
      if (n.url != url) return n;
      return NodeInfo(
        url: n.url,
        status: status ?? n.status,
        latencyMs: latencyMs ?? n.latencyMs,
        isSelected: n.isSelected,
      );
    }).toList();
  }
}

final networkSettingsProvider =
    StateNotifierProvider.autoDispose<NetworkSettingsNotifier, List<NodeInfo>>(
  (ref) => NetworkSettingsNotifier(),
);

// ── 视觉 Token（对齐"我的"页风格）─────────────────────────
const Color _kPrimary = Color(0xFFFF6B6B);
const Color _kBg = Color(0xFFF7F8FA);
const Color _kCardBg = Colors.white;
const Color _kTitleText = Color(0xFF111827);
const Color _kSubText = Color(0xFF6B7280);
const Color _kMuted = Color(0xFF9CA3AF);
const Color _kDivider = Color(0xFFEDEFF2);

// ── 页面 ────────────────────────────────────────────────
class NetworkSettingsPage extends ConsumerWidget {
  const NetworkSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final nodes = ref.watch(networkSettingsProvider);
    final notifier = ref.read(networkSettingsProvider.notifier);

    final Color bg = isDark ? const Color(0xFF0E1015) : _kBg;
    final Color cardBg = isDark ? const Color(0xFF161821) : _kCardBg;
    final Color titleColor = isDark ? Colors.white : _kTitleText;
    final Color subColor = isDark ? Colors.white54 : _kSubText;
    final Color dividerColor =
        isDark ? Colors.white.withOpacity(0.06) : _kDivider;

    // 当前选中节点摘要（用于顶部卡片）
    NodeInfo? selectedNode;
    for (final n in nodes) {
      if (n.isSelected) {
        selectedNode = n;
        break;
      }
    }
    final okCount = nodes.where((n) => n.status == NodeStatus.ok).length;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: Text(
          '网络线路',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: titleColor,
          ),
        ),
        iconTheme: IconThemeData(color: titleColor),
      ),
      body: nodes.isEmpty
          ? _buildEmptyState(cardBg, titleColor, subColor)
          : RefreshIndicator(
              color: _kPrimary,
              onRefresh: () async {
                HapticFeedback.lightImpact();
                await notifier.testAll();
              },
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(bottom: 32),
                children: [
                  const SizedBox(height: 8),

                  // ── 当前线路概览卡（顶部主视觉，内含"重新测速"与"重新发现"两个按钮）
                  _CurrentRouteHero(
                    node: selectedNode,
                    okCount: okCount,
                    totalCount: nodes.length,
                    onRetest: () {
                      HapticFeedback.lightImpact();
                      notifier.testAll();
                    },
                    onRediscover: () async {
                      HapticFeedback.lightImpact();
                      await notifier.rediscover();
                    },
                    isDark: isDark,
                  ),

                  const SizedBox(height: 16),

                  // ── 线路列表卡
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Container(
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        children: List.generate(nodes.length * 2 - 1, (index) {
                          if (index.isOdd) {
                            return _RouteDivider(color: dividerColor);
                          }
                          final i = index ~/ 2;
                          return _RouteTile(
                            index: i + 1,
                            node: nodes[i],
                            isDark: isDark,
                            onTap: () {
                              HapticFeedback.selectionClick();
                              unawaited(notifier.selectNode(nodes[i].url));
                            },
                            onRetest: () {
                              HapticFeedback.lightImpact();
                              notifier.testOne(nodes[i].url);
                            },
                          );
                        }),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildEmptyState(Color cardBg, Color titleColor, Color subColor) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 32,
            height: 32,
            child: CircularProgressIndicator(strokeWidth: 2.5, color: _kPrimary),
          ),
          const SizedBox(height: 14),
          Text(
            '正在探测网络线路…',
            style: TextStyle(fontSize: 14, color: subColor),
          ),
        ],
      ),
    );
  }
}

// ── 顶部主视觉卡：当前线路 + 概览 + 操作按钮 ─────────────────
class _CurrentRouteHero extends StatelessWidget {
  final NodeInfo? node;
  final int okCount;
  final int totalCount;
  final VoidCallback onRetest;
  final Future<void> Function() onRediscover;
  final bool isDark;

  const _CurrentRouteHero({
    required this.node,
    required this.okCount,
    required this.totalCount,
    required this.onRetest,
    required this.onRediscover,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final ms = node?.latencyMs;
    final status = node?.status ?? NodeStatus.idle;

    String stateLabel;
    Color stateColor;
    if (status == NodeStatus.testing) {
      stateLabel = '测速中';
      stateColor = _kMuted;
    } else if (status == NodeStatus.failed) {
      stateLabel = '不可用';
      stateColor = const Color(0xFFEF4444);
    } else if (ms != null && ms < 100) {
      stateLabel = '流畅';
      stateColor = const Color(0xFF22C55E);
    } else if (ms != null && ms < 300) {
      stateLabel = '良好';
      stateColor = const Color(0xFFF59E0B);
    } else if (ms != null) {
      stateLabel = '较慢';
      stateColor = const Color(0xFFEF4444);
    } else {
      stateLabel = '待测速';
      stateColor = _kMuted;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFFFF6B6B),
              Color(0xFFFF9E9E),
              Color(0xFF7CD5FF),
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: _kPrimary.withOpacity(0.22),
              blurRadius: 22,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── 顶部：图标 + 标签 + 状态胶囊
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.22),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.35),
                        width: 1,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.dns_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      '当前线路',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                  _HeroPill(
                    label: stateLabel,
                    background: Colors.white.withOpacity(0.22),
                    labelColor: Colors.white,
                    dotColor: stateColor,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              // ── 大号延迟数字
              RichText(
                text: TextSpan(
                  style: const TextStyle(color: Colors.white),
                  children: [
                    TextSpan(
                      text: ms != null ? '$ms' : '—',
                      style: const TextStyle(
                        fontSize: 40,
                        fontWeight: FontWeight.w700,
                        height: 1.0,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const TextSpan(
                      text: ' ms',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        height: 1.0,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '$okCount / $totalCount 条线路可用',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.85),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 14),
              // ── 操作按钮：重新测速 + 重新发现（左右并排）
              Row(
                children: [
                  Expanded(
                    child: _HeroActionButton(
                      icon: Icons.refresh_rounded,
                      label: '重新测速',
                      onTap: onRetest,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _HeroActionButton(
                      icon: Icons.travel_explore_rounded,
                      label: '重新发现',
                      onTap: () => onRediscover(),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Hero 卡内的白色半透明按钮
class _HeroActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _HeroActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withOpacity(0.22),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white, size: 16),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeroPill extends StatelessWidget {
  final String label;
  final Color background;
  final Color labelColor;
  final Color dotColor;

  const _HeroPill({
    required this.label,
    required this.background,
    required this.labelColor,
    required this.dotColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: dotColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: labelColor,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ── 线路行 ───────────────────────────────────────────────
class _RouteTile extends StatelessWidget {
  final int index;
  final NodeInfo node;
  final bool isDark;
  final VoidCallback onTap;
  final VoidCallback onRetest;

  const _RouteTile({
    required this.index,
    required this.node,
    required this.isDark,
    required this.onTap,
    required this.onRetest,
  });

  @override
  Widget build(BuildContext context) {
    final Color titleColor = isDark ? Colors.white : _kTitleText;

    final displayName = '线路 $index';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Row(
            children: [
              // ── 左侧：状态色圆点 + 序号
              _RouteLeading(
                index: index,
                node: node,
                isDark: isDark,
              ),
              const SizedBox(width: 14),

              // ── 中间：仅显示线路名（去掉具体地址）
              Expanded(
                child: Text(
                  displayName,
                  style: TextStyle(
                    fontSize: 15.5,
                    fontWeight: node.isSelected
                        ? FontWeight.w700
                        : FontWeight.w500,
                    color: titleColor,
                    height: 1.2,
                  ),
                ),
              ),

              const SizedBox(width: 8),

              // ── 右侧：延迟徽章 + 重测按钮 + 选中标识
              _LatencyBadge(node: node),
              const SizedBox(width: 4),
              _CircleIconButton(
                icon: Icons.refresh_rounded,
                onTap: onRetest,
                isDark: isDark,
              ),
              const SizedBox(width: 4),
              _SelectedIndicator(selected: node.isSelected),
            ],
          ),
        ),
      ),
    );
  }

}

class _RouteLeading extends StatelessWidget {
  final int index;
  final NodeInfo node;
  final bool isDark;

  const _RouteLeading({
    required this.index,
    required this.node,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final Color ringColor = _statusColor(node);
    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: ringColor.withOpacity(0.12),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(
            '$index',
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: ringColor,
            ),
          ),
        ),
        // 右下角小圆点显示状态
        Positioned(
          right: -1,
          bottom: -1,
          child: Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: ringColor,
              shape: BoxShape.circle,
              border: Border.all(
                color: isDark ? const Color(0xFF161821) : _kCardBg,
                width: 1.5,
              ),
            ),
          ),
        ),
      ],
    );
  }

  static Color _statusColor(NodeInfo node) {
    switch (node.status) {
      case NodeStatus.idle:
        return _kMuted;
      case NodeStatus.testing:
        return _kPrimary;
      case NodeStatus.failed:
        return const Color(0xFFEF4444);
      case NodeStatus.ok:
        final ms = node.latencyMs ?? 0;
        if (ms < 100) return const Color(0xFF22C55E);
        if (ms < 300) return const Color(0xFFF59E0B);
        return const Color(0xFFEF4444);
    }
  }
}

class _SelectedIndicator extends StatelessWidget {
  final bool selected;
  const _SelectedIndicator({required this.selected});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: selected ? _kPrimary : Colors.transparent,
        border: Border.all(
          color: selected ? _kPrimary : const Color(0xFFCBD1D9),
          width: 1.5,
        ),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: selected
          ? const Icon(Icons.check_rounded, size: 14, color: Colors.white)
          : null,
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool isDark;

  const _CircleIconButton({
    required this.icon,
    required this.onTap,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 32,
          height: 32,
          child: Icon(
            icon,
            size: 18,
            color: isDark ? Colors.white38 : _kMuted,
          ),
        ),
      ),
    );
  }
}

class _RouteDivider extends StatelessWidget {
  final Color color;
  const _RouteDivider({required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 66, right: 16),
      child: Divider(height: 1, thickness: 0.6, color: color),
    );
  }
}

class _LatencyBadge extends StatelessWidget {
  final NodeInfo node;
  const _LatencyBadge({required this.node});

  @override
  Widget build(BuildContext context) {
    switch (node.status) {
      case NodeStatus.idle:
        return const SizedBox(width: 62);
      case NodeStatus.testing:
        return const SizedBox(
          width: 62,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: _kMuted,
                ),
              ),
              SizedBox(width: 6),
              Text(
                '测速中',
                style: TextStyle(fontSize: 11, color: _kMuted),
              ),
            ],
          ),
        );
      case NodeStatus.failed:
        return _pillWidget(
          text: '不可用',
          color: const Color(0xFFEF4444),
        );
      case NodeStatus.ok:
        final ms = node.latencyMs ?? 0;
        final Color c = ms < 100
            ? const Color(0xFF22C55E)
            : ms < 300
                ? const Color(0xFFF59E0B)
                : const Color(0xFFEF4444);
        return _pillWidget(text: '${ms}ms', color: c);
    }
  }

  static Widget _pillWidget({required String text, required Color color}) {
    return Container(
      width: 62,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: color,
          height: 1.1,
        ),
      ),
    );
  }
}


