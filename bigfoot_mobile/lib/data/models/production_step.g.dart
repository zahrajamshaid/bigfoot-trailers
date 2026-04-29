// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'production_step.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ProductionStep _$ProductionStepFromJson(Map<String, dynamic> json) =>
    ProductionStep(
      id: (json['id'] as num).toInt(),
      trailerId: (json['trailerId'] as num).toInt(),
      departmentId: (json['departmentId'] as num).toInt(),
      stepOrder: (json['stepOrder'] as num).toInt(),
      status: json['status'] as String,
      isRework: json['isRework'] as bool? ?? false,
      reworkCount: (json['reworkCount'] as num?)?.toInt() ?? 0,
      pointsAwarded: _parseDecimalField(json['pointsAwarded']),
      completedByUserId: (json['completedByUserId'] as num?)?.toInt(),
      completedAt: json['completedAt'] == null
          ? null
          : DateTime.parse(json['completedAt'] as String),
      becameActiveAt: json['becameActiveAt'] == null
          ? null
          : DateTime.parse(json['becameActiveAt'] as String),
      completionNotes: json['completionNotes'] as String?,
      createdAt: json['createdAt'] == null
          ? null
          : DateTime.parse(json['createdAt'] as String),
      department: json['department'] == null
          ? null
          : DepartmentInfo.fromJson(json['department'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$ProductionStepToJson(ProductionStep instance) =>
    <String, dynamic>{
      'id': instance.id,
      'trailerId': instance.trailerId,
      'departmentId': instance.departmentId,
      'stepOrder': instance.stepOrder,
      'status': instance.status,
      'isRework': instance.isRework,
      'reworkCount': instance.reworkCount,
      'pointsAwarded': instance.pointsAwarded,
      'completedByUserId': instance.completedByUserId,
      'completedAt': instance.completedAt?.toIso8601String(),
      'becameActiveAt': instance.becameActiveAt?.toIso8601String(),
      'completionNotes': instance.completionNotes,
      'createdAt': instance.createdAt?.toIso8601String(),
      'department': instance.department,
    };

DepartmentInfo _$DepartmentInfoFromJson(Map<String, dynamic> json) =>
    DepartmentInfo(
      id: (json['id'] as num).toInt(),
      code: json['code'] as String,
      displayName: json['displayName'] as String,
      isQcStep: json['isQcStep'] as bool? ?? false,
      completionType: json['completionType'] as String,
      stallThresholdHours: (json['stallThresholdHours'] as num?)?.toInt() ?? 48,
    );

Map<String, dynamic> _$DepartmentInfoToJson(DepartmentInfo instance) =>
    <String, dynamic>{
      'id': instance.id,
      'code': instance.code,
      'displayName': instance.displayName,
      'isQcStep': instance.isQcStep,
      'completionType': instance.completionType,
      'stallThresholdHours': instance.stallThresholdHours,
    };
