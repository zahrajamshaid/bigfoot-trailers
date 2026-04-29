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

/// Abstract contract for production queue operations.
abstract class ProductionRepository {
  Future<List<QueueItem>> getQueue(int departmentId);
  Future<List<Department>> getDepartments();
  Future<List<StepChecklistItem>> getStepChecklistItems(int stepId);
  Future<StepCompletionResult> completeStep(
    int stepId, {
    String? notes,
    List<StepCheckResult>? checklistResults,
  });
  Future<void> reverseStep(int stepId);
  Future<void> reorderQueue(int departmentId, List<int> stepIds);
}
