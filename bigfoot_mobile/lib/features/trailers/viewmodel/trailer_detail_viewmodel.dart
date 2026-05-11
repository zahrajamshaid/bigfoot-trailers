import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/websocket/ws_client.dart';
import '../../../core/websocket/ws_events.dart';
import '../../../data/models/trailer.dart';
import '../../../domain/repositories/production_repository.dart';
import '../../../domain/repositories/storage_repository.dart';
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
  final List<StagePhotoGroup> stagePhotos;

  const TrailerDetailLoaded({
    required this.trailer,
    this.steps = const [],
    this.history = const [],
    this.stagePhotos = const [],
  });

  @override
  List<Object?> get props => [trailer, steps, history, stagePhotos];
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

class StagePhotoGroup extends Equatable {
  final String stageLabel;
  final List<TrailerStagePhoto> photos;

  const StagePhotoGroup({required this.stageLabel, required this.photos});

  @override
  List<Object?> get props => [stageLabel, photos];
}

class TrailerStagePhoto extends Equatable {
  final int id;
  final String source;
  final String stageLabel;
  final String storageKey;
  final String? downloadUrl;
  final DateTime? takenAt;
  final String? note;

  const TrailerStagePhoto({
    required this.id,
    required this.source,
    required this.stageLabel,
    required this.storageKey,
    this.downloadUrl,
    this.takenAt,
    this.note,
  });

  TrailerStagePhoto copyWith({String? downloadUrl}) {
    return TrailerStagePhoto(
      id: id,
      source: source,
      stageLabel: stageLabel,
      storageKey: storageKey,
      downloadUrl: downloadUrl ?? this.downloadUrl,
      takenAt: takenAt,
      note: note,
    );
  }

  @override
  List<Object?> get props => [id, source, stageLabel, storageKey, downloadUrl, takenAt, note];
}

class TrailerDetailViewModel extends Cubit<TrailerDetailState> {
  final TrailerRepository _repository;
  final StorageRepository _storageRepository;
  final ProductionRepository _productionRepository;
  final WsClient _ws;
  final int trailerId;
  StreamSubscription<WsEvent>? _wsSub;

  TrailerDetailViewModel({
    required TrailerRepository repository,
    required StorageRepository storageRepository,
    required ProductionRepository productionRepository,
    required WsClient ws,
    required this.trailerId,
  })  : _repository = repository,
        _storageRepository = storageRepository,
        _productionRepository = productionRepository,
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

      Map<String, dynamic> historyPayload = const <String, dynamic>{};
      try {
        historyPayload = await _repository.getHistory(trailerId);
      } catch (_) {
        // User lacks permission — keep history/photos empty.
      }

      if (isClosed) return;

      final sortedSteps = List<ProductionStepSummary>.from(steps)
        ..sort((a, b) => a.stepOrder.compareTo(b.stepOrder));
      final auditLogs = _asMapList(historyPayload['auditLogs']);
      final history = auditLogs.map(HistoryEntry.fromJson).toList();
      final stagePhotos = await _buildStagePhotos(historyPayload);

      emit(TrailerDetailLoaded(
        trailer: trailer,
        steps: sortedSteps,
        history: history,
        stagePhotos: stagePhotos,
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

  /// Admin override — place the trailer at [stepId]. Throws on failure so the
  /// caller can surface the API error to the user; refreshes detail state on
  /// success.
  Future<void> jumpToStep(int stepId, {String? reason}) async {
    await _productionRepository.jumpToStep(
      trailerId: trailerId,
      stepId: stepId,
      reason: reason,
    );
    if (!isClosed) await load();
  }

  @override
  Future<void> close() {
    _wsSub?.cancel();
    return super.close();
  }

  Future<List<StagePhotoGroup>> _buildStagePhotos(
    Map<String, dynamic> historyPayload,
  ) async {
    final grouped = <String, List<TrailerStagePhoto>>{};

    final qcInspections = _asMapList(historyPayload['qcInspections']);
    for (final inspection in qcInspections) {
      final productionStep = inspection['productionStep'] as Map<String, dynamic>?;
      final stepOrder = _toInt(productionStep?['stepOrder']);
      final department = productionStep?['department'] as Map<String, dynamic>?;
      final departmentCode = department?['code'] as String?;

      final stageLabel = [
        if (stepOrder != null) 'Step $stepOrder',
        if (departmentCode != null && departmentCode.isNotEmpty) departmentCode.toUpperCase(),
        'QC',
      ].join(' • ');

      final photos = _asMapList(inspection['photos']);
      for (final photo in photos) {
        final storageKey = _getStorageKey(photo);
        if (storageKey == null || storageKey.isEmpty) continue;

        final trailerPhoto = TrailerStagePhoto(
          id: _toInt(photo['id']) ?? 0,
          source: 'qc',
          stageLabel: stageLabel,
          storageKey: storageKey,
          takenAt: _parseDate(photo['takenAt']),
          note: (inspection['result'] as String?)?.toUpperCase(),
        );
        grouped.putIfAbsent(stageLabel, () => []).add(trailerPhoto);
      }
    }

    final deliveries = _asMapList(historyPayload['deliveries']);
    for (final delivery in deliveries) {
      final destination = delivery['destinationLocation'] as Map<String, dynamic>?;
      final destinationName = destination?['name'] as String? ?? destination?['code'] as String?;
      final deliveryType = (delivery['deliveryType'] as String?)?.toUpperCase() ?? 'DELIVERY';
      final stageLabel = destinationName != null && destinationName.isNotEmpty
          ? '$deliveryType • $destinationName'
          : deliveryType;

      final photos = _asMapList(delivery['deliveryPhotos']);
      for (final photo in photos) {
        final storageKey = _getStorageKey(photo);
        if (storageKey == null || storageKey.isEmpty) continue;

        final trailerPhoto = TrailerStagePhoto(
          id: _toInt(photo['id']) ?? 0,
          source: 'delivery',
          stageLabel: stageLabel,
          storageKey: storageKey,
          takenAt: _parseDate(photo['takenAt']),
          note: (photo['photoType'] as String?)?.replaceAll('_', ' ').toUpperCase(),
        );
        grouped.putIfAbsent(stageLabel, () => []).add(trailerPhoto);
      }
    }

    final resolvedGroups = <StagePhotoGroup>[];
    for (final entry in grouped.entries) {
      final resolvedPhotos = await Future.wait(entry.value.map((photo) async {
        try {
          final url = await _storageRepository.getDownloadUrl(photo.storageKey);
          return photo.copyWith(downloadUrl: url);
        } catch (_) {
          return photo;
        }
      }));

      resolvedGroups.add(StagePhotoGroup(stageLabel: entry.key, photos: resolvedPhotos));
    }

    return resolvedGroups;
  }

  static List<Map<String, dynamic>> _asMapList(dynamic value) {
    if (value is! List) return const [];
    return value.whereType<Map<String, dynamic>>().toList();
  }

  static String? _getStorageKey(Map<String, dynamic> photo) {
    final key = photo['storageKey']?.toString();
    if (key != null && key.isNotEmpty) return key;

    final storageUrl = photo['storageUrl']?.toString();
    if (storageUrl != null && storageUrl.isNotEmpty) return storageUrl;
    return null;
  }

  static int? _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }
}
