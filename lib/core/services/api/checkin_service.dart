import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';

/// 签到日历 + 统计数据
class CheckinCalendar {
  final String month; // 2026-06
  final List<String> checkedDays; // ["2026-06-01", ...]
  final int totalDays;
  final int continuousDays;
  final bool checkedToday;

  const CheckinCalendar({
    this.month = '',
    this.checkedDays = const [],
    this.totalDays = 0,
    this.continuousDays = 0,
    this.checkedToday = false,
  });

  factory CheckinCalendar.fromJson(Map<String, dynamic> json) {
    return CheckinCalendar(
      month: json['month']?.toString() ?? '',
      checkedDays:
          (json['checked_days'] as List<dynamic>?)?.cast<String>() ?? const [],
      totalDays: json['total_days'] as int? ?? 0,
      continuousDays: json['continuous_days'] as int? ?? 0,
      checkedToday: json['checked_today'] == true,
    );
  }
}

class CheckinService {
  CheckinService(this._api);

  final ApiClient _api;

  /// 拉取某月签到日历，month 形如 2026-06，空则后端默认当月
  Future<CheckinCalendar> getCalendar({String? month}) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/checkin/calendar',
      queryParameters: month != null ? {'month': month} : null,
      fromJson: (data) => data as Map<String, dynamic>,
    );
    if (res.isSuccess && res.data != null) {
      return CheckinCalendar.fromJson(res.data!);
    }
    return const CheckinCalendar();
  }

  /// 执行签到，返回最新统计
  Future<CheckinCalendar> doCheckin() async {
    final res = await _api.post<Map<String, dynamic>>(
      '/checkin',
      fromJson: (data) => data as Map<String, dynamic>,
    );
    if (res.isSuccess && res.data != null) {
      return CheckinCalendar.fromJson(res.data!);
    }
    throw Exception(res.message);
  }
}

final checkinServiceProvider = Provider<CheckinService>((ref) {
  final api = ref.watch(apiClientProvider);
  return CheckinService(api);
});
