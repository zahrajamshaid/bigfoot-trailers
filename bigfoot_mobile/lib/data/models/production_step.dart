import 'package:json_annotation/json_annotation.dart';

part 'production_step.g.dart';

// Prisma serializes Decimal fields as strings — parse either String or num.
double? _parseDecimalField(dynamic v) =>
    v == null ? null : double.tryParse(v.toString());

@JsonSerializable()
class ProductionStep {
  final int id;
  final int trailerId;
  final int departmentId;
  final int stepOrder;
  final String status; // waiting, active, complete, rework
  final bool isRework;
  final int reworkCount;
  @JsonKey(fromJson: _parseDecimalField)
  final double? pointsAwarded;
  final int? completedByUserId;
  final DateTime? completedAt;
  final DateTime? becameActiveAt;
  final String? completionNotes;
  final DateTime? createdAt;

  // Expanded
  final DepartmentInfo? department;

  const ProductionStep({
    required this.id,
    required this.trailerId,
    required this.departmentId,
    required this.stepOrder,
    required this.status,
    this.isRework = false,
    this.reworkCount = 0,
    this.pointsAwarded,
    this.completedByUserId,
    this.completedAt,
    this.becameActiveAt,
    this.completionNotes,
    this.createdAt,
    this.department,
  });

  factory ProductionStep.fromJson(Map<String, dynamic> json) =>
      _$ProductionStepFromJson(json);
  Map<String, dynamic> toJson() => _$ProductionStepToJson(this);
}

@JsonSerializable()
class DepartmentInfo {
  final int id;
  final String code;
  final String displayName;
  final bool isQcStep;
  final String completionType;
  final int stallThresholdHours;

  const DepartmentInfo({
    required this.id,
    required this.code,
    required this.displayName,
    this.isQcStep = false,
    required this.completionType,
    this.stallThresholdHours = 48,
  });

  factory DepartmentInfo.fromJson(Map<String, dynamic> json) =>
      _$DepartmentInfoFromJson(json);
  Map<String, dynamic> toJson() => _$DepartmentInfoToJson(this);
}
