import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'api_client.dart';

class AppCleanException implements Exception {
  final String? message;
  const AppCleanException(this.message);
  @override
  String toString() => message ?? 'Error';
}

/// 签到日历 + 统计数据
class CheckinCalendar {
  final String month;
  final List<String> checkedDays;
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
      checkedDays: (json['checked_days'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      totalDays: json['total_days'] as int? ?? 0,
      continuousDays: json['continuous_days'] as int? ?? 0,
      checkedToday: json['checked_today'] == true,
    );
  }
}

class CheckinService {
  final ApiClient _api;
  CheckinService(this._api);

  Future<CheckinCalendar> getCalendar({required String month}) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/checkin/calendar',
      queryParameters: {'month': month},
      fromJson: (data) => data as Map<String, dynamic>,
    );
    if (res.isSuccess && res.data != null) {
      return CheckinCalendar.fromJson(res.data!);
    }
    return const CheckinCalendar();
  }

  Future<CheckinCalendar> doCheckin() async {
    final res = await _api.post<Map<String, dynamic>>(
      '/checkin',
      fromJson: (data) => data as Map<String, dynamic>,
    );
    if (res.isSuccess && res.data != null) {
      return CheckinCalendar.fromJson(res.data!);
    }
    throw AppCleanException(res.message);
  }
}

final checkinServiceProvider = Provider<CheckinService>((ref) {
  final api = ref.watch(apiClientProvider);
  return CheckinService(api);
});
