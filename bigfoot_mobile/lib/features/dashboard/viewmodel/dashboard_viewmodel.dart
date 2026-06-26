import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/websocket/ws_client.dart';
import '../../../core/websocket/ws_events.dart';
import '../../../domain/repositories/dashboard_repository.dart';

// ── Dashboard Data ──────────────────────────────────────────────────────────

class DashboardData extends Equatable {
  final int activeTrailers;
  final int readyForDelivery;
  final int hotTrailers;
  final int stalledSteps;
  final int weeklyCompleted;
  /// All-time count of trailers whose status is `delivered`. Drives the
  /// "Archived" tile on the manager dashboard — it deep-links to the
  /// Trailers list filtered for delivered units.
  final int archivedTotal;
  final double qcFailRate;
  /// Raw 30-day counts behind [qcFailRate] — surfaced on the manager
  /// dashboard tile as "X.X% · F of N (30d)".
  final int qcFailRateInspections;
  final int qcFailRateFails;
  final int totalTrailers;
  final int pendingProduction;
  /// Stock builds at Mulberry currently ready_for_delivery, grouped by
  /// destination yard code. Powers the "Mulberry → Yards" tile + its
  /// drill-down. Always carries entries for JACKSONVILLE / TAPPAHANNOCK /
  /// TALLAHASSEE / ATLANTA (zero when nothing is queued) once the new
  /// API is live.
  final Map<String, int> mulberryStockByYard;
  final int mulberryStockTotal;
  /// Customer-order trailers at Mulberry waiting on a factory pickup.
  /// Powers the matched "Customer pickups @ Mulberry" tile.
  final int mulberryCustomerPickups;
  final int myQueueCount;
  final double myPointsToday;
  final double myPointsWeek;
  final String? nextTrailerSo;
  final String? nextTrailerColor;
  final int readyForInspection;
  final int inspectionsToday;
  final double failRateToday;
  final int reworkQueue;
  final int activeDeliveries;
  final int upcomingDeliveries;
  final int completedThisWeek;
  final int scheduledDeliveries;
  final int inTransitCount;
  final int readyForPickup;
  final List<ActivityItem> recentActivity;

  const DashboardData({
    this.activeTrailers = 0,
    this.readyForDelivery = 0,
    this.hotTrailers = 0,
    this.stalledSteps = 0,
    this.weeklyCompleted = 0,
    this.archivedTotal = 0,
    this.qcFailRate = 0,
    this.qcFailRateInspections = 0,
    this.qcFailRateFails = 0,
    this.totalTrailers = 0,
    this.pendingProduction = 0,
    this.mulberryStockByYard = const <String, int>{},
    this.mulberryStockTotal = 0,
    this.mulberryCustomerPickups = 0,
    this.myQueueCount = 0,
    this.myPointsToday = 0,
    this.myPointsWeek = 0,
    this.nextTrailerSo,
    this.nextTrailerColor,
    this.readyForInspection = 0,
    this.inspectionsToday = 0,
    this.failRateToday = 0,
    this.reworkQueue = 0,
    this.activeDeliveries = 0,
    this.upcomingDeliveries = 0,
    this.completedThisWeek = 0,
    this.scheduledDeliveries = 0,
    this.inTransitCount = 0,
    this.readyForPickup = 0,
    this.recentActivity = const [],
  });

