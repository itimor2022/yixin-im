// 文件用途：实现 VIP 相关逻辑，服务于会员权益。
// 核心逻辑：围绕 VIP 组织，完成输入校验、核心处理和结果回传。
// 关键声明：VIP 是会员模块导出入口，负责集中暴露会员页面、模型、Provider、Service 和徽章组件。
// 流程逻辑：本文件没有可执行方法，关键行为由导出的常量、条件实现或模块声明决定；修改时需保持公共导出契约稳定。
library vip;

export 'pages/vip_center_page.dart';
export 'pages/vip_orders_page.dart';
export 'models/vip_profile_summary.dart';
export 'providers/vip_provider.dart';
export 'services/vip_service.dart';
export 'widgets/vip_badge.dart';
