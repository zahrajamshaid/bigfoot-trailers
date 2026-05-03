import 'package:json_annotation/json_annotation.dart';

part 'qc_inspection.g.dart';

@JsonSerializable()
class QcInspection {
  final int id;
  final int productionStepId;
  final int trailerId;
  final int inspectorId;
  final String result; // pass, fail
  final String? failNotes;
  final int? reworkTargetDeptId;
  final int attemptNumber;
  final DateTime? createdAt;

  // Expanded
  final List<QcChecklistResult>? checklistResults;
  final List<QcPhotoInfo>? photos;

  const QcInspection({
    required this.id,
    required this.productionStepId,
    required this.trailerId,
    required this.inspectorId,
    required this.result,
    this.failNotes,
    this.reworkTargetDeptId,
    this.attemptNumber = 1,
    this.createdAt,
    this.checklistResults,
    this.photos,
  });

  factory QcInspection.fromJson(Map<String, dynamic> json) =>
      _$QcInspectionFromJson(json);
  Map<String, dynamic> toJson() => _$QcInspectionToJson(this);
}

@JsonSerializable()
class QcChecklistItem {
  final int id;
  final int departmentId;
  // API field is `itemLabel` — Dart side keeps the shorter `label`.
  @JsonKey(name: 'itemLabel')
  final String label;
  final int sortOrder;
  final String appliesToSeries; // xp, yeti, deck_over, gooseneck_dump, all
  final bool isActive;

  const QcChecklistItem({
    required this.id,
    required this.departmentId,
    required this.label,
    this.sortOrder = 0,
    this.appliesToSeries = 'all',
    this.isActive = true,
  });

  factory QcChecklistItem.fromJson(Map<String, dynamic> json) =>
      _$QcChecklistItemFromJson(json);
  Map<String, dynamic> toJson() => _$QcChecklistItemToJson(this);
}

@JsonSerializable()
class QcChecklistResult {
  final int id;
  final int checklistItemId;
  final bool passed;
  final String? note;

  const QcChecklistResult({
    required this.id,
    required this.checklistItemId,
    required this.passed,
    this.note,
  });

  factory QcChecklistResult.fromJson(Map<String, dynamic> json) =>
      _$QcChecklistResultFromJson(json);
  Map<String, dynamic> toJson() => _$QcChecklistResultToJson(this);
}

@JsonSerializable()
class QcPhotoInfo {
  final int id;
  final String storageKey;
  final String? downloadUrl;

  const QcPhotoInfo({
    required this.id,
    required this.storageKey,
    this.downloadUrl,
  });

  factory QcPhotoInfo.fromJson(Map<String, dynamic> json) =>
      _$QcPhotoInfoFromJson(json);
  Map<String, dynamic> toJson() => _$QcPhotoInfoToJson(this);
}