  DashboardData copyWith({
    int? activeTrailers,
    int? readyForDelivery,
    int? hotTrailers,
    int? stalledSteps,
    int? weeklyCompleted,
    int? archivedTotal,
    double? qcFailRate,
    int? qcFailRateInspections,
    int? qcFailRateFails,
    int? totalTrailers,
    int? pendingProduction,
    Map<String, int>? mulberryStockByYard,
    int? mulberryStockTotal,
    int? mulberryCustomerPickups,
    int? myQueueCount,
    double? myPointsToday,
    double? myPointsWeek,
    String? nextTrailerSo,
    String? nextTrailerColor,
    int? readyForInspection,
    int? inspectionsToday,
    double? failRateToday,
    int? reworkQueue,
    int? activeDeliveries,
    int? upcomingDeliveries,
    int? completedThisWeek,
    int? scheduledDeliveries,
    int? inTransitCount,
    int? readyForPickup,
    List<ActivityItem>? recentActivity,
  }) {
    return DashboardData(
      activeTrailers: activeTrailers ?? this.activeTrailers,
      readyForDelivery: readyForDelivery ?? this.readyForDelivery,
      hotTrailers: hotTrailers ?? this.hotTrailers,
      stalledSteps: stalledSteps ?? this.stalledSteps,
      weeklyCompleted: weeklyCompleted ?? this.weeklyCompleted,
      archivedTotal: archivedTotal ?? this.archivedTotal,
      qcFailRate: qcFailRate ?? this.qcFailRate,
      qcFailRateInspections:
          qcFailRateInspections ?? this.qcFailRateInspections,
      qcFailRateFails: qcFailRateFails ?? this.qcFailRateFails,
      totalTrailers: totalTrailers ?? this.totalTrailers,
      pendingProduction: pendingProduction ?? this.pendingProduction,
      mulberryStockByYard: mulberryStockByYard ?? this.mulberryStockByYard,
      mulberryStockTotal: mulberryStockTotal ?? this.mulberryStockTotal,
      mulberryCustomerPickups:
          mulberryCustomerPickups ?? this.mulberryCustomerPickups,
      myQueueCount: myQueueCount ?? this.myQueueCount,
      myPointsToday: myPointsToday ?? this.myPointsToday,
      myPointsWeek: myPointsWeek ?? this.myPointsWeek,
      nextTrailerSo: nextTrailerSo ?? this.nextTrailerSo,
      nextTrailerColor: nextTrailerColor ?? this.nextTrailerColor,
      readyForInspection: readyForInspection ?? this.readyForInspection,
      inspectionsToday: inspectionsToday ?? this.inspectionsToday,
      failRateToday: failRateToday ?? this.failRateToday,
      reworkQueue: reworkQueue ?? this.reworkQueue,
      activeDeliveries: activeDeliveries ?? this.activeDeliveries,
      upcomingDeliveries: upcomingDeliveries ?? this.upcomingDeliveries,
      completedThisWeek: completedThisWeek ?? this.completedThisWeek,
      scheduledDeliveries: scheduledDeliveries ?? this.scheduledDeliveries,
      inTransitCount: inTransitCount ?? this.inTransitCount,
      readyForPickup: readyForPickup ?? this.readyForPickup,
      recentActivity: recentActivity ?? this.recentActivity,
    );
  }

  @override
  List<Object?> get props => [
        activeTrailers, readyForDelivery, hotTrailers, stalledSteps,
        weeklyCompleted, archivedTotal, qcFailRate, qcFailRateInspections,
        qcFailRateFails, totalTrailers, pendingProduction, mulberryStockByYard,
        mulberryStockTotal, mulberryCustomerPickups,
        myQueueCount, myPointsToday,
        myPointsWeek, nextTrailerSo, nextTrailerColor,
        readyForInspection, inspectionsToday, failRateToday, reworkQueue,
        activeDeliveries, upcomingDeliveries, completedThisWeek,
        scheduledDeliveries, inTransitCount, readyForPickup, recentActivity,
      ];
}

class ActivityItem extends Equatable {
  final String type;
  final String description;
  final DateTime timestamp;

  const ActivityItem({
    required this.type,
    required this.description,
    required this.timestamp,
  });

  @override
  List<Object?> get props => [type, description, timestamp];
}

// ── Dashboard States ─────────────────────────────────────────────────────────

sealed class DashboardState extends Equatable {
  const DashboardState();
  @override
  List<Object?> get props => [];
}

class DashboardInitial extends DashboardState {
  const DashboardInitial();
}

class DashboardLoading extends DashboardState {
  const DashboardLoading();
}

class DashboardLoaded extends DashboardState {
  final DashboardData data;
  final bool isRefreshing;

  const DashboardLoaded({required this.data, this.isRefreshing = false});

  @override
  List<Object?> get props => [data, isRefreshing];
}

class DashboardError extends DashboardState {
  final String message;
  const DashboardError(this.message);

  @override
  List<Object?> get props => [message];
}

// ── Dashboard ViewModel ─────────────────────────────────────────────────────

class DashboardViewModel extends Cubit<DashboardState> {
  final DashboardRepository _repository;
  final WsClient _ws;
  String _role;
  int? _userId;
  int? _departmentId;
  StreamSubscription<WsEvent>? _wsSub;

