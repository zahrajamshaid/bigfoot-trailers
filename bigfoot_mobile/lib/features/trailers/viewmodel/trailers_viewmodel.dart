import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/websocket/ws_client.dart';
import '../../../core/websocket/ws_events.dart';
import '../../../data/models/trailer.dart';
import '../../../domain/repositories/trailer_repository.dart';

// ── States ───────────────────────────────────────────────────────────────────

sealed class TrailersState extends Equatable {
  const TrailersState();
  @override
  List<Object?> get props => [];
}

class TrailersInitial extends TrailersState {
  const TrailersInitial();
}

class TrailersLoading extends TrailersState {
  const TrailersLoading();
}

class TrailersLoaded extends TrailersState {
  final List<Trailer> trailers;
  final bool hasMore;
  final bool fromCache;
  final DateTime? lastUpdated;
  final int page;
  final String? search;
  final String? statusFilter;
  final String? seriesFilter;
  final int? locationFilter;
  final String? saleStatusFilter;
  final bool hotOnly;
  final bool isLoadingMore;
  /// ISO 8601 cutoff for the "delivery completed at or after" filter —
  /// used by the dashboard "Completed this week" tile's deep link.
  final String? completedSince;

  const TrailersLoaded({
    required this.trailers,
    this.hasMore = true,
    this.fromCache = false,
    this.lastUpdated,
    this.page = 1,
    this.search,
    this.statusFilter,
    this.seriesFilter,
    this.locationFilter,
    this.saleStatusFilter,
    this.hotOnly = false,
    this.isLoadingMore = false,
    this.completedSince,
  });

  TrailersLoaded copyWith({
    List<Trailer>? trailers,
    bool? hasMore,
    bool? fromCache,
    DateTime? lastUpdated,
    int? page,
    String? search,
    String? statusFilter,
    String? seriesFilter,
    int? locationFilter,
    String? saleStatusFilter,
    bool? hotOnly,
    bool? isLoadingMore,
    String? completedSince,
  }) {
    return TrailersLoaded(
      trailers: trailers ?? this.trailers,
      hasMore: hasMore ?? this.hasMore,
      fromCache: fromCache ?? this.fromCache,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      page: page ?? this.page,
      search: search ?? this.search,
      statusFilter: statusFilter ?? this.statusFilter,
      seriesFilter: seriesFilter ?? this.seriesFilter,
      locationFilter: locationFilter ?? this.locationFilter,
      saleStatusFilter: saleStatusFilter ?? this.saleStatusFilter,
      hotOnly: hotOnly ?? this.hotOnly,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      completedSince: completedSince ?? this.completedSince,
    );
  }

  @override
  List<Object?> get props =>
      [
        trailers,
        hasMore,
        fromCache,
        lastUpdated,
        page,
        search,
        statusFilter,
        seriesFilter,
        locationFilter,
        saleStatusFilter,
        hotOnly,
        isLoadingMore,
        completedSince,
      ];
}

class TrailersError extends TrailersState {
  final String message;
  const TrailersError(this.message);
  @override
  List<Object?> get props => [message];
}

// ── ViewModel ────────────────────────────────────────────────────────────────

class TrailersViewModel extends Cubit<TrailersState> {
  final TrailerRepository _repository;
  final WsClient _ws;
  StreamSubscription<WsEvent>? _wsSub;
  Timer? _debounce;

  TrailersViewModel({required TrailerRepository repository, required WsClient ws})
      : _repository = repository,
        _ws = ws,
        super(const TrailersInitial()) {
    _wsSub = _ws.events.listen(_onWsEvent);
  }

  Future<void> load({
    String? search,
    String? status,
    String? series,
    int? locationId,
    String? saleStatus,
    bool hotOnly = false,
    String? completedSince,
  }) async {
    emit(const TrailersLoading());
    try {
      final result = await _repository.getTrailers(
        page: 1,
        search: search,
        status: status,
        series: series,
        locationId: locationId,
        saleStatus: saleStatus,
        hotOnly: hotOnly,
        completedSince: completedSince,
      );
      emit(TrailersLoaded(
        trailers: _sortTrailers(result.items),
        hasMore: result.hasMore,
        fromCache: result.fromCache,
        lastUpdated: result.lastUpdated,
        page: 1,
        search: search,
        statusFilter: status,
        seriesFilter: series,
        locationFilter: locationId,
        saleStatusFilter: saleStatus,
        hotOnly: hotOnly,
        completedSince: completedSince,
      ));
    } on ApiException catch (e) {
      emit(TrailersError(e.displayMessage));
    } on NetworkException catch (e) {
      emit(TrailersError(e.message));
    } catch (e, stack) {
      // Surface the underlying error so deserialization mismatches are
      // diagnosable from the screen instead of being hidden behind a
      // generic message.
      debugPrint('TrailersViewModel.load failed: $e\n$stack');
      emit(TrailersError('Failed to load trailers: $e'));
    }
  }

