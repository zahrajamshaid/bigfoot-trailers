/// A trailer physically found in the yard that the app did NOT list there.
/// Captured during a yard audit as an "extra". Mutable so the form can edit it.
class AuditExtra {
  String soNumber;
  String note;

  AuditExtra({this.soNumber = '', this.note = ''});

  bool get isEmpty => soNumber.trim().isEmpty && note.trim().isEmpty;

  Map<String, dynamic> toJson() => {
        if (soNumber.trim().isNotEmpty) 'soNumber': soNumber.trim(),
        if (note.trim().isNotEmpty) 'note': note.trim(),
      };
}

/// Result of submitting a yard audit — how many problem reports were opened.
class YardAuditResult {
  final String locationName;
  final int missingReported;
  final int extrasReported;
  final int totalReported;

  const YardAuditResult({
    required this.locationName,
    required this.missingReported,
    required this.extrasReported,
    required this.totalReported,
  });

  factory YardAuditResult.fromJson(Map<String, dynamic> json) => YardAuditResult(
        locationName: (json['locationName'] as String?) ?? '',
        missingReported: (json['missingReported'] as num?)?.toInt() ?? 0,
        extrasReported: (json['extrasReported'] as num?)?.toInt() ?? 0,
        totalReported: (json['totalReported'] as num?)?.toInt() ?? 0,
      );
}
