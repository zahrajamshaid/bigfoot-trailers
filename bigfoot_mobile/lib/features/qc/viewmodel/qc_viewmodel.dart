import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/websocket/ws_client.dart';
import '../../../core/websocket/ws_events.dart';
import '../../../data/models/department.dart';
import '../../../data/models/qc_inspection.dart';
import '../../../domain/repositories/qc_repository.dart';

// Re-export domain types used by screens
export '../../../domain/repositories/qc_repository.dart'
    show QcQueueItem, QcInspectionResult, UpstreamCheck;

// ── States ───────────────────────────────────────────────────────────────────

sealed class QcState extends Equatable {
  const QcState();
  @override
  List<Object?> get props => [];
}

class QcInitial extends QcState {
  const QcInitial();
}

class QcLoading extends QcState {
  const QcLoading();
}

class QcLoaded extends QcState {
  final Map<String, List<QcQueueItem>> groupedQueue;
  final bool isRefreshing;

  const QcLoaded({required this.groupedQueue, this.isRefreshing = false});

  int get totalCount =>
      groupedQueue.values.fold(0, (sum, list) => sum + list.length);

  @override
  List<Object?> get props => [groupedQueue, isRefreshing];
}

class QcError extends QcState {
  final String message;
  const QcError(this.message);
  @override
  List<Object?> get props => [message];
}

// ── ViewModel ────────────────────────────────────────────────────────────────

class QcViewModel extends Cubit<QcState> {
  final QcRepository _repository;
  final WsClient _ws;
  StreamSubscription<WsEvent>? _wsSub;

  QcViewModel({required QcRepository repository, required WsClient ws})
      : _repository = repository,
        _ws = ws,
        super(const QcInitial()) {
    _wsSub = _ws.events.listen(_onWsEvent);
  }

  Future<void> load() async {
    emit(const QcLoading());
    try {
      final grouped = await _repository.getQcQueues();
      emit(QcLoaded(groupedQueue: grouped));
    } on ApiException catch (e) {
      emit(QcError(e.displayMessage));
    } on NetworkException catch (e) {
      emit(QcError(e.message));
    } catch (_) {
      emit(const QcError('Failed to load QC queue'));
    }
  }

  Future<void> refresh() async {
    final current = state;
    if (current is QcLoaded) {
      emit(QcLoaded(groupedQueue: current.groupedQueue, isRefreshing: true));
    }
    await load();
  }

  Future<List<QcChecklistItem>> fetchChecklistItems({
    required int departmentId,
    String? series,
    int? trailerId,
  }) => _repository.getChecklistItems(
        departmentId: departmentId,
        series: series,
        trailerId: trailerId,
      );

  Future<List<Department>> fetchReworkTargets(int trailerId) =>
      _repository.getReworkTargets(trailerId);

  Future<QcInspectionResult> submitInspection({
    required int productionStepId,
    required String result,
    String? failNotes,
    int? reworkTargetDepartmentId,
    required List<Map<String, dynamic>> checklistResults,
    required List<String> photoStorageKeys,
  }) async {
    final inspResult = await _repository.submitInspection(
      productionStepId: productionStepId,
      result: result,
      failNotes: failNotes,
      reworkTargetDepartmentId: reworkTargetDepartmentId,
      checklistResults: checklistResults,
      photoStorageKeys: photoStorageKeys,
    );
    load();
    return inspResult;
  }

  Future<QcInspection> fetchInspection(int id) => _repository.getInspection(id);

  Future<List<QcInspection>> fetchInspectionsForStep(int stepId) =>
      _repository.getInspectionsForStep(stepId);

  Future<String> uploadPhoto(List<int> bytes, String filename) =>
      _repository.uploadPhoto(bytes, filename);

  Future<void> createChecklistItem({
    required int departmentId,
    required String label,
    int sortOrder = 0,
    String appliesToSeries = 'all',
  }) => _repository.createChecklistItem(
    departmentId: departmentId,
    label: label,
    sortOrder: sortOrder,
    appliesToSeries: appliesToSeries,
  );

  Future<void> updateChecklistItem(int id, {String? label, int? sortOrder, bool? isActive}) =>
      _repository.updateChecklistItem(id, label: label, sortOrder: sortOrder, isActive: isActive);

  Future<List<QcChecklistItem>> fetchAllChecklistItems() =>
      _repository.getAllChecklistItems();

  Future<List<UpstreamCheck>> fetchUpstreamChecks(int trailerId) =>
      _repository.getUpstreamChecksForTrailer(trailerId);

  void _onWsEvent(WsEvent event) {
    if (state is! QcLoaded) return;
    if ([
      WsEventType.stepCompleted,
      WsEventType.qcPass,
      WsEventType.qcFail,
    ].contains(event.type)) {
      refresh();
    }
  }

  @override
  Future<void> close() {
    _wsSub?.cancel();
    return super.close();
  }
}
