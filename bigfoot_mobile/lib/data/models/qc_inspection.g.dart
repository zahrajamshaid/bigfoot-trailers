// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'qc_inspection.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

QcInspection _$QcInspectionFromJson(Map<String, dynamic> json) => QcInspection(
  id: (json['id'] as num).toInt(),
  productionStepId: (json['productionStepId'] as num).toInt(),
  trailerId: (json['trailerId'] as num).toInt(),
  inspectorId: (json['inspectorId'] as num).toInt(),
  result: json['result'] as String,
  failNotes: json['failNotes'] as String?,
  reworkTargetDeptId: (json['reworkTargetDeptId'] as num?)?.toInt(),
  attemptNumber: (json['attemptNumber'] as num?)?.toInt() ?? 1,
  createdAt: json['createdAt'] == null
      ? null
      : DateTime.parse(json['createdAt'] as String),
  checklistResults: (json['checklistResults'] as List<dynamic>?)
      ?.map((e) => QcChecklistResult.fromJson(e as Map<String, dynamic>))
      .toList(),
  photos: (json['photos'] as List<dynamic>?)
      ?.map((e) => QcPhotoInfo.fromJson(e as Map<String, dynamic>))
      .toList(),
);

Map<String, dynamic> _$QcInspectionToJson(QcInspection instance) =>
    <String, dynamic>{
      'id': instance.id,
      'productionStepId': instance.productionStepId,
      'trailerId': instance.trailerId,
      'inspectorId': instance.inspectorId,
      'result': instance.result,
      'failNotes': instance.failNotes,
      'reworkTargetDeptId': instance.reworkTargetDeptId,
      'attemptNumber': instance.attemptNumber,
      'createdAt': instance.createdAt?.toIso8601String(),
      'checklistResults': instance.checklistResults,
      'photos': instance.photos,
    };

QcChecklistItem _$QcChecklistItemFromJson(Map<String, dynamic> json) =>
    QcChecklistItem(
      id: (json['id'] as num).toInt(),
      departmentId: (json['departmentId'] as num).toInt(),
      label: json['itemLabel'] as String,
      sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
      appliesToSeries: json['appliesToSeries'] as String? ?? 'all',
      isActive: json['isActive'] as bool? ?? true,
    );

Map<String, dynamic> _$QcChecklistItemToJson(QcChecklistItem instance) =>
    <String, dynamic>{
      'id': instance.id,
      'departmentId': instance.departmentId,
      'itemLabel': instance.label,
      'sortOrder': instance.sortOrder,
      'appliesToSeries': instance.appliesToSeries,
      'isActive': instance.isActive,
    };

QcChecklistResult _$QcChecklistResultFromJson(Map<String, dynamic> json) =>
    QcChecklistResult(
      id: (json['id'] as num).toInt(),
      checklistItemId: (json['checklistItemId'] as num).toInt(),
      passed: json['passed'] as bool,
      note: json['note'] as String?,
    );

Map<String, dynamic> _$QcChecklistResultToJson(QcChecklistResult instance) =>
    <String, dynamic>{
      'id': instance.id,
      'checklistItemId': instance.checklistItemId,
      'passed': instance.passed,
      'note': instance.note,
    };

QcPhotoInfo _$QcPhotoInfoFromJson(Map<String, dynamic> json) => QcPhotoInfo(
  id: (json['id'] as num).toInt(),
  storageKey: json['storageKey'] as String,
  downloadUrl: json['downloadUrl'] as String?,
);

Map<String, dynamic> _$QcPhotoInfoToJson(QcPhotoInfo instance) =>
    <String, dynamic>{
      'id': instance.id,
      'storageKey': instance.storageKey,
      'downloadUrl': instance.downloadUrl,
    };
