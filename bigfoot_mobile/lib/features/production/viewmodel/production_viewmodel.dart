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

  /// The queue after the stalled filter is applied and the priority sort
  /// has run — what the list actually renders.
  ///
  /// Tiered priority order, requested by ops:
  ///   1. Rework trailers come first (a failed inspection has to be
  ///      handled before anything else).
  ///   2. Hot trailers (truly urgent).
  ///   3. Trailers with an explicit global priority set (used for
  ///      "important but not hot" overrides — lower number = more
  ///      urgent within this tier).
  ///   4. Stalled trailers (critical before warning, then by stalled
  ///      duration).
  ///   5. Everything else, oldest `becameActiveAt` first — a unit
  ///      that's been sitting for three days outranks a unit that's
  ///      been there five minutes.
  List<QueueItem> get visibleQueue {
    final filtered =
        stalledOnly ? queue.where((q) => q.stallLevel > 0).toList() : [...queue];
    filtered.sort(_byPriority);
    return filtered;
  }

  static int _byPriority(QueueItem a, QueueItem b) {
    // 1. Rework
    if (a.isRework != b.isRework) return a.isRework ? -1 : 1;
    // 2. Hot
    if (a.isHot != b.isHot) return a.isHot ? -1 : 1;
    // 3. Explicit priority (anything < the 9999 default counts as set).
    final aHasPriority = a.globalPriority < 9999;
    final bHasPriority = b.globalPriority < 9999;
    if (aHasPriority != bHasPriority) return aHasPriority ? -1 : 1;
    if (aHasPriority && bHasPriority) {
      // Lower number = more urgent within this tier.
      final cmp = a.globalPriority.compareTo(b.globalPriority);
      if (cmp != 0) return cmp;
    }
    // 4. Stalled (level 2 = critical/red before level 1 = warning/yellow).
    if (a.stallLevel != b.stallLevel) return b.stallLevel.compareTo(a.stallLevel);
    // 5. Oldest becameActiveAt first; items with no timestamp sink to the
    //    bottom so an unstamped row doesn't accidentally outrank everyone.
    final aAt = a.becameActiveAt;
    final bAt = b.becameActiveAt;
    if (aAt == null && bAt == null) return 0;
    if (aAt == null) return 1;
    if (bAt == null) return -1;
    return aAt.compareTo(bAt);
  }

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
    List<int> allowedDepartmentIds = const <int>[],
  }) async {
    emit(const ProductionQueueLoading());
    try {
      // Fetch the full department catalog whenever there's a choice to be made:
      // managers can switch to anything; multi-dept "master" workers can switch
      // between their primary + extras. Normal single-dept workers don't need
      // it and we skip the round-trip.
      final hasMultipleAllowed = allowedDepartmentIds.length > 1;
      List<Department> departments = [];
      if (isManager || hasMultipleAllowed) {
        final all = await _repository.getDepartments();
        departments = isManager
            ? all
            : all.where((d) => allowedDepartmentIds.contains(d.id)).toList();
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

    // Anything that can change what's in this queue or its ordering:
    //   • step + qc events shift trailers between departments;
    //   • queueReordered / priorityChanged shift positions within the dept;
    //   • trailerStalled / trailerReady flip the stall badge or pull the
    //     trailer out of production entirely. Without these last two the
    //     queue would drift out of sync until the next manual refresh.
    if (![
      WsEventType.stepCompleted,
      WsEventType.stepReversed,
      WsEventType.qcPass,
      WsEventType.qcFail,
      WsEventType.queueReordered,
      WsEventType.priorityChanged,
      WsEventType.trailerStalled,
      WsEventType.trailerReady,
    ].contains(event.type)) {
      return;
    }

    final eventDeptId = event.departmentId;
    if (eventDeptId == null || eventDeptId == current.departmentId) {
      refresh();
    }
  }

  @override
  Future<void> close() {
    _wsSub?.cancel();
    return super.close();
  }
}
