// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'payroll_record.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

PayrollRecord _$PayrollRecordFromJson(Map<String, dynamic> json) =>
    PayrollRecord(
      id: (json['id'] as num).toInt(),
      userId: (json['userId'] as num).toInt(),
      departmentId: (json['departmentId'] as num).toInt(),
      weekStartDate: DateTime.parse(json['weekStartDate'] as String),
      totalPoints: json['totalPoints'] == null
          ? 0
          : _parseDouble(json['totalPoints']),
      trailersCompleted: (json['trailersCompleted'] as num?)?.toInt() ?? 0,
      grossPay: json['grossPay'] == null ? 0 : _parseDouble(json['grossPay']),
      isLocked: json['isLocked'] as bool? ?? false,
      lockedAt: json['lockedAt'] == null
          ? null
          : DateTime.parse(json['lockedAt'] as String),
      createdAt: json['createdAt'] == null
          ? null
          : DateTime.parse(json['createdAt'] as String),
      user: json['user'] == null
          ? null
          : PayrollUserRef.fromJson(json['user'] as Map<String, dynamic>),
      department: json['department'] == null
          ? null
          : PayrollDepartmentRef.fromJson(
              json['department'] as Map<String, dynamic>,
            ),
    );

Map<String, dynamic> _$PayrollRecordToJson(PayrollRecord instance) =>
    <String, dynamic>{
      'id': instance.id,
      'userId': instance.userId,
      'departmentId': instance.departmentId,
      'weekStartDate': instance.weekStartDate.toIso8601String(),
      'totalPoints': instance.totalPoints,
      'trailersCompleted': instance.trailersCompleted,
      'grossPay': instance.grossPay,
      'isLocked': instance.isLocked,
      'lockedAt': instance.lockedAt?.toIso8601String(),
      'createdAt': instance.createdAt?.toIso8601String(),
      'user': instance.user,
      'department': instance.department,
    };

PayrollUserRef _$PayrollUserRefFromJson(Map<String, dynamic> json) =>
    PayrollUserRef(
      id: (json['id'] as num).toInt(),
      fullName: json['fullName'] as String,
      email: json['email'] as String?,
    );

Map<String, dynamic> _$PayrollUserRefToJson(PayrollUserRef instance) =>
    <String, dynamic>{
      'id': instance.id,
      'fullName': instance.fullName,
      'email': instance.email,
    };

PayrollDepartmentRef _$PayrollDepartmentRefFromJson(
  Map<String, dynamic> json,
) => PayrollDepartmentRef(
  id: (json['id'] as num).toInt(),
  code: json['code'] as String,
  displayName: json['displayName'] as String,
);

Map<String, dynamic> _$PayrollDepartmentRefToJson(
  PayrollDepartmentRef instance,
) => <String, dynamic>{
  'id': instance.id,
  'code': instance.code,
  'displayName': instance.displayName,
};

PointValue _$PointValueFromJson(Map<String, dynamic> json) => PointValue(
  id: (json['id'] as num).toInt(),
  trailerModelId: (json['trailerModelId'] as num).toInt(),
  departmentId: (json['departmentId'] as num).toInt(),
  points: _parseDouble(json['points']),
  effectiveFrom: json['effectiveFrom'] == null
      ? null
      : DateTime.parse(json['effectiveFrom'] as String),
  effectiveTo: json['effectiveTo'] == null
      ? null
      : DateTime.parse(json['effectiveTo'] as String),
  trailerModel: json['trailerModel'] == null
      ? null
      : PointValueTrailerModel.fromJson(
          json['trailerModel'] as Map<String, dynamic>,
        ),
  department: json['department'] == null
      ? null
      : PayrollDepartmentRef.fromJson(
          json['department'] as Map<String, dynamic>,
        ),
);

Map<String, dynamic> _$PointValueToJson(PointValue instance) =>
    <String, dynamic>{
      'id': instance.id,
      'trailerModelId': instance.trailerModelId,
      'departmentId': instance.departmentId,
      'points': instance.points,
      'effectiveFrom': instance.effectiveFrom?.toIso8601String(),
      'effectiveTo': instance.effectiveTo?.toIso8601String(),
      'trailerModel': instance.trailerModel,
      'department': instance.department,
    };

PointValueTrailerModel _$PointValueTrailerModelFromJson(
  Map<String, dynamic> json,
) => PointValueTrailerModel(
  id: (json['id'] as num).toInt(),
  displayName: json['displayName'] as String,
  series: json['series'] as String,
);

Map<String, dynamic> _$PointValueTrailerModelToJson(
  PointValueTrailerModel instance,
) => <String, dynamic>{
  'id': instance.id,
  'displayName': instance.displayName,
  'series': instance.series,
};

