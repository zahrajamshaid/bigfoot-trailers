import '../../core/constants/api_endpoints.dart';
import '../../core/network/dio_client.dart';
import '../../domain/repositories/yard_audit_repository.dart';
import '../models/yard_audit.dart';

class YardAuditRepositoryImpl implements YardAuditRepository {
  final DioClient _api;

  YardAuditRepositoryImpl({required DioClient api}) : _api = api;

  @override
  Future<YardAuditResult> submit({
    required int locationId,
    required List<int> missingTrailerIds,
    required List<AuditExtra> extras,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      ApiEndpoints.yardAudit,
      data: {
        'locationId': locationId,
        'missingTrailerIds': missingTrailerIds,
        'extras': extras
            .where((e) => !e.isEmpty)
            .map((e) => e.toJson())
            .toList(),
      },
      fromJson: (d) => d as Map<String, dynamic>,
    );
    return YardAuditResult.fromJson(res.data!);
  }
}
