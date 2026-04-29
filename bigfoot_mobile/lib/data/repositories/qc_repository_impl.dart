import 'package:dio/dio.dart';

import '../../core/constants/api_endpoints.dart';
import '../../core/network/dio_client.dart';
import '../../domain/repositories/qc_repository.dart';
import '../models/department.dart';
import '../models/qc_inspection.dart';

class QcRepositoryImpl implements QcRepository {
  final DioClient _api;

  QcRepositoryImpl({required DioClient api}) : _api = api;

  @override
  Future<Map<String, List<QcQueueItem>>> getQcQueues() async {
    final deptResp = await _api.get<List<dynamic>>(
      ApiEndpoints.productionDepartments,
      fromJson: (d) => d as List<dynamic>,
    );
    final qcDepts = (deptResp.data ?? [])
        .whereType<Map<String, dynamic>>()
        .map(Department.fromJson)
        .where((d) => d.isQcStep)
        .toList();

    final grouped = <String, List<QcQueueItem>>{};
    for (final dept in qcDepts) {
      final resp = await _api.get<List<dynamic>>(
        ApiEndpoints.productionQueue(dept.id),
        queryParameters: const {'includeWaiting': 'true'},
        fromJson: (d) => d as List<dynamic>,
      );
      final items = (resp.data ?? [])
          .whereType<Map<String, dynamic>>()
          .map((json) {
        json['departmentId'] = dept.id;
        json['departmentCode'] = dept.code;
        json['departmentName'] = dept.displayName;
        return QcQueueItem.fromJson(json);
      }).toList();
      if (items.isNotEmpty) {
        grouped[dept.code] = items;
      }
    }

    return grouped;
  }

  @override
  Future<List<QcChecklistItem>> getChecklistItems({
    required int departmentId,
    String? series,
    int? trailerId,
  }) async {
    final params = <String, dynamic>{'departmentId': departmentId};
    if (series != null) params['series'] = series;
    if (trailerId != null) params['trailerId'] = trailerId;

    final resp = await _api.get<List<dynamic>>(
      ApiEndpoints.qcChecklistItems,
      queryParameters: params,
      fromJson: (d) => d as List<dynamic>,
    );
    return (resp.data ?? [])
        .whereType<Map<String, dynamic>>()
        .map(QcChecklistItem.fromJson)
        .where((i) => i.isActive)
        .toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  }

  @override
  Future<List<Department>> getReworkTargets(int trailerId) async {
    final deptResp = await _api.get<List<dynamic>>(
      ApiEndpoints.productionDepartments,
      fromJson: (d) => d as List<dynamic>,
    );
    final allDepts = (deptResp.data ?? [])
        .whereType<Map<String, dynamic>>()
        .map(Department.fromJson)
        .toList();

    try {
      final stepsResp = await _api.get<List<dynamic>>(
        ApiEndpoints.trailerSteps(trailerId),
        fromJson: (d) => d as List<dynamic>,
      );

      final deptIds = <int>{};
      for (final raw in (stepsResp.data ?? [])) {
        if (raw is! Map<String, dynamic>) continue;
        final nestedDept = raw['department'];
        final deptId = (raw['departmentId'] as int?) ??
            (raw['department_id'] as int?) ??
            (nestedDept is Map<String, dynamic> ? (nestedDept['id'] as int?) : null);
        final isQcStep = (raw['isQcStep'] as bool?) ??
            (raw['is_qc_step'] as bool?) ??
            (nestedDept is Map<String, dynamic>
                ? ((nestedDept['isQcStep'] as bool?) ?? (nestedDept['is_qc_step'] as bool?))
                : null) ??
            false;

        if (deptId != null && !isQcStep) {
          deptIds.add(deptId);
        }
      }

      final targets = allDepts
          .where((d) => deptIds.contains(d.id) && !d.isQcStep)
          .toList()
        ..sort((a, b) => a.code.compareTo(b.code));

      if (targets.isNotEmpty) return targets;
    } catch (_) {}

    return allDepts.where((d) => !d.isQcStep).toList()
      ..sort((a, b) => a.code.compareTo(b.code));
  }

