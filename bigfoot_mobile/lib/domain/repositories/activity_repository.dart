import '../../data/models/user_activity.dart';

abstract class ActivityRepository {
  /// Fire-and-forget usage heartbeat for the current user. Never throws.
  Future<void> heartbeat();

  /// Per-user usage over [from, to] (YYYY-MM-DD). Owner/office only.
  Future<UserActivitySummary> getSummary({String? from, String? to});

  /// One user's day-by-day usage. Owner/office only.
  Future<UserDailyActivity> getUserDaily(int userId, {String? from, String? to});
}
