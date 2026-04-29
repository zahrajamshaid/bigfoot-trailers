// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'queue_item.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

QueueItem _$QueueItemFromJson(Map<String, dynamic> json) => QueueItem(
  stepId: (json['stepId'] as num).toInt(),
  trailerId: (json['trailerId'] as num).toInt(),
  soNumber: json['soNumber'] as String,
  modelName: json['modelName'] as String?,
  series: json['series'] as String?,
  color: json['color'] as String?,
  size: json['sizeFt'] as String?,
  customerName: json['customerName'] as String?,
  optionsNotes: json['optionsNotes'] as String?,
  qbSoPdfUrl: json['qbSoPdfUrl'] as String?,
  isHot: json['isHot'] as bool? ?? false,
  isRework: json['isRework'] as bool? ?? false,
  reworkCount: (json['reworkCount'] as num?)?.toInt() ?? 0,
  reworkFailNotes: json['reworkFailNotes'] as String?,
  queuePosition: (json['queuePosition'] as num?)?.toInt() ?? 0,
  becameActiveAt: json['becameActiveAt'] == null
      ? null
      : DateTime.parse(json['becameActiveAt'] as String),
  hoursInQueue: (json['hoursInQueue'] as num?)?.toDouble(),
  globalPriority: (json['globalPriority'] as num?)?.toInt() ?? 9999,
);

Map<String, dynamic> _$QueueItemToJson(QueueItem instance) => <String, dynamic>{
  'stepId': instance.stepId,
  'trailerId': instance.trailerId,
  'soNumber': instance.soNumber,
  'modelName': instance.modelName,
  'series': instance.series,
  'color': instance.color,
  'sizeFt': instance.size,
  'customerName': instance.customerName,
  'optionsNotes': instance.optionsNotes,
  'qbSoPdfUrl': instance.qbSoPdfUrl,
  'isHot': instance.isHot,
  'isRework': instance.isRework,
  'reworkCount': instance.reworkCount,
  'reworkFailNotes': instance.reworkFailNotes,
  'queuePosition': instance.queuePosition,
  'becameActiveAt': instance.becameActiveAt?.toIso8601String(),
  'hoursInQueue': instance.hoursInQueue,
  'globalPriority': instance.globalPriority,
};

StepCompletionResult _$StepCompletionResultFromJson(
  Map<String, dynamic> json,
) => StepCompletionResult(
  completedStepId: (json['completedStepId'] as num).toInt(),
  pointsAwarded: (json['pointsAwarded'] as num).toDouble(),
  nextStepId: (json['nextStepId'] as num?)?.toInt(),
  nextDepartment: json['nextDepartment'] as String?,
  trailerStatus: json['trailerStatus'] as String,
);

Map<String, dynamic> _$StepCompletionResultToJson(
  StepCompletionResult instance,
) => <String, dynamic>{
  'completedStepId': instance.completedStepId,
  'pointsAwarded': instance.pointsAwarded,
  'nextStepId': instance.nextStepId,
  'nextDepartment': instance.nextDepartment,
  'trailerStatus': instance.trailerStatus,
};
