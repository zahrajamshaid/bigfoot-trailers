import '../../data/models/yard_audit.dart';

abstract class YardAuditRepository {
  /// Submit a yard audit. Opens one problem report per missing trailer
  /// (listed in the app at this yard but not physically found) and one per
  /// extra (found on the lot but not expected here).
  Future<YardAuditResult> submit({
    required int locationId,
    required List<int> missingTrailerIds,
    required List<AuditExtra> extras,
  });
}
