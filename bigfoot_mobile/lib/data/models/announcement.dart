/// One floor-wide message admins push to every user.
///
/// `GET /announcements/pending` returns the slim shape (no ack-count fields);
/// `GET /admin/announcements` returns the [AnnouncementWithStats] variant.
/// How often an announcement re-appears for someone who has already seen it.
/// Mirrors the backend `ANNOUNCEMENT_FREQUENCIES`.
class AnnouncementFrequency {
  static const String once = 'once';
  static const String everyLogin = 'every_login';
  static const String daily = 'daily';
  static const String weekly = 'weekly';

  static const List<String> all = [once, everyLogin, daily, weekly];

  /// Human label for the frequency picker + admin card chip.
  static String label(String value) {
    switch (value) {
      case everyLogin:
        return 'Every login';
      case daily:
        return 'Daily';
      case weekly:
        return 'Weekly';
      case once:
      default:
        return 'Once';
    }
  }
}

class Announcement {
  final int id;
  final String? title;
  final String body;
  final String frequency;
  final DateTime? createdAt;
  final String? postedByName;

  const Announcement({
    required this.id,
    this.title,
    required this.body,
    this.frequency = AnnouncementFrequency.once,
    this.createdAt,
    this.postedByName,
  });

  factory Announcement.fromJson(Map<String, dynamic> json) {
    final postedBy = json['postedByUser'] as Map<String, dynamic>?;
    return Announcement(
      id: (json['id'] as num).toInt(),
      title: json['title'] as String?,
      body: json['body'] as String? ?? '',
      frequency: json['frequency'] as String? ?? AnnouncementFrequency.once,
      createdAt: json['createdAt'] == null
          ? null
          : DateTime.tryParse(json['createdAt'].toString()),
      postedByName: postedBy?['fullName'] as String?,
    );
  }
}

/// Admin-view payload — same as [Announcement] plus the ack progress + the
/// raw fields the management screen needs to toggle activity / expiry.
class AnnouncementWithStats {
  final Announcement announcement;
  final bool isActive;
  final DateTime? expiresAt;
  final int ackCount;
  final int totalUsers;

  const AnnouncementWithStats({
    required this.announcement,
    required this.isActive,
    this.expiresAt,
    required this.ackCount,
    required this.totalUsers,
  });

  factory AnnouncementWithStats.fromJson(Map<String, dynamic> json) {
    return AnnouncementWithStats(
      announcement: Announcement.fromJson(json),
      isActive: json['isActive'] as bool? ?? true,
      expiresAt: json['expiresAt'] == null
          ? null
          : DateTime.tryParse(json['expiresAt'].toString()),
      ackCount: (json['ackCount'] as num?)?.toInt() ?? 0,
      totalUsers: (json['totalUsers'] as num?)?.toInt() ?? 0,
    );
  }
}