  Future<void> loadMore() async {
    final current = state;
    if (current is! TrailersLoaded || !current.hasMore || current.isLoadingMore) return;

    emit(current.copyWith(isLoadingMore: true));
    try {
      final nextPage = current.page + 1;
      final result = await _repository.getTrailers(
        page: nextPage,
        search: current.search,
        status: current.statusFilter,
        series: current.seriesFilter,
        locationId: current.locationFilter,
        saleStatus: current.saleStatusFilter,
        hotOnly: current.hotOnly,
        completedSince: current.completedSince,
      );
      emit(TrailersLoaded(
        trailers: _sortTrailers([...current.trailers, ...result.items]),
        hasMore: result.hasMore,
        fromCache: current.fromCache,
        lastUpdated: current.lastUpdated,
        page: nextPage,
        search: current.search,
        statusFilter: current.statusFilter,
        seriesFilter: current.seriesFilter,
        locationFilter: current.locationFilter,
        saleStatusFilter: current.saleStatusFilter,
        hotOnly: current.hotOnly,
        completedSince: current.completedSince,
      ));
    } catch (_) {
      emit(current.copyWith(isLoadingMore: false));
    }
  }

  void searchDebounced(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      final current = state;
      load(
        search: query.isEmpty ? null : query,
        status: current is TrailersLoaded ? current.statusFilter : null,
        series: current is TrailersLoaded ? current.seriesFilter : null,
        locationId: current is TrailersLoaded ? current.locationFilter : null,
        saleStatus: current is TrailersLoaded ? current.saleStatusFilter : null,
        hotOnly: current is TrailersLoaded ? current.hotOnly : false,
      );
    });
  }

  void setStatusFilter(String? status) {
    final current = state;
    load(
      search: current is TrailersLoaded ? current.search : null,
      status: status,
      series: current is TrailersLoaded ? current.seriesFilter : null,
      locationId: current is TrailersLoaded ? current.locationFilter : null,
      saleStatus: current is TrailersLoaded ? current.saleStatusFilter : null,
      hotOnly: current is TrailersLoaded ? current.hotOnly : false,
      completedSince:
          current is TrailersLoaded ? current.completedSince : null,
    );
  }

  void setSeriesFilter(String? series) {
    final current = state;
    load(
      search: current is TrailersLoaded ? current.search : null,
      status: current is TrailersLoaded ? current.statusFilter : null,
      series: series,
      locationId: current is TrailersLoaded ? current.locationFilter : null,
      saleStatus: current is TrailersLoaded ? current.saleStatusFilter : null,
      hotOnly: current is TrailersLoaded ? current.hotOnly : false,
      completedSince:
          current is TrailersLoaded ? current.completedSince : null,
    );
  }

  void setLocationFilter(int? locationId) {
    final current = state;
    load(
      search: current is TrailersLoaded ? current.search : null,
      status: current is TrailersLoaded ? current.statusFilter : null,
      series: current is TrailersLoaded ? current.seriesFilter : null,
      locationId: locationId,
      saleStatus: current is TrailersLoaded ? current.saleStatusFilter : null,
      hotOnly: current is TrailersLoaded ? current.hotOnly : false,
      completedSince:
          current is TrailersLoaded ? current.completedSince : null,
    );
  }

  void setSaleStatusFilter(String? saleStatus) {
    final current = state;
    load(
      search: current is TrailersLoaded ? current.search : null,
      status: current is TrailersLoaded ? current.statusFilter : null,
      series: current is TrailersLoaded ? current.seriesFilter : null,
      locationId: current is TrailersLoaded ? current.locationFilter : null,
      saleStatus: saleStatus,
      hotOnly: current is TrailersLoaded ? current.hotOnly : false,
      completedSince:
          current is TrailersLoaded ? current.completedSince : null,
    );
  }

  void toggleHotOnly() {
    final current = state;
    final wasHot = current is TrailersLoaded ? current.hotOnly : false;
    load(
      search: current is TrailersLoaded ? current.search : null,
      status: current is TrailersLoaded ? current.statusFilter : null,
      series: current is TrailersLoaded ? current.seriesFilter : null,
      locationId: current is TrailersLoaded ? current.locationFilter : null,
      saleStatus: current is TrailersLoaded ? current.saleStatusFilter : null,
      hotOnly: !wasHot,
      completedSince:
          current is TrailersLoaded ? current.completedSince : null,
    );
  }

  List<Trailer> _sortTrailers(List<Trailer> trailers) {
    final sorted = List<Trailer>.from(trailers);
    sorted.sort((a, b) {
      if (a.isHot && !b.isHot) return -1;
      if (!a.isHot && b.isHot) return 1;
      return a.globalPriority.compareTo(b.globalPriority);
    });
    return sorted;
  }

  void _onWsEvent(WsEvent event) {
    if (state is TrailersLoaded) {
      if ([
        WsEventType.stepCompleted,
        WsEventType.qcPass,
        WsEventType.qcFail,
        WsEventType.trailerReady,
        WsEventType.priorityChanged,
      ].contains(event.type)) {
        final current = state as TrailersLoaded;
        load(
          search: current.search,
          status: current.statusFilter,
          series: current.seriesFilter,
          locationId: current.locationFilter,
          saleStatus: current.saleStatusFilter,
          hotOnly: current.hotOnly,
          completedSince: current.completedSince,
        );
      }
    }
  }

  @override
  Future<void> close() {
    _wsSub?.cancel();
    _debounce?.cancel();
    return super.close();
  }
}
