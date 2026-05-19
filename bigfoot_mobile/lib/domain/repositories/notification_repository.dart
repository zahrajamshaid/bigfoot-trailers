import '../../data/models/app_notification.dart';

/// Abstract contract for notification operations.
abstract class NotificationRepository {
  Future<List<AppNotification>> getHistory({int page, int limit});
  Future<void> registerPushToken(String token);

  /// Permanently deletes a single notification from the user's history.
  Future<void> deleteNotification(String id);
}
