/// One user's rolled-up usage over a date range (from GET /activity/summary).
class UserActivityRow {
  final int userId;
  final String fullName;
  final String? role;
  final int daysActive;
  final int totalActiveSeconds;
  final DateTime? lastSeenAt;

  const UserActivityRow({
    required this.userId,
    required this.fullName,
    this.role,
    required this.daysActive,
    required this.totalActiveSeconds,
    this.lastSeenAt,
  });

  factory UserActivityRow.fromJson(Map<String, dynamic> json) => UserActivityRow(
        userId: int.parse(json['userId'].toString()),
        fullName: (json['fullName'] as String?) ?? 'Unknown',
        role: json['role'] as String?,
        daysActive: (json['daysActive'] as num?)?.toInt() ?? 0,
        totalActiveSeconds: (json['totalActiveSeconds'] as num?)?.toInt() ?? 0,
        lastSeenAt: json['lastSeenAt'] == null
            ? null
            : DateTime.tryParse(json['lastSeenAt'].toString()),
      );
}

class UserActivitySummary {
  final String from;
  final String to;
  final List<UserActivityRow> users;

  const UserActivitySummary({
    required this.from,
    required this.to,
    required this.users,
  });

  factory UserActivitySummary.fromJson(Map<String, dynamic> json) =>
      UserActivitySummary(
        from: (json['from'] as String?) ?? '',
        to: (json['to'] as String?) ?? '',
        users: ((json['users'] as List<dynamic>?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(UserActivityRow.fromJson)
            .toList(),
      );
}

/// One day of a single user's usage (from GET /activity/summary/:userId).
class DailyActivityRow {
  final String day; // YYYY-MM-DD
  final int activeSeconds;
  final DateTime? firstSeenAt;
  final DateTime? lastSeenAt;
  final int pingCount;

  const DailyActivityRow({
    required this.day,
    required this.activeSeconds,
    this.firstSeenAt,
    this.lastSeenAt,
    required this.pingCount,
  });

  factory DailyActivityRow.fromJson(Map<String, dynamic> json) => DailyActivityRow(
        day: (json['day'] as String?) ?? '',
        activeSeconds: (json['activeSeconds'] as num?)?.toInt() ?? 0,
        firstSeenAt: json['firstSeenAt'] == null
            ? null
            : DateTime.tryParse(json['firstSeenAt'].toString()),
        lastSeenAt: json['lastSeenAt'] == null
            ? null
            : DateTime.tryParse(json['lastSeenAt'].toString()),
        pingCount: (json['pingCount'] as num?)?.toInt() ?? 0,
      );
}

class UserDailyActivity {
  final String from;
  final String to;
  final List<DailyActivityRow> days;

  const UserDailyActivity({
    required this.from,
    required this.to,
    required this.days,
  });

  factory UserDailyActivity.fromJson(Map<String, dynamic> json) =>
      UserDailyActivity(
        from: (json['from'] as String?) ?? '',
        to: (json['to'] as String?) ?? '',
        days: ((json['days'] as List<dynamic>?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(DailyActivityRow.fromJson)
            .toList(),
      );
}

/// Format a whole number of seconds as "3h 42m" / "42m" / "0m".
String formatActiveDuration(int seconds) {
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  if (h > 0) return '${h}h ${m}m';
  return '${m}m';
}
