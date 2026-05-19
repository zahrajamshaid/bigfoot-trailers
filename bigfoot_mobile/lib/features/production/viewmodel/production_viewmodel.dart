import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/websocket/ws_client.dart';
import '../../../core/websocket/ws_events.dart';
import '../../../data/models/department.dart';
import '../../../data/models/queue_item.dart';
import '../../../domain/repositories/production_repository.dart';

// ── States ───────────────────────────────────────────────────────────────────

sealed class ProductionQueueState extends Equatable {
  const ProductionQueueState();
  @override
  List<Object?> get props => [];
}

class ProductionQueueInitial extends ProductionQueueState {
  const ProductionQueueInitial();
}

class ProductionQueueLoading extends ProductionQueueState {
  const ProductionQueueLoading();
}

class ProductionQueueLoaded extends ProductionQueueState {
  final List<QueueItem> queue;
  final int departmentId;
  final String? departmentName;
  final List<Department> departments;
  final bool isRefreshing;
  final StepCompletionResult? lastCompletion;

  /// When true the UI shows only stalled items (stallLevel > 0). Set by the
  /// "Stalled only" filter chip or a `?filter=stalled` deep link.
  final bool stalledOnly;

  const ProductionQueueLoaded({
    required this.queue,
    required this.departmentId,
    this.departmentName,
    this.departments = const [],
    this.isRefreshing = false,
    this.lastCompletion,
    this.stalledOnly = false,
  });

  /// The queue after the stalled filter is applied — what the list renders.
  List<QueueItem> get visibleQueue =>
      stalledOnly ? queue.where((q) => q.stallLevel > 0).toList() : queue;

  ProductionQueueLoaded copyWith({
    List<QueueItem>? queue,
    int? departmentId,
    String? departmentName,
    List<Department>? departments,
    bool? isRefreshing,
    StepCompletionResult? lastCompletion,
    bool? stalledOnly,
  }) {
    return ProductionQueueLoaded(
      queue: queue ?? this.queue,
      departmentId: departmentId ?? this.departmentId,
      departmentName: departmentName ?? this.departmentName,
      departments: departments ?? this.departments,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      lastCompletion: lastCompletion,
      stalledOnly: stalledOnly ?? this.stalledOnly,
    );
  }

  @override
  List<Object?> get props => [
        queue,
        departmentId,
        departmentName,
        departments,
        isRefreshing,
        lastCompletion,
        stalledOnly,
      ];
}

class ProductionQueueError extends ProductionQueueState {
  final String message;
  const ProductionQueueError(this.message);
  @override
  List<Object?> get props => [message];
}

// ── ViewModel ────────────────────────────────────────────────────────────────

class ProductionViewModel extends Cubit<ProductionQueueState> {
  final ProductionRepository _repository;
  final WsClient _ws;
  StreamSubscription<WsEvent>? _wsSub;

  ProductionViewModel({required ProductionRepository repository, required WsClient ws})
      : _repository = repository,
        _ws = ws,
        super(const ProductionQueueInitial()) {
    _wsSub = _ws.events.listen(_onWsEvent);
  }

  Future<void> load(
    int? departmentId, {
    bool isManager = false,
    bool stalledOnly = false,
  }) async {
    emit(const ProductionQueueLoading());
    try {
      List<Department> departments = [];
      if (isManager) {
        departments = await _repository.getDepartments();
      }

      int? resolvedDepartmentId = departmentId;
      if (resolvedDepartmentId == null && isManager) {
        final productionDepartments = departments.where((d) => !d.isQcStep).toList();
        resolvedDepartmentId =
            productionDepartments.firstOrNull?.id ?? departments.firstOrNull?.id;
      }

      if (resolvedDepartmentId == null) {
        emit(const ProductionQueueError(
          'No department is assigned to this account. Please contact admin.',
        ));
        return;
      }

      final queue = await _repository.getQueue(resolvedDepartmentId);
      final deptName = departments.isEmpty
          ? null
          : departments
              .where((d) => d.id == resolvedDepartmentId)
              .map((d) => d.displayName)
              .firstOrNull;

      emit(ProductionQueueLoaded(
        queue: queue,
        departmentId: resolvedDepartmentId,
        departmentName: deptName,
        departments: departments,
        stalledOnly: stalledOnly,
      ));
    } on ApiException catch (e) {
      emit(ProductionQueueError(e.displayMessage));
    } on NetworkException catch (e) {
      emit(ProductionQueueError(e.message));
    } catch (_) {
      emit(const ProductionQueueError('Failed to load production queue'));
    }
  }