  DashboardViewModel({
    required DashboardRepository repository,
    required WsClient ws,
    required String role,
    int? userId,
    int? departmentId,
  })  : _repository = repository,
        _ws = ws,
        _role = role,
        _userId = userId,
        _departmentId = departmentId,
        super(const DashboardInitial()) {
    _wsSub = _ws.events.listen(_onWsEvent);
  }

  Future<void> loadForUser({
    required String role,
    int? userId,
    int? departmentId,
  }) async {
    _role = role;
    _userId = userId;
    _departmentId = departmentId;
    return load();
  }

  Future<void> load() async {
    emit(const DashboardLoading());
    try {
      final stats = await _fetchData();
      emit(DashboardLoaded(data: _toDashboardData(stats)));
    } on ApiException catch (e) {
      emit(DashboardError(e.displayMessage));
    } on NetworkException catch (e) {
      emit(DashboardError(e.message));
    } catch (e) {
      emit(const DashboardError('Failed to load dashboard'));
    }
  }

  Future<void> refresh() async {
    final current = state;
    if (current is DashboardLoaded) {
      emit(DashboardLoaded(data: current.data, isRefreshing: true));
    }
    try {
      final stats = await _fetchData();
      // Preserve client-side state (live activity feed) that doesn't come
      // from the role-specific stats endpoint.
      final activity = current is DashboardLoaded
          ? current.data.recentActivity
          : const <ActivityItem>[];
      emit(DashboardLoaded(
        data: _toDashboardData(stats).copyWith(recentActivity: activity),
      ));
    } catch (_) {
      if (current is DashboardLoaded) {
        emit(DashboardLoaded(data: current.data));
      }
    }
  }

  /// Single mapping point so `load` and `refresh` always carry the same
  /// fields — previously `refresh` dropped the QC / payroll fields, which
  /// made the QC dashboard render zeros after every pull-to-refresh.
  DashboardData _toDashboardData(DashboardStats stats) {
    return DashboardData(
      activeTrailers: stats.activeTrailers,
      readyForDelivery: stats.readyForDelivery,
      hotTrailers: stats.hotTrailers,
      stalledSteps: stats.stalledSteps,
      weeklyCompleted: stats.weeklyCompleted,
      archivedTotal: stats.archivedTotal,
      qcFailRate: stats.qcFailRate,
      qcFailRateInspections: stats.qcFailRateInspections,
      qcFailRateFails: stats.qcFailRateFails,
      totalTrailers: stats.totalTrailers,
      pendingProduction: stats.pendingProduction,
      mulberryStockByYard: stats.mulberryStockByYard,
      mulberryStockTotal: stats.mulberryStockTotal,
      mulberryCustomerPickups: stats.mulberryCustomerPickups,
      myQueueCount: stats.myQueueCount,
      myPointsToday: stats.myPointsToday,
      myPointsWeek: stats.myPointsWeek,
      readyForInspection: stats.readyForInspection,
      inspectionsToday: stats.inspectionsToday,
      failRateToday: stats.failRateToday,
      reworkQueue: stats.reworkQueue,
      activeDeliveries: stats.activeDeliveries,
      upcomingDeliveries: stats.upcomingDeliveries,
      completedThisWeek: stats.completedThisWeek,
      scheduledDeliveries: stats.scheduledDeliveries,
      inTransitCount: stats.inTransitCount,
      readyForPickup: stats.readyForPickup,
    );
  }

