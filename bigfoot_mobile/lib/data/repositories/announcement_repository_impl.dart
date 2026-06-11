import '../../core/constants/api_endpoints.dart';
import '../../core/network/dio_client.dart';
import '../../domain/repositories/announcement_repository.dart';
import '../models/announcement.dart';

class AnnouncementRepositoryImpl implements AnnouncementRepository {
  final DioClient _api;

  AnnouncementRepositoryImpl({required DioClient api}) : _api = api;

  @override
  Future<List<Announcement>> getPending() async {
    final res = await _api.get<List<dynamic>>(
      ApiEndpoints.announcementsPending,
      fromJson: (d) => d as List<dynamic>,
    );
    return (res.data ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(Announcement.fromJson)
        .toList();
  }

  @override
  Future<void> ack(int announcementId) async {
    await _api.post(ApiEndpoints.announcementAck(announcementId));
  }

  @override
  Future<List<AnnouncementWithStats>> getAllForAdmin() async {
    final res = await _api.get<List<dynamic>>(
      ApiEndpoints.adminAnnouncements,
      fromJson: (d) => d as List<dynamic>,
    );
    return (res.data ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(AnnouncementWithStats.fromJson)
        .toList();
  }

  @override
  Future<Announcement> create({
    String? title,
    required String body,
    DateTime? expiresAt,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      ApiEndpoints.adminAnnouncements,
      data: {
        if (title != null && title.trim().isNotEmpty) 'title': title.trim(),
        'body': body.trim(),
        if (expiresAt != null) 'expiresAt': expiresAt.toUtc().toIso8601String(),
      },
      fromJson: (d) => d as Map<String, dynamic>,
    );
    return Announcement.fromJson(res.data!);
  }

  @override
  Future<AnnouncementWithStats> update({
    required int id,
    String? title,
    String? body,
    bool? isActive,
    DateTime? expiresAt,
  }) async {
    final res = await _api.patch<Map<String, dynamic>>(
      ApiEndpoints.adminAnnouncement(id),
      data: {
        if (title != null) 'title': title.trim(),
        if (body != null) 'body': body.trim(),
        if (isActive != null) 'isActive': isActive,
        if (expiresAt != null) 'expiresAt': expiresAt.toUtc().toIso8601String(),
      },
      fromJson: (d) => d as Map<String, dynamic>,
    );
    return AnnouncementWithStats.fromJson(res.data!);
  }

  @override
  Future<void> remove(int id) async {
    await _api.delete(ApiEndpoints.adminAnnouncement(id));
  }
}
