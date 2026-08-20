import '../../core/constants/api_endpoints.dart';
import '../../core/network/dio_client.dart';
import '../../domain/repositories/activity_repository.dart';
import '../models/user_activity.dart';

class ActivityRepositoryImpl implements ActivityRepository {
  final DioClient _api;

  ActivityRepositoryImpl({required DioClient api}) : _api = api;

  @override
  Future<void> heartbeat() async {
    try {
      await _api.post(ApiEndpoints.activityHeartbeat);
    } catch (_) {
      // Usage tracking must never disrupt the app — swallow all errors.
    }
  }

  @override
  Future<UserActivitySummary> getSummary({String? from, String? to}) async {
    final res = await _api.get<Map<String, dynamic>>(
      ApiEndpoints.activitySummary,
      queryParameters: {
        if (from != null) 'from': from,
        if (to != null) 'to': to,
      },
      fromJson: (d) => d as Map<String, dynamic>,
    );
    return UserActivitySummary.fromJson(res.data!);
  }

  @override
  Future<UserDailyActivity> getUserDaily(
    int userId, {
    String? from,
    String? to,
  }) async {
    final res = await _api.get<Map<String, dynamic>>(
      ApiEndpoints.activityUserDaily(userId),
      queryParameters: {
        if (from != null) 'from': from,
        if (to != null) 'to': to,
      },
      fromJson: (d) => d as Map<String, dynamic>,
    );
    return UserDailyActivity.fromJson(res.data!);
  }
}
