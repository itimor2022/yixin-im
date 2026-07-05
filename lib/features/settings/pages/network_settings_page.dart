import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/server_discovery.dart';
import '../../../core/services/api/api_client.dart';
import '../../../core/theme/app_colors.dart';
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
    String normalize(String u) => u.trim().replaceAll(RegExp(r'/+$'), '');
    final current = normalize(ApiConfig.serverUrl ?? ''); 
    
    final all = ServerDiscovery.instance.allKnownNodes;
    
    if (all.length <= 1) {
      Future(rediscover); 
    }
    
    final sortedList = all.toList()..sort((a, b) => a.compareTo(b)); 
    
    state = sortedList
        .map((url) => NodeInfo(
              url: url,
              isSelected: normalize(url) == current, 
            ))
        .toList();
        
    testAll();
  }

  Future<void> rediscover() async {
    state = [];
    try {
      await ServerDiscovery.instance.forceRefresh();
    } catch (_) {}
    _init();
  }

  Future<void> testAll() async {
    // 全部重置为测试中
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
      (dio.httpClientAdapter as IOHttpClientAdapter).onHttpClientCreate =
          (client) {
        client.badCertificateCallback = (cert, host, port) => true;
        return client;
      };
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

  void selectNode(String url) {
    ApiConfig.updateServer(url);
    ServerDiscovery.instance.clearCacheAndSet(url);
    
    String normalize(String u) => u.trim().replaceAll(RegExp(r'/+$'), '');
    final target = normalize(url);
    
    state = state
        .map((n) => NodeInfo(
              url: n.url,
              status: n.status,
              latencyMs: n.latencyMs,
              isSelected: normalize(n.url) == target, // 🔥 改为清洗比对
            ))
        .toList();
  }

  void _updateNode(String url, {NodeStatus? status, int? latencyMs}) {
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

// ── 页面 ────────────────────────────────────────────────
class NetworkSettingsPage extends ConsumerWidget {
  const NetworkSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final nodes = ref.watch(networkSettingsProvider);
    final notifier = ref.read(networkSettingsProvider.notifier);

    final bg = isDark ? AppColors.darkBackground : AppColors.lightBackground;
    final cardBg = isDark ? AppColors.darkCard : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black;
    final subColor = isDark ? Colors.white54 : Colors.black45;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text(
          '网络线路',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: textColor,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(Icons.refresh_rounded, color: AppColors.primary),
            tooltip: '重新测速',
            onPressed: () {
              HapticFeedback.lightImpact();
              notifier.testAll();
            },
          ),
        ],
      ),
      body: nodes.isEmpty
          ? Center(child: CircularProgressIndicator(color: AppColors.primary))
          : ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              children: [
                // 说明文字
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    '选择延迟最低的线路以获得最佳体验。切换后将立即生效。',
                    style: TextStyle(fontSize: 13, color: subColor),
                  ),
                ),

                // 节点列表
                Container(
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      for (int i = 0; i < nodes.length; i++) ...[
                        if (i > 0)
                          Divider(
                              height: 1,
                              indent: 16,
                              color: isDark ? Colors.white12 : Colors.black12),
                        _NodeTile(
                          index: i + 1,
                          node: nodes[i],
                          isDark: isDark,
                          onTap: () {
                            HapticFeedback.selectionClick();
                            notifier.selectNode(nodes[i].url);
                          },
                          onRetest: () {
                            HapticFeedback.lightImpact();
                            notifier.testOne(nodes[i].url);
                          },
                        ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // 重新发现按钮
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.travel_explore_rounded),
                    label: const Text('重新发现可用线路'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: BorderSide(color: AppColors.primary),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () async {
                      HapticFeedback.lightImpact();
                      await notifier.rediscover();
                    },
                  ),
                ),

                const SizedBox(height: 8),
                // Center(
                //   child: Text(
                //     '当前节点: ${ApiConfig.serverUrl}',
                //     style: TextStyle(fontSize: 12, color: subColor),
                //   ),
                // ),
              ],
            ),
    );
  }
}

// ── 节点行 ───────────────────────────────────────────────
class _NodeTile extends StatelessWidget {
  final int index;
  final NodeInfo node;
  final bool isDark;
  final VoidCallback onTap;
  final VoidCallback onRetest;

  const _NodeTile({
    required this.index,
    required this.node,
    required this.isDark,
    required this.onTap,
    required this.onRetest,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = isDark ? Colors.white : Colors.black;
    final subColor = isDark ? Colors.white54 : Colors.black45;

    // 显示为 "线路 1", "线路 2" 等
    final displayName = '线路 $index';

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            // 选中指示
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: node.isSelected ? AppColors.primary : Colors.grey,
                  width: 2,
                ),
                color: node.isSelected ? AppColors.primary : Colors.transparent,
              ),
              child: node.isSelected
                  ? const Icon(Icons.check, size: 12, color: Colors.white)
                  : null,
            ),

            const SizedBox(width: 12),

            // 节点名称
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayName,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight:
                          node.isSelected ? FontWeight.w600 : FontWeight.normal,
                      color: textColor,
                    ),
                  ),
                  // const SizedBox(height: 2),
                  // Text(
                  //   node.url,
                  //   style: TextStyle(fontSize: 11, color: subColor),
                  //   overflow: TextOverflow.ellipsis,
                  // ),
                ],
              ),
            ),

            const SizedBox(width: 8),

            // 延迟显示
            _LatencyBadge(node: node),

            const SizedBox(width: 4),

            // 重测按钮
            IconButton(
              icon: Icon(Icons.refresh_rounded,
                  size: 18, color: isDark ? Colors.white38 : Colors.black38),
              onPressed: onRetest,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
          ],
        ),
      ),
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
        return const SizedBox(width: 60);
      case NodeStatus.testing:
        return SizedBox(
          width: 60,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(width: 4),
              const Text('测速中',
                  style: TextStyle(fontSize: 11, color: Colors.grey)),
            ],
          ),
        );
      case NodeStatus.failed:
        return Container(
          width: 60,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            color: Colors.red.withOpacity(0.12),
            borderRadius: BorderRadius.circular(6),
          ),
          child: const Text(
            '不可用',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: Colors.red),
          ),
        );
      case NodeStatus.ok:
        final ms = node.latencyMs ?? 0;
        final color = ms < 100
            ? const Color(0xFF34C759)
            : ms < 300
                ? const Color(0xFFFF9500)
                : Colors.red;
        return Container(
          width: 60,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            '${ms}ms',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        );
    }
  }
}