DollarRate _$DollarRateFromJson(Map<String, dynamic> json) => DollarRate(
  id: (json['id'] as num).toInt(),
  departmentId: (json['departmentId'] as num).toInt(),
  dollarPerPoint: _parseDouble(json['dollarPerPoint']),
  effectiveFrom: json['effectiveFrom'] == null
      ? null
      : DateTime.parse(json['effectiveFrom'] as String),
  effectiveTo: json['effectiveTo'] == null
      ? null
      : DateTime.parse(json['effectiveTo'] as String),
  department: json['department'] == null
      ? null
      : PayrollDepartmentRef.fromJson(
          json['department'] as Map<String, dynamic>,
        ),
);

Map<String, dynamic> _$DollarRateToJson(DollarRate instance) =>
    <String, dynamic>{
      'id': instance.id,
      'departmentId': instance.departmentId,
      'dollarPerPoint': instance.dollarPerPoint,
      'effectiveFrom': instance.effectiveFrom?.toIso8601String(),
      'effectiveTo': instance.effectiveTo?.toIso8601String(),
      'department': instance.department,
    };

WorkerSummary _$WorkerSummaryFromJson(Map<String, dynamic> json) =>
    WorkerSummary(
      userId: (json['userId'] as num).toInt(),
      fullName: json['fullName'] as String,
      weekStartDate: json['weekStartDate'] as String,
      totalPoints: json['totalPoints'] == null
          ? 0
          : _parseDouble(json['totalPoints']),
      projectedEarnings: json['projectedEarnings'] == null
          ? 0
          : _parseDouble(json['projectedEarnings']),
      stepsCompleted: (json['stepsCompleted'] as num?)?.toInt() ?? 0,
      reworkCount: (json['reworkCount'] as num?)?.toInt() ?? 0,
      departments:
          (json['departments'] as List<dynamic>?)
              ?.map(
                (e) =>
                    WorkerDepartmentSummary.fromJson(e as Map<String, dynamic>),
              )
              .toList() ??
          const [],
    );

Map<String, dynamic> _$WorkerSummaryToJson(WorkerSummary instance) =>
    <String, dynamic>{
      'userId': instance.userId,
      'fullName': instance.fullName,
      'weekStartDate': instance.weekStartDate,
      'totalPoints': instance.totalPoints,
      'projectedEarnings': instance.projectedEarnings,
      'stepsCompleted': instance.stepsCompleted,
      'reworkCount': instance.reworkCount,
      'departments': instance.departments,
    };

WorkerDepartmentSummary _$WorkerDepartmentSummaryFromJson(
  Map<String, dynamic> json,
) => WorkerDepartmentSummary(
  departmentId: (json['departmentId'] as num).toInt(),
  code: json['code'] as String,
  name: json['name'] as String,
  points: json['points'] == null ? 0 : _parseDouble(json['points']),
  steps: (json['steps'] as num?)?.toInt() ?? 0,
  reworks: (json['reworks'] as num?)?.toInt() ?? 0,
  dollarPerPoint: json['dollarPerPoint'] == null
      ? 0
      : _parseDouble(json['dollarPerPoint']),
  projectedEarnings: json['projectedEarnings'] == null
      ? 0
      : _parseDouble(json['projectedEarnings']),
);

Map<String, dynamic> _$WorkerDepartmentSummaryToJson(
  WorkerDepartmentSummary instance,
) => <String, dynamic>{
  'departmentId': instance.departmentId,
  'code': instance.code,
  'name': instance.name,
  'points': instance.points,
  'steps': instance.steps,
  'reworks': instance.reworks,
  'dollarPerPoint': instance.dollarPerPoint,
  'projectedEarnings': instance.projectedEarnings,
};

WeeklyPayrollReport _$WeeklyPayrollReportFromJson(Map<String, dynamic> json) =>
    WeeklyPayrollReport(
      weekStartDate: json['weekStartDate'] as String,
      weekEndDate: json['weekEndDate'] as String,
      isLocked: json['isLocked'] as bool? ?? false,
      lockedAt: json['lockedAt'] == null
          ? null
          : DateTime.parse(json['lockedAt'] as String),
      lockedBy: json['lockedBy'] == null
          ? null
          : PayrollUserRef.fromJson(json['lockedBy'] as Map<String, dynamic>),
      workers:
          (json['workers'] as List<dynamic>?)
              ?.map(
                (e) => WeeklyPayrollWorker.fromJson(e as Map<String, dynamic>),
              )
              .toList() ??
          const [],
    );

Map<String, dynamic> _$WeeklyPayrollReportToJson(
  WeeklyPayrollReport instance,
) => <String, dynamic>{
  'weekStartDate': instance.weekStartDate,
  'weekEndDate': instance.weekEndDate,
  'isLocked': instance.isLocked,
  'lockedAt': instance.lockedAt?.toIso8601String(),
  'lockedBy': instance.lockedBy,
  'workers': instance.workers,
};

