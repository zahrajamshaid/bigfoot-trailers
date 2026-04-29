// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'department.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Department _$DepartmentFromJson(Map<String, dynamic> json) => Department(
  id: (json['id'] as num).toInt(),
  code: json['code'] as String,
  displayName: json['displayName'] as String,
  isQcStep: json['isQcStep'] as bool? ?? false,
  completionType: json['completionType'] as String,
  stallThresholdHours: (json['stallThresholdHours'] as num?)?.toInt() ?? 48,
  createdAt: json['createdAt'] == null
      ? null
      : DateTime.parse(json['createdAt'] as String),
);

Map<String, dynamic> _$DepartmentToJson(Department instance) =>
    <String, dynamic>{
      'id': instance.id,
      'code': instance.code,
      'displayName': instance.displayName,
      'isQcStep': instance.isQcStep,
      'completionType': instance.completionType,
      'stallThresholdHours': instance.stallThresholdHours,
      'createdAt': instance.createdAt?.toIso8601String(),
    };

WorkflowTemplate _$WorkflowTemplateFromJson(Map<String, dynamic> json) =>
    WorkflowTemplate(
      id: (json['id'] as num).toInt(),
      series: json['series'] as String,
      departmentId: (json['departmentId'] as num).toInt(),
      stepOrder: (json['stepOrder'] as num).toInt(),
      departmentCode: json['departmentCode'] as String?,
      departmentName: json['departmentName'] as String?,
    );

Map<String, dynamic> _$WorkflowTemplateToJson(WorkflowTemplate instance) =>
    <String, dynamic>{
      'id': instance.id,
      'series': instance.series,
      'departmentId': instance.departmentId,
      'stepOrder': instance.stepOrder,
      'departmentCode': instance.departmentCode,
      'departmentName': instance.departmentName,
    };
