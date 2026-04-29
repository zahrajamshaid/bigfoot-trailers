import '../../core/constants/api_endpoints.dart';
import '../../core/network/dio_client.dart';
import '../../domain/repositories/payroll_repository.dart';
import '../models/payroll_record.dart';

class PayrollRepositoryImpl implements PayrollRepository {
  final DioClient _api;

  PayrollRepositoryImpl({required DioClient api}) : _api = api;

  @override
  Future<WorkerSummary> getWorkerSummary(int userId) async {
    final resp = await _api.get<Map<String, dynamic>>(
      ApiEndpoints.payrollWorkerSummary(userId),
      fromJson: (d) => d as Map<String, dynamic>,
    );
    return WorkerSummary.fromJson(resp.data!);
  }

  @override
  Future<List<PayrollRecord>> getRecords({int? userId}) async {
    final resp = await _api.get<List<dynamic>>(
      ApiEndpoints.payrollRecords,
      queryParameters: {if (userId != null) 'userId': userId},
      fromJson: (d) => d as List<dynamic>,
    );
    return (resp.data ?? [])
        .whereType<Map<String, dynamic>>()
        .map(PayrollRecord.fromJson)
        .toList();
  }

  @override
  Future<WeeklyPayrollReport> getWeeklyReport(String weekStart) async {
    final resp = await _api.get<Map<String, dynamic>>(
      ApiEndpoints.payrollWeekReport(weekStart),
      fromJson: (d) => d as Map<String, dynamic>,
    );
    return WeeklyPayrollReport.fromJson(resp.data!);
  }

  @override
  Future<PayrollLockResult> lockWeek(String weekStart) async {
    final resp = await _api.post<Map<String, dynamic>>(
      ApiEndpoints.payrollLockWeek(weekStart),
      fromJson: (d) => d as Map<String, dynamic>,
    );
    return PayrollLockResult.fromJson(resp.data!);
  }

  @override
  Future<List<PointValue>> getPointValues() async {
    final resp = await _api.get<List<dynamic>>(
      ApiEndpoints.payrollPointValues,
      fromJson: (d) => d as List<dynamic>,
    );
    return (resp.data ?? [])
        .whereType<Map<String, dynamic>>()
        .map(PointValue.fromJson)
        .toList();
  }

  @override
  Future<PointValue> createPointValue({
    required int trailerModelId,
    required int departmentId,
    required double points,
    required DateTime effectiveFrom,
  }) async {
    final resp = await _api.post<Map<String, dynamic>>(
      ApiEndpoints.payrollPointValues,
      data: {
        'trailerModelId': trailerModelId,
        'departmentId': departmentId,
        'points': points,
        'effectiveFrom': effectiveFrom.toIso8601String().split('T').first,
      },
      fromJson: (d) => d as Map<String, dynamic>,
    );
    return PointValue.fromJson(resp.data!);
  }

  @override
  Future<PointValue> updatePointValue({
    required int id,
    double? points,
    DateTime? effectiveTo,
  }) async {
    final resp = await _api.patch<Map<String, dynamic>>(
      ApiEndpoints.payrollPointValue(id),
      data: {
        if (points != null) 'points': points,
        if (effectiveTo != null)
          'effectiveTo': effectiveTo.toIso8601String().split('T').first,
      },
      fromJson: (d) => d as Map<String, dynamic>,
    );
    return PointValue.fromJson(resp.data!);
  }

  @override
  Future<List<DollarRate>> getDollarRates() async {
    final resp = await _api.get<List<dynamic>>(
      ApiEndpoints.payrollDollarRates,
      fromJson: (d) => d as List<dynamic>,
    );
    return (resp.data ?? [])
        .whereType<Map<String, dynamic>>()
        .map(DollarRate.fromJson)
        .toList();
  }

  @override
  Future<DollarRate> createDollarRate({
    required int departmentId,
    required double dollarPerPoint,
    required DateTime effectiveFrom,
  }) async {
    final resp = await _api.post<Map<String, dynamic>>(
      ApiEndpoints.payrollDollarRates,
      data: {
        'departmentId': departmentId,
        'dollarPerPoint': dollarPerPoint,
        'effectiveFrom': effectiveFrom.toIso8601String().split('T').first,
      },
      fromJson: (d) => d as Map<String, dynamic>,
    );
    return DollarRate.fromJson(resp.data!);
  }
}
