import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/websocket/ws_client.dart';
import '../../../core/websocket/ws_events.dart';
import '../../../data/models/trailer.dart';
import '../../../domain/repositories/trailer_repository.dart';

sealed class TrailerDetailState extends Equatable {
  const TrailerDetailState();
  @override
  List<Object?> get props => [];
}

class TrailerDetailInitial extends TrailerDetailState {
  const TrailerDetailInitial();
}

class TrailerDetailLoading extends TrailerDetailState {
  const TrailerDetailLoading();
}

class TrailerDetailLoaded extends TrailerDetailState {
  final Trailer trailer;
  final List<ProductionStepSummary> steps;
  final List<HistoryEntry> history;

  const TrailerDetailLoaded({
    required this.trailer,
    this.steps = const [],
    this.history = const [],
  });

  @override
  List<Object?> get props => [trailer, steps, history];
}

class TrailerDetailError extends TrailerDetailState {
  final String message;
  const TrailerDetailError(this.message);
  @override
  List<Object?> get props => [message];
}

class HistoryEntry extends Equatable {
  final String action;
  final String? userName;
  final DateTime? timestamp;
  final String? details;
  final String? eventType;

  const HistoryEntry({
    required this.action,
    this.userName,
    this.timestamp,
    this.details,
    this.eventType,
  });

  factory HistoryEntry.fromJson(Map<String, dynamic> json) {
    final user = json['user'] as Map<String, dynamic>?;
    return HistoryEntry(
      action: json['action'] as String? ?? '',
      userName: user?['fullName'] as String? ?? json['userName'] as String?,
      timestamp: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'] as String)
          : null,
      details: json['details'] as String?,
      eventType: json['eventType'] as String?,
    );
  }

  @override
  List<Object?> get props => [action, userName, timestamp, details, eventType];
}

class TrailerDetailViewModel extends Cubit<TrailerDetailState> {
  final TrailerRepository _repository;
  final WsClient _ws;
  final int trailerId;
  StreamSubscription<WsEvent>? _wsSub;

  TrailerDetailViewModel({
    required TrailerRepository repository,
    required WsClient ws,
    required this.trailerId,
  })  : _repository = repository,
        _ws = ws,
        super(const TrailerDetailInitial()) {
    _wsSub = _ws.events
        .where((e) => e.affectsTrailer(trailerId))
        .listen((_) => load());
  }

  Future<void> load() async {
    if (isClosed) return;
    if (state is TrailerDetailInitial) {
      emit(const TrailerDetailLoading());
    }

    try {
      final trailerFuture = _repository.getTrailer(trailerId);
      final stepsFuture = _repository.getSteps(trailerId);

      final trailer = await trailerFuture;
      final steps = await stepsFuture;

      List<Map<String, dynamic>> historyData = const [];
      try {
        historyData = await _repository.getHistory(trailerId);
      } catch (_) {
        // User lacks permission or shape mismatch — show empty history
      }

      if (isClosed) return;

      final sortedSteps = List<ProductionStepSummary>.from(steps)
        ..sort((a, b) => a.stepOrder.compareTo(b.stepOrder));
      final history = historyData.map(HistoryEntry.fromJson).toList();

      emit(TrailerDetailLoaded(
        trailer: trailer,
        steps: sortedSteps,
        history: history,
      ));
    } on ApiException catch (e) {
      if (!isClosed) emit(TrailerDetailError(e.displayMessage));
    } on NetworkException catch (e) {
      if (!isClosed) emit(TrailerDetailError(e.message));
    } catch (e) {
      if (!isClosed) emit(TrailerDetailError('Failed to load trailer details: $e'));
    }
  }

  Future<void> toggleHot() async {
    final current = state;
    if (current is! TrailerDetailLoaded) return;
    try {
      await _repository.toggleHot(trailerId, !current.trailer.isHot);
      if (!isClosed) await load();
    } on ApiException catch (e) {
      if (!isClosed) emit(TrailerDetailError(e.displayMessage));
    }
  }

  Future<void> setPriority(int priority) async {
    try {
      await _repository.updatePriority(trailerId, priority);
      if (!isClosed) await load();
    } on ApiException catch (e) {
      if (!isClosed) emit(TrailerDetailError(e.displayMessage));
    }
  }

  Future<void> addAddon(String name, String? notes) async {
    try {
      await _repository.addAddon(
        trailerId,
        {'addonName': name, if (notes != null) 'notes': notes},
      );
      if (!isClosed) await load();
    } on ApiException catch (e) {
      if (!isClosed) emit(TrailerDetailError(e.displayMessage));
    }
  }

  Future<void> removeAddon(int addonId) async {
    try {
      await _repository.removeAddon(trailerId, addonId);
      if (!isClosed) await load();
    } on ApiException catch (e) {
      if (!isClosed) emit(TrailerDetailError(e.displayMessage));
    }
  }

  @override
  Future<void> close() {
    _wsSub?.cancel();
    return super.close();
  }
}
