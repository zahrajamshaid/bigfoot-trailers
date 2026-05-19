import '../../core/constants/api_endpoints.dart';
import '../../core/network/dio_client.dart';
import '../../domain/repositories/notification_repository.dart';
import '../models/app_notification.dart';

class NotificationRepositoryImpl implements NotificationRepository {
  final DioClient _api;

  NotificationRepositoryImpl({required DioClient api}) : _api = api;

  @override
  Future<List<AppNotification>> getHistory({int page = 1, int limit = 100}) async {
    final response = await _api.get<Map<String, dynamic>>(
      ApiEndpoints.notifications,
      queryParameters: {'page': page, 'limit': limit},
      fromJson: (d) => d as Map<String, dynamic>,
    );

    final data = response.data ?? <String, dynamic>{};
    return ((data['items'] as List<dynamic>?) ??
            (data['notifications'] as List<dynamic>?) ??
            const [])
        .whereType<Map<String, dynamic>>()
        .map(AppNotification.fromJson)
        .toList();
  }

  @override
  Future<void> deleteNotification(String id) async {
    await _api.delete<Map<String, dynamic>>(
      '${ApiEndpoints.notifications}/$id',
      fromJson: (d) => d as Map<String, dynamic>,
    );
  }

  @override
  Future<void> registerPushToken(String token) async {
    await _api.patch<Map<String, dynamic>>(
      ApiEndpoints.authPushToken,
      data: {'pushToken': token},
      fromJson: (d) => d as Map<String, dynamic>,
    );
  }
}
