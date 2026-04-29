import '../../core/constants/api_endpoints.dart';
import '../../core/network/dio_client.dart';
import '../../domain/repositories/production_repository.dart';
import '../models/department.dart';
import '../models/queue_item.dart';

class ProductionRepositoryImpl implements ProductionRepository {
  final DioClient _api;

  ProductionRepositoryImpl({required DioClient api}) : _api = api;

  @override
  Future<List<QueueItem>> getQueue(int departmentId) async {
    final response = await _api.get<List<dynamic>>(
      ApiEndpoints.productionQueue(departmentId),
      fromJson: (d) => d as List<dynamic>,
    );
    return (response.data ?? [])
        .whereType<Map<String, dynamic>>()
        .map(QueueItem.fromJson)
        .toList();
  }

  @override
  Future<List<Department>> getDepartments() async {
    try {
      final response = await _api.get<List<dynamic>>(
        ApiEndpoints.adminDepartments,
        fromJson: (d) => d as List<dynamic>,
      );
      return (response.data ?? [])
          .whereType<Map<String, dynamic>>()
          .map(Department.fromJson)
          .toList();
    } catch (_) {
      return [];
    }
  }

  @override
  Future<List<StepChecklistItem>> getStepChecklistItems(int stepId) async {
    final response = await _api.get<List<dynamic>>(
      ApiEndpoints.stepChecklistItems(stepId),
      fromJson: (d) => d as List<dynamic>,
    );
    return (response.data ?? [])
        .whereType<Map<String, dynamic>>()
        .map(StepChecklistItem.fromJson)
        .toList();
  }

  @override
  Future<StepCompletionResult> completeStep(
    int stepId, {
    String? notes,
    List<StepCheckResult>? checklistResults,
  }) async {
    final data = <String, dynamic>{};
    if (notes != null && notes.isNotEmpty) data['notes'] = notes;
    if (checklistResults != null && checklistResults.isNotEmpty) {
      data['checklistResults'] =
          checklistResults.map((r) => r.toJson()).toList();
    }

    final response = await _api.post<Map<String, dynamic>>(
      ApiEndpoints.stepComplete(stepId),
      data: data.isEmpty ? null : data,
      fromJson: (d) => d as Map<String, dynamic>,
    );

    return StepCompletionResult.fromJson(response.data!);
  }

  @override
  Future<void> reverseStep(int stepId) async {
    await _api.post<Map<String, dynamic>>(
      ApiEndpoints.stepReverse(stepId),
      fromJson: (d) => d as Map<String, dynamic>,
    );
  }

  @override
  Future<void> reorderQueue(int departmentId, List<int> stepIds) async {
    await _api.patch<Map<String, dynamic>>(
      ApiEndpoints.reorderQueue(departmentId),
      data: {'stepIds': stepIds},
      fromJson: (d) => d as Map<String, dynamic>,
    );
  }
}
