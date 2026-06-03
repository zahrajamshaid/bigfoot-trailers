import 'package:json_annotation/json_annotation.dart';

part 'payroll_record.g.dart';

double _parseDouble(dynamic v) =>
    v == null ? 0 : (v is num ? v.toDouble() : double.tryParse(v.toString()) ?? 0);

@JsonSerializable()
class PayrollRecord {
  final int id;
  final int userId;
  final int departmentId;
  final DateTime weekStartDate;
  @JsonKey(fromJson: _parseDouble)
  final double totalPoints;
  final int trailersCompleted;
  @JsonKey(fromJson: _parseDouble)
  final double grossPay;
  final bool isLocked;
  final DateTime? lockedAt;
  final DateTime? createdAt;
  final PayrollUserRef? user;
  final PayrollDepartmentRef? department;

  const PayrollRecord({
    required this.id,
    required this.userId,
    required this.departmentId,
    required this.weekStartDate,
    this.totalPoints = 0,
    this.trailersCompleted = 0,
    this.grossPay = 0,
    this.isLocked = false,
    this.lockedAt,
    this.createdAt,
    this.user,
    this.department,
  });

  factory PayrollRecord.fromJson(Map<String, dynamic> json) =>
      _$PayrollRecordFromJson(json);
  Map<String, dynamic> toJson() => _$PayrollRecordToJson(this);
}

@JsonSerializable()
class PayrollUserRef {
  final int id;
  final String fullName;
  final String? email;

  const PayrollUserRef({
    required this.id,
    required this.fullName,
    this.email,
  });

  factory PayrollUserRef.fromJson(Map<String, dynamic> json) =>
      _$PayrollUserRefFromJson(json);
  Map<String, dynamic> toJson() => _$PayrollUserRefToJson(this);
}

@JsonSerializable()
class PayrollDepartmentRef {
  final int id;
  final String code;
  final String displayName;

  const PayrollDepartmentRef({
    required this.id,
    required this.code,
    required this.displayName,
  });

  factory PayrollDepartmentRef.fromJson(Map<String, dynamic> json) =>
      _$PayrollDepartmentRefFromJson(json);
  Map<String, dynamic> toJson() => _$PayrollDepartmentRefToJson(this);
}

@JsonSerializable()
class PointValue {
  final int id;
  final int trailerModelId;
  final int departmentId;
  @JsonKey(fromJson: _parseDouble)
  final double points;
  final DateTime? effectiveFrom;
  final DateTime? effectiveTo;
  final PointValueTrailerModel? trailerModel;
  final PayrollDepartmentRef? department;

  const PointValue({
    required this.id,
    required this.trailerModelId,
    required this.departmentId,
    required this.points,
    this.effectiveFrom,
    this.effectiveTo,
    this.trailerModel,
    this.department,
  });

  factory PointValue.fromJson(Map<String, dynamic> json) =>
      _$PointValueFromJson(json);
  Map<String, dynamic> toJson() => _$PointValueToJson(this);
}

@JsonSerializable()
class PointValueTrailerModel {
  final int id;
  final String displayName;
  final String series;

  const PointValueTrailerModel({
    required this.id,
    required this.displayName,
    required this.series,
  });

  factory PointValueTrailerModel.fromJson(Map<String, dynamic> json) =>
      _$PointValueTrailerModelFromJson(json);
  Map<String, dynamic> toJson() => _$PointValueTrailerModelToJson(this);
}

@JsonSerializable()
class DollarRate {
  final int id;
  final int departmentId;
  @JsonKey(fromJson: _parseDouble)
  final double dollarPerPoint;
  final DateTime? effectiveFrom;
  final DateTime? effectiveTo;
  final PayrollDepartmentRef? department;

  const DollarRate({
    required this.id,
    required this.departmentId,
    required this.dollarPerPoint,
    this.effectiveFrom,
    this.effectiveTo,
    this.department,
  });

  factory DollarRate.fromJson(Map<String, dynamic> json) =>
      _$DollarRateFromJson(json);
  Map<String, dynamic> toJson() => _$DollarRateToJson(this);
}

@JsonSerializable()
class WorkerSummary {
  final int userId;
  final String fullName;
  final String weekStartDate;
  @JsonKey(fromJson: _parseDouble)
  final double totalPoints;
  @JsonKey(fromJson: _parseDouble)
  final double projectedEarnings;
  final int stepsCompleted;
  final int reworkCount;
  final List<WorkerDepartmentSummary> departments;

  const WorkerSummary({
    required this.userId,
    required this.fullName,
    required this.weekStartDate,
    this.totalPoints = 0,
    this.projectedEarnings = 0,
    this.stepsCompleted = 0,
    this.reworkCount = 0,
    this.departments = const [],
  });

  factory WorkerSummary.fromJson(Map<String, dynamic> json) =>
      _$WorkerSummaryFromJson(json);
  Map<String, dynamic> toJson() => _$WorkerSummaryToJson(this);
}

