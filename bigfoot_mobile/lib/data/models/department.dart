import 'package:json_annotation/json_annotation.dart';

part 'department.g.dart';

@JsonSerializable()
class Department {
  final int id;
  final String code;
  final String displayName;
  final bool isQcStep;
  final String completionType;
  final int stallThresholdHours;
  final DateTime? createdAt;

  const Department({
    required this.id,
    required this.code,
    required this.displayName,
    this.isQcStep = false,
    required this.completionType,
    this.stallThresholdHours = 48,
    this.createdAt,
  });

  factory Department.fromJson(Map<String, dynamic> json) =>
      _$DepartmentFromJson(json);
  Map<String, dynamic> toJson() => _$DepartmentToJson(this);
}

@JsonSerializable()
class WorkflowTemplate {
  final int id;
  final String series;
  final int departmentId;
  final int stepOrder;
  final String? departmentCode;
  final String? departmentName;

  const WorkflowTemplate({
    required this.id,
    required this.series,
    required this.departmentId,
    required this.stepOrder,
    this.departmentCode,
    this.departmentName,
  });

  factory WorkflowTemplate.fromJson(Map<String, dynamic> json) =>
      _$WorkflowTemplateFromJson(json);
  Map<String, dynamic> toJson() => _$WorkflowTemplateToJson(this);
}
