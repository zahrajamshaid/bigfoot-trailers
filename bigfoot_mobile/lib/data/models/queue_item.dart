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
  /// True when the trailer was created without a customer attached. Combined
  /// with [soldToName] this lets the queue tile render an unambiguous
  /// ownership badge — customer order / stock build / sold-stock — without
  /// the worker having to open the trailer detail.
  final bool isStockBuild;
  /// Free-text buyer name captured when a stock build is marked sold. Only
  /// set when [isStockBuild] is true and the sale-status moved off
  /// `available`. Always null for customer-order trailers.
  final String? soldToName;
  /// Mirrors trailer.saleStatus — `available` / `sale_pending` / `sold`.
  /// Drives the ownership chip: every `sold` trailer renders as a customer
  /// chip on the queue tile regardless of where the buyer name lives
  /// (customer record vs free-text soldToName).
  final String? saleStatus;
  final String? optionsNotes;
  final String? qbSoPdfUrl;
  final String? qbSoPdfStorageKey;
  final bool isHot;
  final bool isRework;
  final int reworkCount;
  final String? reworkFailNotes;
  final int queuePosition;
  final DateTime? becameActiveAt;
  final double? hoursInQueue;
  final int globalPriority;
  /// Stall threshold for the department this step belongs to. Set by an
  /// admin on /admin/departments/:id; ships per-item so a threshold edit
  /// propagates throughout the app on the next queue refresh. Falls back
  /// to 48 when the API doesn't supply one (older builds).
  final int stallThresholdHours;

  const QueueItem({
    required this.stepId,
    required this.trailerId,
    required this.soNumber,
    this.modelName,
    this.series,
    this.color,
    this.size,
    this.customerName,
    this.isStockBuild = false,
    this.soldToName,
    this.saleStatus,
    this.optionsNotes,
    this.qbSoPdfUrl,
    this.qbSoPdfStorageKey,
    this.isHot = false,
    this.isRework = false,
    this.reworkCount = 0,
    this.reworkFailNotes,
    this.queuePosition = 0,
    this.becameActiveAt,
    this.hoursInQueue,
    this.globalPriority = 9999,
    this.stallThresholdHours = 48,
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

  /// Stall level keyed to the department's [stallThresholdHours]:
  ///   0 = ok                    (hours < threshold)
  ///   1 = warning (yellow)      (hours >= threshold)
  ///   2 = critical (red)        (hours >= 2 × threshold)
  /// Means an admin change on /admin/departments/:id propagates straight
  /// through to the queue cards without any client-side constants.
  int get stallLevel {
    final hours = calculatedHoursInQueue;
    final t = stallThresholdHours > 0 ? stallThresholdHours : 48;
    if (hours >= t * 2) return 2;
    if (hours >= t) return 1;
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
