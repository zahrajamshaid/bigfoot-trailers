import 'package:json_annotation/json_annotation.dart';

part 'queue_item.g.dart';

/// A single item in a department production queue.
/// Maps to GET /production/queue/:dept_id response shape.
@JsonSerializable()
class QueueItem {
  final int stepId;
  final int trailerId;
  final String soNumber;
  final String? modelName;
  final String? series;
  final String? color;
  @JsonKey(name: 'sizeFt')
  final String? size;
  final String? customerName;
  final String? optionsNotes;
  final String? qbSoPdfUrl;
  final bool isHot;
  final bool isRework;
  final int reworkCount;
  final String? reworkFailNotes;
  final int queuePosition;
  final DateTime? becameActiveAt;
  final double? hoursInQueue;
  final int globalPriority;

  const QueueItem({
    required this.stepId,
    required this.trailerId,
    required this.soNumber,
    this.modelName,
    this.series,
    this.color,
    this.size,
    this.customerName,
    this.optionsNotes,
    this.qbSoPdfUrl,
    this.isHot = false,
    this.isRework = false,
    this.reworkCount = 0,
    this.reworkFailNotes,
    this.queuePosition = 0,
    this.becameActiveAt,
    this.hoursInQueue,
    this.globalPriority = 9999,
  });

  factory QueueItem.fromJson(Map<String, dynamic> json) =>
      _$QueueItemFromJson(json);
  Map<String, dynamic> toJson() => _$QueueItemToJson(this);

  /// Hours since became active (calculated client-side as fallback).
  double get calculatedHoursInQueue {
    if (hoursInQueue != null) return hoursInQueue!;
    if (becameActiveAt == null) return 0;
    return DateTime.now().difference(becameActiveAt!).inMinutes / 60.0;
  }

  /// Stall level: 0 = ok, 1 = warning (>24h), 2 = critical (>48h).
  int get stallLevel {
    final hours = calculatedHoursInQueue;
    if (hours > 48) return 2;
    if (hours > 24) return 1;
    return 0;
  }
}

/// Response from POST /production/steps/:step_id/complete.
@JsonSerializable()
class StepCompletionResult {
  final int completedStepId;
  final double pointsAwarded;
  final int? nextStepId;
  final String? nextDepartment;
  final String trailerStatus;

  const StepCompletionResult({
    required this.completedStepId,
    required this.pointsAwarded,
    this.nextStepId,
    this.nextDepartment,
    required this.trailerStatus,
  });

  factory StepCompletionResult.fromJson(Map<String, dynamic> json) =>
      _$StepCompletionResultFromJson(json);
  Map<String, dynamic> toJson() => _$StepCompletionResultToJson(this);
}
