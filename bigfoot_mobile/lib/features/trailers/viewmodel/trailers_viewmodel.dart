import 'dart:async';

import 'package:equatable/equatable.dart';
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
  final int page;
  final String? search;
  final String? statusFilter;
  final String? seriesFilter;
  final bool hotOnly;
  final bool isLoadingMore;

  const TrailersLoaded({
    required this.trailers,
    this.hasMore = true,
    this.page = 1,
    this.search,
    this.statusFilter,
    this.seriesFilter,
    this.hotOnly = false,
    this.isLoadingMore = false,
  });

  TrailersLoaded copyWith({
    List<Trailer>? trailers,
    bool? hasMore,
    int? page,
    String? search,
    String? statusFilter,
    String? seriesFilter,
    bool? hotOnly,
    bool? isLoadingMore,
  }) {
    return TrailersLoaded(
      trailers: trailers ?? this.trailers,
      hasMore: hasMore ?? this.hasMore,
      page: page ?? this.page,
      search: search ?? this.search,
      statusFilter: statusFilter ?? this.statusFilter,
      seriesFilter: seriesFilter ?? this.seriesFilter,
      hotOnly: hotOnly ?? this.hotOnly,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    );
  }

  @override
  List<Object?> get props =>
      [trailers, hasMore, page, search, statusFilter, seriesFilter, hotOnly, isLoadingMore];
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
    bool hotOnly = false,
  }) async {
    emit(const TrailersLoading());
    try {
      final result = await _repository.getTrailers(
        page: 1,
        search: search,
        status: status,
        series: series,
        hotOnly: hotOnly,
      );
      emit(TrailersLoaded(
        trailers: _sortTrailers(result.items),
        hasMore: result.hasMore,
        page: 1,
        search: search,
        statusFilter: status,
        seriesFilter: series,
        hotOnly: hotOnly,
      ));
    } on ApiException catch (e) {
      emit(TrailersError(e.displayMessage));
    } on NetworkException catch (e) {
      emit(TrailersError(e.message));
    } catch (_) {
      emit(const TrailersError('Failed to load trailers'));
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
        hotOnly: current.hotOnly,
      );
      emit(TrailersLoaded(
        trailers: _sortTrailers([...current.trailers, ...result.items]),
        hasMore: result.hasMore,
        page: nextPage,
        search: current.search,
        statusFilter: current.statusFilter,
        seriesFilter: current.seriesFilter,
        hotOnly: current.hotOnly,
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
      hotOnly: current is TrailersLoaded ? current.hotOnly : false,
    );
  }

  void setSeriesFilter(String? series) {
    final current = state;
    load(
      search: current is TrailersLoaded ? current.search : null,
      status: current is TrailersLoaded ? current.statusFilter : null,
      series: series,
      hotOnly: current is TrailersLoaded ? current.hotOnly : false,
    );
  }

  void toggleHotOnly() {
    final current = state;
    final wasHot = current is TrailersLoaded ? current.hotOnly : false;
    load(
      search: current is TrailersLoaded ? current.search : null,
      status: current is TrailersLoaded ? current.statusFilter : null,
      series: current is TrailersLoaded ? current.seriesFilter : null,
      hotOnly: !wasHot,
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
          hotOnly: current.hotOnly,
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