  Future<void> switchDepartment(int departmentId) async {
    final current = state;
    if (current is! ProductionQueueLoaded) return;

    emit(current.copyWith(isRefreshing: true));
    try {
      final queue = await _repository.getQueue(departmentId);
      final deptName = current.departments
          .where((d) => d.id == departmentId)
          .map((d) => d.displayName)
          .firstOrNull;
      emit(ProductionQueueLoaded(
        queue: queue,
        departmentId: departmentId,
        departmentName: deptName,
        departments: current.departments,
        stalledOnly: current.stalledOnly,
      ));
    } catch (_) {
      emit(current.copyWith(isRefreshing: false));
    }
  }

  /// Toggles the "stalled only" view filter without re-fetching the queue.
  void setStalledOnly(bool value) {
    final current = state;
    if (current is ProductionQueueLoaded) {
      emit(current.copyWith(stalledOnly: value));
    }
  }

  Future<void> refresh() async {
    final current = state;
    if (current is! ProductionQueueLoaded) return;

    emit(current.copyWith(isRefreshing: true));
    try {
      final queue = await _repository.getQueue(current.departmentId);
      emit(current.copyWith(queue: queue, isRefreshing: false));
    } catch (_) {
      emit(current.copyWith(isRefreshing: false));
    }
  }

  Future<StepCompletionResult?> completeStep(
    int stepId, {
    String? notes,
    List<StepCheckResult>? checklistResults,
  }) async {
    try {
      final result = await _repository.completeStep(
        stepId,
        notes: notes,
        checklistResults: checklistResults,
      );

      final current = state;
      if (current is ProductionQueueLoaded) {
        final updatedQueue = current.queue.where((q) => q.stepId != stepId).toList();
        emit(current.copyWith(queue: updatedQueue, lastCompletion: result));
      }

      return result;
    } on ApiException {
      rethrow;
    }
  }

  Future<List<StepChecklistItem>> loadStepChecklist(int stepId) =>
      _repository.getStepChecklistItems(stepId);

  Future<void> reverseStep(int stepId) async {
    try {
      await _repository.reverseStep(stepId);
      await refresh();
    } on ApiException {
      rethrow;
    }
  }

  Future<void> reorderQueue(int departmentId, List<int> stepIds) async {
    try {
      await _repository.reorderQueue(departmentId, stepIds);
      await refresh();
    } on ApiException {
      rethrow;
    }
  }

  void clearLastCompletion() {
    final current = state;
    if (current is ProductionQueueLoaded) {
      emit(current.copyWith());
    }
  }

  void _onWsEvent(WsEvent event) {
    final current = state;
    if (current is! ProductionQueueLoaded) return;

    if ([
      WsEventType.stepCompleted,
      WsEventType.stepReversed,
      WsEventType.qcPass,
      WsEventType.qcFail,
      WsEventType.queueReordered,
      WsEventType.priorityChanged,
    ].contains(event.type)) {
      final eventDeptId = event.departmentId;
      if (eventDeptId == null || eventDeptId == current.departmentId) {
        refresh();
      }
    }
  }

  @override
  Future<void> close() {
    _wsSub?.cancel();
    return super.close();
  }
}
