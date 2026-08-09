// 文件用途：实现 wallet 相关逻辑，服务于钱包与支付。
// 核心逻辑：围绕 wallet 组织，完成输入校验、核心处理和结果回传。
// 关键声明：wallet 是钱包模块导出入口，负责集中暴露余额、交易、充值、提现和支付相关页面与服务。
// 流程逻辑：本文件没有可执行方法，关键行为由导出的常量、条件实现或模块声明决定；修改时需保持公共导出契约稳定。
/// 钱包模块导出文件
library wallet;

// Services
export 'services/wallet_service.dart';

// Providers
export 'providers/wallet_provider.dart';

// Pages
export 'pages/wallet_page.dart';
export 'pages/set_pay_password_page.dart';
export 'pages/recharge_page.dart';
export 'pages/payment_result_page.dart';
export 'pages/withdraw_page.dart';
export 'pages/transaction_list_page.dart';
export 'pages/send_red_packet_page.dart';
export 'pages/transfer_page.dart';

// Widgets
export 'widgets/amount_input.dart';
export 'widgets/pay_password_input.dart';
export 'widgets/red_packet_bubble.dart';
export 'widgets/transfer_bubble.dart';
