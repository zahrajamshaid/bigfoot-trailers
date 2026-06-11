import '../../data/models/announcement.dart';

abstract class AnnouncementRepository {
  /// Active, unexpired announcements the current user hasn't acked yet,
  /// oldest first.
  Future<List<Announcement>> getPending();

  /// Mark a single announcement as acked. Idempotent on the backend.
  Future<void> ack(int announcementId);

  /// Admin: every announcement + per-row ack counts.
  Future<List<AnnouncementWithStats>> getAllForAdmin();

  Future<Announcement> create({
    String? title,
    required String body,
    DateTime? expiresAt,
  });

  Future<AnnouncementWithStats> update({
    required int id,
    String? title,
    String? body,
    bool? isActive,
    DateTime? expiresAt,
  });

  Future<void> remove(int id);
}