  @override
  Future<QcInspectionResult> submitInspection({
    required int productionStepId,
    required String result,
    String? failNotes,
    int? reworkTargetDepartmentId,
    required List<Map<String, dynamic>> checklistResults,
    required List<String> photoStorageKeys,
  }) async {
    final data = <String, dynamic>{
      'productionStepId': productionStepId,
      'result': result,
      'checklistResults': checklistResults,
      'photoStorageKeys': photoStorageKeys,
    };
    if (result == 'fail') {
      data['failNotes'] = failNotes;
      data['reworkTargetDepartmentId'] = reworkTargetDepartmentId;
    }

    final resp = await _api.post<Map<String, dynamic>>(
      ApiEndpoints.qcInspections,
      data: data,
      fromJson: (d) => d as Map<String, dynamic>,
    );

    return QcInspectionResult.fromJson(resp.data!);
  }

  @override
  Future<QcInspection> getInspection(int id) async {
    final resp = await _api.get<Map<String, dynamic>>(
      ApiEndpoints.qcInspection(id),
      fromJson: (d) => d as Map<String, dynamic>,
    );
    return QcInspection.fromJson(resp.data!);
  }

  @override
  Future<List<QcInspection>> getInspectionsForStep(int stepId) async {
    final resp = await _api.get<List<dynamic>>(
      ApiEndpoints.qcInspectionsForStep(stepId),
      fromJson: (d) => d as List<dynamic>,
    );
    return (resp.data ?? [])
        .whereType<Map<String, dynamic>>()
        .map(QcInspection.fromJson)
        .toList();
  }

  @override
  Future<String> uploadPhoto(List<int> bytes, String filename) async {
    final resp = await _api.post<Map<String, dynamic>>(
      ApiEndpoints.storagePresign,
      data: {
        'filename': filename,
        'contentType': 'image/jpeg',
        'folder': 'qc-photos',
      },
      fromJson: (d) => d as Map<String, dynamic>,
    );
    final uploadUrl = resp.data!['uploadUrl'] as String? ?? resp.data!['upload_url'] as String;
    final storageKey = resp.data!['storageKey'] as String? ?? resp.data!['storage_key'] as String;

    await _api.dio.put(
      uploadUrl,
      data: bytes,
      options: Options(headers: {
        'Content-Type': 'image/jpeg',
        'Content-Length': bytes.length,
      }),
    );

    return storageKey;
  }

  @override
  Future<List<QcChecklistItem>> getAllChecklistItems() async {
    final resp = await _api.get<List<dynamic>>(
      ApiEndpoints.qcChecklistItems,
      fromJson: (d) => d as List<dynamic>,
    );
    return (resp.data ?? [])
        .whereType<Map<String, dynamic>>()
        .map(QcChecklistItem.fromJson)
        .toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  }

  @override
  Future<void> createChecklistItem({
    required int departmentId,
    required String label,
    int sortOrder = 0,
    String appliesToSeries = 'all',
  }) async {
    await _api.post(
      ApiEndpoints.qcChecklistItems,
      data: {
        'departmentId': departmentId,
        'label': label,
        'sortOrder': sortOrder,
        'appliesToSeries': appliesToSeries,
      },
    );
  }

  @override
  Future<void> updateChecklistItem(int id, {String? label, int? sortOrder, bool? isActive}) async {
    final data = <String, dynamic>{};
    if (label != null) data['label'] = label;
    if (sortOrder != null) data['sortOrder'] = sortOrder;
    if (isActive != null) data['isActive'] = isActive;

    await _api.patch('${ApiEndpoints.qcChecklistItems}/$id', data: data);
  }

  @override
  Future<void> sendCustomerSms(int inspectionId) async {
    await _api.post(ApiEndpoints.qcInspectionSendSms(inspectionId));
  }

  @override
  Future<List<UpstreamCheck>> getUpstreamChecksForTrailer(int trailerId) async {
    final resp = await _api.get<List<dynamic>>(
      ApiEndpoints.trailerUpstreamChecks(trailerId),
      fromJson: (d) => d as List<dynamic>,
    );
    return (resp.data ?? [])
        .whereType<Map<String, dynamic>>()
        .map(UpstreamCheck.fromJson)
        .toList();
  }
}
