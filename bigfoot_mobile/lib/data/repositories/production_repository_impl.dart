import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/constants/api_endpoints.dart';
import '../../core/network/api_exception.dart';
import '../../core/network/dio_client.dart';
import '../../domain/repositories/production_repository.dart';
import '../models/department.dart';
import '../models/queue_item.dart';

class ProductionRepositoryImpl implements ProductionRepository {
  final DioClient _api;
  final Connectivity _connectivity;

  static const _queueFileName = 'pending_step_completions.json';
  List<_QueuedStepCompletion> _pending = const [];
  bool _queueInitialized = false;
  bool _processingQueue = false;

  ProductionRepositoryImpl({required DioClient api, Connectivity? connectivity})
      : _api = api,
        _connectivity = connectivity ?? Connectivity() {
    _initializeQueue();
  }

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
      data['checklistResults'] = checklistResults.map((r) => r.toJson()).toList();
    }

    try {
      final response = await _api.post<Map<String, dynamic>>(
        ApiEndpoints.stepComplete(stepId),
        data: data.isEmpty ? null : data,
        fromJson: (d) => d as Map<String, dynamic>,
      );
      return StepCompletionResult.fromJson(response.data!);
    } on NetworkException {
      await _enqueueStepCompletion(
        _QueuedStepCompletion(
          stepId: stepId,
          notes: notes,
          checklistResults: checklistResults ?? const [],
          queuedAtIso: DateTime.now().toIso8601String(),
        ),
      );

      return StepCompletionResult(
        completedStepId: stepId,
        pointsAwarded: 0,
        nextStepId: null,
        nextDepartment: 'Queued for sync',
        trailerStatus: 'queued_offline',
      );
    }
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

  @override
  Future<void> jumpToStep({
    required int trailerId,
    required int stepId,
    String? reason,
  }) async {
    await _api.post<Map<String, dynamic>>(
      ApiEndpoints.trailerJumpToStep(trailerId),
      data: {
        'stepId': stepId,
        if (reason != null && reason.isNotEmpty) 'reason': reason,
      },
      fromJson: (d) => d as Map<String, dynamic>,
    );
  }

  Future<void> _initializeQueue() async {
    if (_queueInitialized) return;
    _queueInitialized = true;

    await _loadQueue();

    _connectivity.onConnectivityChanged.listen((result) {
      if (result.isNotEmpty && !result.contains(ConnectivityResult.none)) {
        _processQueue();
      }
    });

    final current = await _connectivity.checkConnectivity();
    if (current.isNotEmpty && !current.contains(ConnectivityResult.none)) {
      _processQueue();
    }
  }

  Future<void> _enqueueStepCompletion(_QueuedStepCompletion item) async {
    if (Platform.isAndroid || Platform.isIOS) {
      _pending = [..._pending, item];
      await _persistQueue();
    }
  }

  Future<void> _processQueue() async {
    if (_processingQueue || _pending.isEmpty) return;
    _processingQueue = true;
    try {
      final snapshot = List<_QueuedStepCompletion>.from(_pending);
      for (final item in snapshot) {
        try {
          final data = <String, dynamic>{};
          if (item.notes != null && item.notes!.isNotEmpty) {
            data['notes'] = item.notes;
          }
          if (item.checklistResults.isNotEmpty) {
            data['checklistResults'] =
                item.checklistResults.map((e) => e.toJson()).toList();
          }

          await _api.post<Map<String, dynamic>>(
            ApiEndpoints.stepComplete(item.stepId),
            data: data.isEmpty ? null : data,
            fromJson: (d) => d as Map<String, dynamic>,
          );

          _pending = _pending.where((e) => e.localId != item.localId).toList();
          await _persistQueue();
        } on NetworkException {
          break;
        } catch (_) {
          _pending = _pending.where((e) => e.localId != item.localId).toList();
          await _persistQueue();
        }
      }
    } finally {
      _processingQueue = false;
    }
  }

  Future<File> _queueFile() async {
    final dir = await getApplicationSupportDirectory();
    return File(p.join(dir.path, _queueFileName));
  }

  Future<void> _loadQueue() async {
    final file = await _queueFile();
    if (!await file.exists()) {
      _pending = const [];
      return;
    }

    try {
      final raw = await file.readAsString();
      final decoded = jsonDecode(raw) as List<dynamic>;
      _pending = decoded
          .whereType<Map<String, dynamic>>()
          .map(_QueuedStepCompletion.fromJson)
          .toList();
    } catch (_) {
      _pending = const [];
    }
  }

  Future<void> _persistQueue() async {
    final file = await _queueFile();
    final payload = _pending.map((e) => e.toJson()).toList();
    await file.writeAsString(jsonEncode(payload), flush: true);
  }
}

class _QueuedStepCompletion {
  _QueuedStepCompletion({
    required this.stepId,
    required this.notes,
    required this.checklistResults,
    required this.queuedAtIso,
    String? localId,
  }) : localId = localId ?? '${DateTime.now().microsecondsSinceEpoch}_$stepId';

  final String localId;
  final int stepId;
  final String? notes;
  final List<StepCheckResult> checklistResults;
  final String queuedAtIso;

  Map<String, dynamic> toJson() => {
        'localId': localId,
        'stepId': stepId,
        'notes': notes,
        'checklistResults': checklistResults.map((e) => e.toJson()).toList(),
        'queuedAtIso': queuedAtIso,
      };

  factory _QueuedStepCompletion.fromJson(Map<String, dynamic> json) {
    final rawChecklist = (json['checklistResults'] as List<dynamic>? ?? const []);
    final checklist = rawChecklist
        .whereType<Map<String, dynamic>>()
        .map(
          (e) => StepCheckResult(
            checklistItemId: (e['checklistItemId'] as num).toInt(),
            passed: e['passed'] as bool? ?? false,
            note: e['note'] as String?,
          ),
        )
        .toList();

    return _QueuedStepCompletion(
      localId: json['localId']?.toString(),
      stepId: (json['stepId'] as num).toInt(),
      notes: json['notes'] as String?,
      checklistResults: checklist,
      queuedAtIso: json['queuedAtIso']?.toString() ?? DateTime.now().toIso8601String(),
    );
  }
}