@JsonSerializable()
class WorkerDepartmentSummary {
  final int departmentId;
  final String code;
  final String name;
  @JsonKey(fromJson: _parseDouble)
  final double points;
  final int steps;
  final int reworks;
  @JsonKey(fromJson: _parseDouble)
  final double dollarPerPoint;
  @JsonKey(fromJson: _parseDouble)
  final double projectedEarnings;

  const WorkerDepartmentSummary({
    required this.departmentId,
    required this.code,
    required this.name,
    this.points = 0,
    this.steps = 0,
    this.reworks = 0,
    this.dollarPerPoint = 0,
    this.projectedEarnings = 0,
  });

  factory WorkerDepartmentSummary.fromJson(Map<String, dynamic> json) =>
      _$WorkerDepartmentSummaryFromJson(json);
  Map<String, dynamic> toJson() => _$WorkerDepartmentSummaryToJson(this);
}

@JsonSerializable()
class WeeklyPayrollReport {
  final String weekStartDate;
  final String weekEndDate;
  final bool isLocked;
  final DateTime? lockedAt;
  final PayrollUserRef? lockedBy;
  final List<WeeklyPayrollWorker> workers;

  const WeeklyPayrollReport({
    required this.weekStartDate,
    required this.weekEndDate,
    this.isLocked = false,
    this.lockedAt,
    this.lockedBy,
    this.workers = const [],
  });

  factory WeeklyPayrollReport.fromJson(Map<String, dynamic> json) =>
      _$WeeklyPayrollReportFromJson(json);
  Map<String, dynamic> toJson() => _$WeeklyPayrollReportToJson(this);
}

@JsonSerializable()
class WeeklyPayrollWorker {
  final int userId;
  final String fullName;
  final String? email;
  @JsonKey(fromJson: _parseDouble)
  final double totalPoints;
  @JsonKey(fromJson: _parseDouble)
  final double totalGrossPay;
  final int totalStepsCompleted;
  final int totalReworkCount;
  final List<WeeklyPayrollDepartment> departments;

  const WeeklyPayrollWorker({
    required this.userId,
    required this.fullName,
    this.email,
    this.totalPoints = 0,
    this.totalGrossPay = 0,
    this.totalStepsCompleted = 0,
    this.totalReworkCount = 0,
    this.departments = const [],
  });

  factory WeeklyPayrollWorker.fromJson(Map<String, dynamic> json) =>
      _$WeeklyPayrollWorkerFromJson(json);
  Map<String, dynamic> toJson() => _$WeeklyPayrollWorkerToJson(this);
}

@JsonSerializable()
class WeeklyPayrollDepartment {
  final int departmentId;
  final String departmentCode;
  final String departmentName;
  @JsonKey(fromJson: _parseDouble)
  final double totalPoints;
  final int stepsCompleted;
  final int reworkCount;
  @JsonKey(fromJson: _parseDouble)
  final double dollarPerPoint;
  @JsonKey(fromJson: _parseDouble)
  final double grossPay;
  /// Distinct trailers this worker touched in this department for the week
  /// (SO, length, model). Defaults to empty so older payloads that don't
  /// carry the field still deserialise cleanly.
  @JsonKey(defaultValue: <WeeklyPayrollTrailer>[])
  final List<WeeklyPayrollTrailer> trailers;

  const WeeklyPayrollDepartment({
    required this.departmentId,
    required this.departmentCode,
    required this.departmentName,
    this.totalPoints = 0,
    this.stepsCompleted = 0,
    this.reworkCount = 0,
    this.dollarPerPoint = 0,
    this.grossPay = 0,
    this.trailers = const <WeeklyPayrollTrailer>[],
  });

  factory WeeklyPayrollDepartment.fromJson(Map<String, dynamic> json) =>
      _$WeeklyPayrollDepartmentFromJson(json);
  Map<String, dynamic> toJson() => _$WeeklyPayrollDepartmentToJson(this);
}

/// One trailer the worker touched in a given department this week. Surfaces
/// on the weekly payroll report drilldown + the CSV detail block.
@JsonSerializable()
class WeeklyPayrollTrailer {
  final String trailerId;
  final String soNumber;
  final String? sizeFt;
  final String? modelName;
  @JsonKey(fromJson: _parseDouble)
  final double points;
  final bool isRework;

  const WeeklyPayrollTrailer({
    required this.trailerId,
    required this.soNumber,
    this.sizeFt,
    this.modelName,
    this.points = 0,
    this.isRework = false,
  });

  factory WeeklyPayrollTrailer.fromJson(Map<String, dynamic> json) =>
      _$WeeklyPayrollTrailerFromJson(json);
  Map<String, dynamic> toJson() => _$WeeklyPayrollTrailerToJson(this);
}

@JsonSerializable()
class PayrollLockResult {
  final String weekStartDate;
  final bool isLocked;
  final DateTime? lockedAt;
  final int recordsLocked;

  const PayrollLockResult({
    required this.weekStartDate,
    this.isLocked = false,
    this.lockedAt,
    this.recordsLocked = 0,
  });

  factory PayrollLockResult.fromJson(Map<String, dynamic> json) =>
      _$PayrollLockResultFromJson(json);
  Map<String, dynamic> toJson() => _$PayrollLockResultToJson(this);
}
