import '../../data/models/payroll_record.dart';
import '../../data/models/payroll_adjustment.dart';

/// Abstract contract for payroll operations.
abstract class PayrollRepository {
  /// Manual payroll line-items for a week (bonus / correction / deduction).
  Future<List<PayrollAdjustment>> getAdjustments({String? weekStart, int? userId});
  Future<PayrollAdjustment> createAdjustment({
    required int userId,
    required String effectiveDate,
    required double dollars,
    required String note,
  });
  Future<PayrollAdjustment> updateAdjustment({
    required int id,
    double? dollars,
    String? note,
  });
  Future<void> voidAdjustment(int id);

  Future<WorkerSummary> getWorkerSummary(int userId);
  Future<List<PayrollRecord>> getRecords({int? userId});
  Future<WeeklyPayrollReport> getWeeklyReport(String weekStart);
  Future<PayrollLockResult> lockWeek(String weekStart);
  Future<List<PointValue>> getPointValues();
  Future<PointValue> createPointValue({
    required int trailerModelId,
    required int departmentId,
    required double points,
    required DateTime effectiveFrom,
  });
  Future<PointValue> updatePointValue({
    required int id,
    double? points,
    DateTime? effectiveTo,
  });
  Future<List<DollarRate>> getDollarRates();
  Future<DollarRate> createDollarRate({
    required int departmentId,
    required double dollarPerPoint,
    required DateTime effectiveFrom,
  });
  Future<void> deleteDollarRate(int id);
}
