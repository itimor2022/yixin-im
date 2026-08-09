// 文件用途：实现 _ChatDetailGroupInfoWidgets 页面及其交互流程，属于聊天与消息。
// 核心逻辑：维护 _ChatDetailGroupInfoWidgets 页面状态，响应用户操作并调用 Provider/Service；同时处理加载、成功、失败和返回导航。
part of 'chat_detail_page.dart';

// 关键声明：chat detail group info widgets 是页面入口，负责组装局部状态、监听用户操作并把副作用交给 Provider/Service。
extension _ChatDetailGroupInfoWidgets on _GroupInfoSheet {
  // 流程逻辑：`_buildInfoChip` 根据输入状态生成页面片段或触发回调，交互副作用由页面状态边界统一处理。
  Widget _buildInfoChip({
    required IconData icon,
    required String label,
    required bool isDark,
    Color? accentColor,
  }) {
    final chipColor = accentColor ??
        (isDark ? AppColors.primaryDarkMode : AppColors.primaryLight);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color:
            isDark ? chipColor.withOpacity(0.14) : chipColor.withOpacity(0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: chipColor.withOpacity(isDark ? 0.26 : 0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: chipColor),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : const Color(0xFF334155),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required String subtitle,
    required bool isDark,
    Color? accentColor,
  }) {
    final tone = accentColor ??
        (isDark ? AppColors.primaryDarkMode : AppColors.primaryLight);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.05) : tone.withOpacity(0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: tone.withOpacity(0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: tone,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : const Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.white54 : Colors.black45,
            ),
          ),
        ],
      ),
    );
  }
}
