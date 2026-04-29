import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'ws_client.dart';
import 'ws_event_stream.dart';

class RealtimeTick extends Equatable {
  final int version;
  final DateTime updatedAt;

  const RealtimeTick({required this.version, required this.updatedAt});

  RealtimeTick next() => RealtimeTick(version: version + 1, updatedAt: DateTime.now());

  @override
  List<Object?> get props => [version, updatedAt];
}

class DepartmentQueueRealtimeCubit extends Cubit<RealtimeTick> {
  final WsClient _ws;
  StreamSubscription<WsEvent>? _sub;
  final Set<int> _watchedDepartments = {};

  DepartmentQueueRealtimeCubit({required WsClient ws})
      : _ws = ws,
        super(RealtimeTick(version: 0, updatedAt: DateTime.now())) {
    _sub = _ws.events.listen(_onEvent);
  }

  Future<void> watchDepartments(Iterable<int> departmentIds) async {
    _watchedDepartments
      ..clear()
      ..addAll(departmentIds);
  }

  void _onEvent(WsEvent event) {
    if (!_watchedDepartments.any(event.affectsDepartment)) return;
    if (!const {
      WsEventType.stepCompleted,
      WsEventType.qcPass,
      WsEventType.qcFail,
      WsEventType.queueReordered,
      WsEventType.priorityChanged,
      WsEventType.trailerStalled,
    }.contains(event.type)) {
      return;
    }
    emit(state.next());
  }

  @override
  Future<void> close() async {
    await _sub?.cancel();
    return super.close();
  }
}

class TrailerDetailRealtimeCubit extends Cubit<RealtimeTick> {
  final WsClient _ws;
  StreamSubscription<WsEvent>? _sub;
  int? _watchedTrailerId;

  TrailerDetailRealtimeCubit({required WsClient ws})
      : _ws = ws,
        super(RealtimeTick(version: 0, updatedAt: DateTime.now())) {
    _sub = _ws.events.listen(_onEvent);
  }

  void watchTrailer(int trailerId) {
    _watchedTrailerId = trailerId;
  }

  void _onEvent(WsEvent event) {
    final trailerId = _watchedTrailerId;
    if (trailerId == null || !event.affectsTrailer(trailerId)) return;
    emit(state.next());
  }

  @override
  Future<void> close() async {
    await _sub?.cancel();
    return super.close();
  }
}

class DashboardStatsRealtimeCubit extends Cubit<RealtimeTick> {
  final WsClient _ws;
  StreamSubscription<WsEvent>? _sub;

  DashboardStatsRealtimeCubit({required WsClient ws})
      : _ws = ws,
        super(RealtimeTick(version: 0, updatedAt: DateTime.now())) {
    _sub = _ws.events.listen(_onEvent);
  }

  void _onEvent(WsEvent event) {
    if (event.isProductionEvent || event.isDeliveryEvent) {
      emit(state.next());
    }
  }

  @override
  Future<void> close() async {
    await _sub?.cancel();
    return super.close();
  }
}

class NotificationCountCubit extends Cubit<int> {
  final WsClient _ws;
  StreamSubscription<WsEvent>? _sub;

  NotificationCountCubit({required WsClient ws})
      : _ws = ws,
        super(0) {
    _sub = _ws.events.listen(_onEvent);
  }

  void _onEvent(WsEvent event) {
    if (const {
      WsEventType.qcFail,
      WsEventType.trailerStalled,
      WsEventType.deliveryComplete,
      WsEventType.workerMessage,
    }.contains(event.type)) {
      emit(state + 1);
    }
  }

  @override
  Future<void> close() async {
    await _sub?.cancel();
    return super.close();
  }
}