  Future<DashboardStats> _fetchData() async {
    switch (_role) {
      case 'owner':
      case 'office':
      case 'production_manager':
        return _repository.fetchManagerStats();
      case 'worker':
        return _repository.fetchWorkerStats(_userId ?? 0, _departmentId);
      case 'qc_inspector':
        // QC now lives in the production-admin tier and its dashboard
        // surfaces both the original QC metrics (ready-for-inspection,
        // inspections-today, fail-rate-today, rework-queue) AND the
        // shop-floor counts (total trailers, pending production, in
        // production, hot, stalled, completed-this-week, archived).
        // The two backend feeds live behind different endpoints, so we
        // fan out in parallel and merge the result. /qc/stats already
        // returns qcFailRate as part of fetchManagerStats — we let the
        // manager-fetch value win because it's the same endpoint
        // computed once and cached on the response.
        final results = await Future.wait([
          _repository.fetchManagerStats(),
          _repository.fetchQcStats(),
        ]);
        final mgr = results[0];
        final qc = results[1];
        return DashboardStats(
          // shop-floor counts (manager-fetch)
          activeTrailers: mgr.activeTrailers,
          readyForDelivery: mgr.readyForDelivery,
          hotTrailers: mgr.hotTrailers,
          stalledSteps: mgr.stalledSteps,
          weeklyCompleted: mgr.weeklyCompleted,
          archivedTotal: mgr.archivedTotal,
          qcFailRate: mgr.qcFailRate,
          // 30-day raw counts come back on /qc/stats only — the manager
          // fetch piggybacks on the rate but not the breakdown.
          qcFailRateInspections: qc.qcFailRateInspections,
          qcFailRateFails: qc.qcFailRateFails,
          totalTrailers: mgr.totalTrailers,
          pendingProduction: mgr.pendingProduction,
          mulberryStockByYard: mgr.mulberryStockByYard,
          mulberryStockTotal: mgr.mulberryStockTotal,
          mulberryCustomerPickups: mgr.mulberryCustomerPickups,
          // QC-specific (qc-stats fetch)
          readyForInspection: qc.readyForInspection,
          inspectionsToday: qc.inspectionsToday,
          failRateToday: qc.failRateToday,
          reworkQueue: qc.reworkQueue,
        );
      case 'driver':
        return _repository.fetchDriverStats();
      case 'transport_manager':
        return _repository.fetchTransportStats();
      default:
        return _repository.fetchManagerStats();
    }
  }

  void _onWsEvent(WsEvent event) {
    final current = state;
    if (current is! DashboardLoaded) return;

    final data = current.data;

    final activity = ActivityItem(
      type: event.type,
      description: _describeEvent(event),
      timestamp: event.timestamp,
    );
    final updatedActivity = [activity, ...data.recentActivity].take(10).toList();

    switch (event.type) {
      case WsEventType.stepCompleted:
        emit(DashboardLoaded(
          data: data.copyWith(
            recentActivity: updatedActivity,
            weeklyCompleted: data.weeklyCompleted + 1,
          ),
        ));
      case WsEventType.qcPass:
        emit(DashboardLoaded(
          data: data.copyWith(recentActivity: updatedActivity),
        ));
      case WsEventType.qcFail:
        emit(DashboardLoaded(
          data: data.copyWith(
            recentActivity: updatedActivity,
            reworkQueue: data.reworkQueue + 1,
          ),
        ));
      case WsEventType.trailerReady:
        emit(DashboardLoaded(
          data: data.copyWith(
            readyForDelivery: data.readyForDelivery + 1,
            activeTrailers: (data.activeTrailers - 1).clamp(0, 99999),
            recentActivity: updatedActivity,
          ),
        ));
      case WsEventType.deliveryDispatched:
        emit(DashboardLoaded(
          data: data.copyWith(
            inTransitCount: data.inTransitCount + 1,
            scheduledDeliveries: (data.scheduledDeliveries - 1).clamp(0, 99999),
            recentActivity: updatedActivity,
          ),
        ));
      case WsEventType.deliveryComplete:
        emit(DashboardLoaded(
          data: data.copyWith(
            completedThisWeek: data.completedThisWeek + 1,
            inTransitCount: (data.inTransitCount - 1).clamp(0, 99999),
            recentActivity: updatedActivity,
          ),
        ));
      case WsEventType.pointsUpdated:
        refresh();
      default:
        emit(DashboardLoaded(
          data: data.copyWith(recentActivity: updatedActivity),
        ));
    }
  }

  String _describeEvent(WsEvent event) {
    final so = event.data['soNumber'] as String? ?? '';
    switch (event.type) {
      case WsEventType.stepCompleted:
        return 'Step completed on $so';
      case WsEventType.qcPass:
        return 'QC passed on $so';
      case WsEventType.qcFail:
        return 'QC failed on $so';
      case WsEventType.trailerReady:
        return '$so ready for delivery';
      case WsEventType.deliveryDispatched:
        return '$so dispatched';
      case WsEventType.deliveryComplete:
        return '$so delivered';
      case WsEventType.pointsUpdated:
        return 'Points updated';
      default:
        return event.type;
    }
  }

  @override
  Future<void> close() {
    _wsSub?.cancel();
    return super.close();
  }
}