WeeklyPayrollWorker _$WeeklyPayrollWorkerFromJson(Map<String, dynamic> json) =>
    WeeklyPayrollWorker(
      userId: (json['userId'] as num).toInt(),
      fullName: json['fullName'] as String,
      email: json['email'] as String?,
      totalPoints: json['totalPoints'] == null
          ? 0
          : _parseDouble(json['totalPoints']),
      totalGrossPay: json['totalGrossPay'] == null
          ? 0
          : _parseDouble(json['totalGrossPay']),
      totalStepsCompleted: (json['totalStepsCompleted'] as num?)?.toInt() ?? 0,
      totalReworkCount: (json['totalReworkCount'] as num?)?.toInt() ?? 0,
      departments:
          (json['departments'] as List<dynamic>?)
              ?.map(
                (e) =>
                    WeeklyPayrollDepartment.fromJson(e as Map<String, dynamic>),
              )
              .toList() ??
          const [],
    );

Map<String, dynamic> _$WeeklyPayrollWorkerToJson(
  WeeklyPayrollWorker instance,
) => <String, dynamic>{
  'userId': instance.userId,
  'fullName': instance.fullName,
  'email': instance.email,
  'totalPoints': instance.totalPoints,
  'totalGrossPay': instance.totalGrossPay,
  'totalStepsCompleted': instance.totalStepsCompleted,
  'totalReworkCount': instance.totalReworkCount,
  'departments': instance.departments,
};

WeeklyPayrollDepartment _$WeeklyPayrollDepartmentFromJson(
  Map<String, dynamic> json,
) => WeeklyPayrollDepartment(
  departmentId: (json['departmentId'] as num).toInt(),
  departmentCode: json['departmentCode'] as String,
  departmentName: json['departmentName'] as String,
  totalPoints: json['totalPoints'] == null
      ? 0
      : _parseDouble(json['totalPoints']),
  stepsCompleted: (json['stepsCompleted'] as num?)?.toInt() ?? 0,
  reworkCount: (json['reworkCount'] as num?)?.toInt() ?? 0,
  dollarPerPoint: json['dollarPerPoint'] == null
      ? 0
      : _parseDouble(json['dollarPerPoint']),
  grossPay: json['grossPay'] == null ? 0 : _parseDouble(json['grossPay']),
  trailers: (json['trailers'] as List<dynamic>?)
          ?.map(
            (e) => WeeklyPayrollTrailer.fromJson(e as Map<String, dynamic>),
          )
          .toList() ??
      const <WeeklyPayrollTrailer>[],
);

Map<String, dynamic> _$WeeklyPayrollDepartmentToJson(
  WeeklyPayrollDepartment instance,
) => <String, dynamic>{
  'departmentId': instance.departmentId,
  'departmentCode': instance.departmentCode,
  'departmentName': instance.departmentName,
  'totalPoints': instance.totalPoints,
  'stepsCompleted': instance.stepsCompleted,
  'reworkCount': instance.reworkCount,
  'dollarPerPoint': instance.dollarPerPoint,
  'grossPay': instance.grossPay,
  'trailers': instance.trailers.map((e) => e.toJson()).toList(),
};

WeeklyPayrollTrailer _$WeeklyPayrollTrailerFromJson(
  Map<String, dynamic> json,
) => WeeklyPayrollTrailer(
  trailerId: json['trailerId'] as String,
  soNumber: json['soNumber'] as String,
  sizeFt: json['sizeFt'] as String?,
  modelName: json['modelName'] as String?,
  points: json['points'] == null ? 0 : _parseDouble(json['points']),
  isRework: json['isRework'] as bool? ?? false,
);

Map<String, dynamic> _$WeeklyPayrollTrailerToJson(
  WeeklyPayrollTrailer instance,
) => <String, dynamic>{
  'trailerId': instance.trailerId,
  'soNumber': instance.soNumber,
  'sizeFt': instance.sizeFt,
  'modelName': instance.modelName,
  'points': instance.points,
  'isRework': instance.isRework,
};

PayrollLockResult _$PayrollLockResultFromJson(Map<String, dynamic> json) =>
    PayrollLockResult(
      weekStartDate: json['weekStartDate'] as String,
      isLocked: json['isLocked'] as bool? ?? false,
      lockedAt: json['lockedAt'] == null
          ? null
          : DateTime.parse(json['lockedAt'] as String),
      recordsLocked: (json['recordsLocked'] as num?)?.toInt() ?? 0,
    );

Map<String, dynamic> _$PayrollLockResultToJson(PayrollLockResult instance) =>
    <String, dynamic>{
      'weekStartDate': instance.weekStartDate,
      'isLocked': instance.isLocked,
      'lockedAt': instance.lockedAt?.toIso8601String(),
      'recordsLocked': instance.recordsLocked,
    };
