import '../../core/constants/api_endpoints.dart';
import '../../core/network/dio_client.dart';
import '../../domain/repositories/payroll_repository.dart';
import '../models/payroll_record.dart';
import '../models/payroll_adjustment.dart';

class PayrollRepositoryImpl implements PayrollRepository {
  final DioClient _api;

  PayrollRepositoryImpl({required DioClient api}) : _api = api;

  @override
  Future<List<PayrollAdjustment>> getAdjustments({
    String? weekStart,
    int? userId,
  }) async {
    final resp = await _api.get<Map<String, dynamic>>(
      ApiEndpoints.payrollAdjustments,
      queryParameters: {
        if (weekStart != null) 'weekStart': weekStart,
        if (userId != null) 'userId': userId,
      },
      fromJson: (d) => d as Map<String, dynamic>,
    );
    final list = (resp.data?['adjustments'] as List<dynamic>?) ?? const [];
    return list
        .whereType<Map<String, dynamic>>()
        .map(PayrollAdjustment.fromJson)
        .toList();
  }

  @override
  Future<PayrollAdjustment> createAdjustment({
    required int userId,
    required String effectiveDate,
    required double dollars,
    required String note,
  }) async {
    final resp = await _api.post<Map<String, dynamic>>(
      ApiEndpoints.payrollAdjustments,
      data: {
        'userId': userId,
        'effectiveDate': effectiveDate,
        'dollars': dollars,
        'note': note,
      },
      fromJson: (d) => d as Map<String, dynamic>,
    );
    return PayrollAdjustment.fromJson(resp.data!);
  }

  @override
  Future<PayrollAdjustment> updateAdjustment({
    required int id,
    double? dollars,
    String? note,
  }) async {
    final resp = await _api.patch<Map<String, dynamic>>(
      ApiEndpoints.payrollAdjustment(id),
      data: {
        if (dollars != null) 'dollars': dollars,
        if (note != null) 'note': note,
      },
      fromJson: (d) => d as Map<String, dynamic>,
    );
    return PayrollAdjustment.fromJson(resp.data!);
  }

  @override
  Future<void> voidAdjustment(int id) async {
    await _api.delete(ApiEndpoints.payrollAdjustment(id));
  }

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
    final resp = await _api.get<Map<String, dynamic>>(
      ApiEndpoints.payrollRecords,
      queryParameters: {if (userId != null) 'userId': userId},
      fromJson: (d) => d as Map<String, dynamic>,
    );
    final items = (resp.data?['items'] as List<dynamic>?) ?? const [];
    return items
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
    final resp = await _api.get<Map<String, dynamic>>(
      ApiEndpoints.payrollPointValues,
      fromJson: (d) => d as Map<String, dynamic>,
    );
    final items = (resp.data?['items'] as List<dynamic>?) ?? const [];
    return items
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
    final resp = await _api.get<Map<String, dynamic>>(
      ApiEndpoints.payrollDollarRates,
      fromJson: (d) => d as Map<String, dynamic>,
    );
    final items = (resp.data?['items'] as List<dynamic>?) ?? const [];
    return items
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

  @override
  Future<void> deleteDollarRate(int id) async {
    await _api.delete(ApiEndpoints.payrollDollarRate(id));
  }
}
