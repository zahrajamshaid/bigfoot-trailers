import '../../data/models/department.dart';
import '../../data/models/queue_item.dart';

class StepChecklistItem {
  final int id;
  final String label;
  final int sortOrder;

  const StepChecklistItem({
    required this.id,
    required this.label,
    this.sortOrder = 0,
  });

  factory StepChecklistItem.fromJson(Map<String, dynamic> json) {
    return StepChecklistItem(
      id: (json['id'] as num).toInt(),
      label: (json['itemLabel'] ?? json['item_label'] ?? json['label'] ?? '')
          .toString(),
      sortOrder: (json['sortOrder'] ?? json['sort_order'] ?? 0) is num
          ? ((json['sortOrder'] ?? json['sort_order'] ?? 0) as num).toInt()
          : 0,
    );
  }
}

class StepCheckResult {
  final int checklistItemId;
  final bool passed;
  final String? note;

  const StepCheckResult({
    required this.checklistItemId,
    required this.passed,
    this.note,
  });

  Map<String, dynamic> toJson() => {
        'checklistItemId': checklistItemId,
        'passed': passed,
        if (note != null && note!.isNotEmpty) 'note': note,
      };
}

/// Manual pay bonuses captured at completion for specific departments:
/// WIRE (hydraulic jack / toolbox), PAINT (ramp jacks), WOOD (tire swaps).
class PayAdjustments {
  /// 'single' | 'double' | 'ramps_jack' | null
  final String? hydraulicJack;
  final bool toolbox;
  final int rampJacks;
  final int tireSwaps;

  const PayAdjustments({
    this.hydraulicJack,
    this.toolbox = false,
    this.rampJacks = 0,
    this.tireSwaps = 0,
  });

  bool get isEmpty =>
      hydraulicJack == null && !toolbox && rampJacks == 0 && tireSwaps == 0;

  Map<String, dynamic> toJson() => {
        if (hydraulicJack != null) 'hydraulicJack': hydraulicJack,
        if (toolbox) 'toolbox': true,
        if (rampJacks > 0) 'rampJacks': rampJacks,
        if (tireSwaps > 0) 'tireSwaps': tireSwaps,
      };
}

/// Abstract contract for production queue operations.
abstract class ProductionRepository {
  Future<List<QueueItem>> getQueue(int departmentId);
  Future<List<Department>> getDepartments();
  Future<List<StepChecklistItem>> getStepChecklistItems(int stepId);
  Future<StepCompletionResult> completeStep(
    int stepId, {
    String? notes,
    List<StepCheckResult>? checklistResults,
    PayAdjustments? payAdjustments,
  });
  Future<void> reverseStep(int stepId);
  Future<void> reorderQueue(int departmentId, List<int> stepIds);

  /// Admin override: place a trailer at an arbitrary production step. Earlier
  /// steps are forced to `complete`, the target becomes `active`, later steps
  /// are reset to `waiting`. Backend rejects 403 unless the caller is owner
  /// or production_manager.
  Future<void> jumpToStep({
    required int trailerId,
    required int stepId,
    String? reason,
  });
}
