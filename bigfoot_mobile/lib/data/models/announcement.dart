/// One floor-wide message admins push to every user.
///
/// `GET /announcements/pending` returns the slim shape (no ack-count fields);
/// `GET /admin/announcements` returns the [AnnouncementWithStats] variant.
class Announcement {
  final int id;
  final String? title;
  final String body;
  final DateTime? createdAt;
  final String? postedByName;

  const Announcement({
    required this.id,
    this.title,
    required this.body,
    this.createdAt,
    this.postedByName,
  });

  factory Announcement.fromJson(Map<String, dynamic> json) {
    final postedBy = json['postedByUser'] as Map<String, dynamic>?;
    return Announcement(
      id: (json['id'] as num).toInt(),
      title: json['title'] as String?,
      body: json['body'] as String? ?? '',
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
