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

/// One field that changed, already rendered for a human by the API
/// (e.g. "Sale status: Available → Sold").
class HistoryChange extends Equatable {
  final String field;
  final String? from;
  final String? to;

  const HistoryChange({required this.field, this.from, this.to});

  factory HistoryChange.fromJson(Map<String, dynamic> j) => HistoryChange(
        field: j['field'] as String? ?? '',
        from: j['from'] as String?,
        to: j['to'] as String?,
      );

  /// "Sale status: Available → Sold" / "Color set to White".
  String get sentence =>
      from == null ? '$field set to ${to ?? 'none'}' : '$field: $from → ${to ?? 'none'}';

  @override
  List<Object?> get props => [field, from, to];
}

class HistoryEntry extends Equatable {
  final String action;
  final String? userName;
  final DateTime? timestamp;
  final String? details;
  final String? eventType;

  /// Plain-English one-liner from the API ("Status: In production → Ready for
  /// delivery"). Falls back to the raw action only if the API didn't send one.
  final String? summary;

  /// The action as a verb ("Updated", "QC failed").
  final String? actionLabel;

  /// Full field-by-field diff — what the row expands to show.
  final List<HistoryChange> changes;

  const HistoryEntry({
    required this.action,
    this.userName,
    this.timestamp,
    this.details,
    this.eventType,
    this.summary,
    this.actionLabel,
    this.changes = const [],
  });

  /// What the row actually shows: the human summary when we have one.
  String get headline =>
      (summary?.isNotEmpty ?? false) ? summary! : (actionLabel ?? action);

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
      summary: json['summary'] as String?,
      actionLabel: json['actionLabel'] as String?,
      changes: ((json['changes'] as List<dynamic>?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(HistoryChange.fromJson)
          .toList(),
    );
  }

  @override
  List<Object?> get props =>
      [action, userName, timestamp, details, eventType, summary, actionLabel, changes];
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
    final priorState = state;
    if (priorState is TrailerDetailInitial) {
      emit(const TrailerDetailLoading());
    }

    try {
      final trailerFuture = _repository.getTrailer(trailerId);
      final stepsFuture = _repository.getSteps(trailerId);

      final trailer = await trailerFuture;
      final steps = await stepsFuture;

      // Null means the history fetch failed (permission OR a transient error).
      // Distinguishing it from an empty result lets us keep previously loaded
      // history instead of blanking it on every failed WebSocket refresh.
      Map<String, dynamic>? historyPayload;
      try {
        historyPayload = await _repository.getHistory(trailerId);
      } catch (_) {
        historyPayload = null;
      }

      if (isClosed) return;

      final sortedSteps = List<ProductionStepSummary>.from(steps)
        ..sort((a, b) => a.stepOrder.compareTo(b.stepOrder));

      final List<HistoryEntry> history;
      final List<StagePhotoGroup> stagePhotos;
      if (historyPayload != null) {
        history = _buildHistory(historyPayload);
        stagePhotos = await _buildStagePhotos(historyPayload);
      } else if (priorState is TrailerDetailLoaded) {
        // Preserve last known history/photos rather than dropping them.
        history = priorState.history;
        stagePhotos = priorState.stagePhotos;
      } else {
        history = const [];
        stagePhotos = const [];
      }

      if (isClosed) return;

      emit(TrailerDetailLoaded(
        trailer: trailer,
        steps: sortedSteps,
        history: history,
        stagePhotos: stagePhotos,
      ));
    } on ApiException catch (e) {
      if (isClosed) return;
      // A failed background refresh must not blow away an already-loaded
      // screen — only surface the error on the initial load.
      if (priorState is! TrailerDetailLoaded) {
        emit(TrailerDetailError(e.displayMessage));
      }
    } on NetworkException catch (e) {
      if (isClosed) return;
      if (priorState is! TrailerDetailLoaded) {
        emit(TrailerDetailError(e.message));
      }
    } catch (e) {
      if (isClosed) return;
      if (priorState is! TrailerDetailLoaded) {
        emit(TrailerDetailError('Failed to load trailer details: $e'));
      }
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

  /// Change the sale status (`available` / `sale_pending` / `sold`).
  /// Throws on failure so the caller can surface the API error to the user;
  /// refreshes the detail state on success. When [fulfilmentType] is set on
  /// a sold transition the backend auto-creates the scheduled Delivery.
  Future<void> updateSaleStatus(
    String saleStatus, {
    String? soldToName,
    String? fulfilmentType,
    String? deliveryAddress,
  }) async {
    await _repository.updateSaleStatus(
      trailerId,
      saleStatus,
      soldToName: soldToName,
      fulfilmentType: fulfilmentType,
      deliveryAddress: deliveryAddress,
    );
    if (!isClosed) await load();
  }

  /// Terminal completion (sales-facing). Closes the open delivery and flips
  /// the trailer to delivered. Throws on failure; refreshes on success.
  Future<void> markCompleted() async {
    await _repository.markCompleted(trailerId);
    if (!isClosed) await load();
  }

  /// Owner / production_manager — swap the trailer's paint step between
  /// PAINT_A and PAINT_B. Throws on failure (e.g. ≥25ft trailer routed to A);
  /// refreshes on success.
  Future<void> setPaintBooth(String code) async {
    await _repository.setPaintBooth(trailerId, code);
    if (!isClosed) await load();
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

  /// Builds the History tab feed by merging three event sources into one
  /// time-ordered list:
  ///   • production step completions — the record of *which account*
  ///     completed each stage of the queue,
  ///   • step roll-backs (reversals), and
  ///   • generic audit-log events.
  List<HistoryEntry> _buildHistory(Map<String, dynamic> historyPayload) {
    final entries = <HistoryEntry>[];

    // Generic audit-log events (priority changes, jump-to-step, etc.).
    final auditLogs = _asMapList(historyPayload['auditLogs']);
    entries.addAll(auditLogs.map(HistoryEntry.fromJson));

    // Production steps — completions and roll-backs.
    final steps = _asMapList(historyPayload['steps']);
    for (final step in steps) {
      final department = step['department'] as Map<String, dynamic>?;
      final deptName = department?['displayName'] as String? ??
          department?['code'] as String? ??
          'Stage';
      final stepOrder = _toInt(step['stepOrder']);
      final isRework = step['isRework'] == true;
      final stageLabel =
          stepOrder != null ? 'Stage $stepOrder of the queue' : null;

      // A completed step records the account that finished the stage.
      final completedAt = _parseDate(step['completedAt']);
      if (step['status'] == 'complete' && completedAt != null) {
        final completedBy = step['completedByUser'] as Map<String, dynamic>?;
        entries.add(HistoryEntry(
          action:
              isRework ? '$deptName completed (rework)' : '$deptName completed',
          userName: completedBy?['fullName'] as String?,
          timestamp: completedAt,
          details: stageLabel,
          eventType: 'step_completed',
        ));
      }

      // Roll-backs recorded against this step.
      for (final rev in _asMapList(step['stepReversals'])) {
        final reversedBy = rev['reversedByUser'] as Map<String, dynamic>?;
        entries.add(HistoryEntry(
          action: '$deptName rolled back',
          userName: reversedBy?['fullName'] as String?,
          timestamp: _parseDate(rev['reversedAt']),
          details: rev['reason'] as String?,
          eventType: 'step_reversed',
        ));
      }
    }

    // QC inspections — pass/fail outcome and the inspector account.
    final qcInspections = _asMapList(historyPayload['qcInspections']);
    for (final inspection in qcInspections) {
      final productionStep =
          inspection['productionStep'] as Map<String, dynamic>?;
      final stepDept = productionStep?['department'] as Map<String, dynamic>?;
      final isFinalQc = inspection['isFinalQc'] == true;
      final qcLabel = isFinalQc
          ? 'Final QC'
          : ((stepDept?['code'] as String?)?.replaceAll('_', ' ').toUpperCase() ??
              'QC');

      final passed = inspection['result'] == 'pass';
      final inspector = inspection['inspectorUser'] as Map<String, dynamic>?;
      final attempt = _toInt(inspection['attemptNumber']);
      final reworkDept =
          inspection['reworkTargetDept'] as Map<String, dynamic>?;
      final reworkName = reworkDept?['displayName'] as String? ??
          reworkDept?['code'] as String?;
      final failNotes = (inspection['failNotes'] as String?)?.trim();

      final detailParts = <String>[
        if (attempt != null && attempt > 1) 'Attempt $attempt',
        if (!passed && reworkName != null && reworkName.isNotEmpty)
          'Sent back to $reworkName',
        if (!passed && failNotes != null && failNotes.isNotEmpty) failNotes,
      ];

      entries.add(HistoryEntry(
        action: passed
            ? '$qcLabel inspection — passed'
            : '$qcLabel inspection — failed',
        userName: inspector?['fullName'] as String?,
        timestamp: _parseDate(inspection['inspectedAt']),
        details: detailParts.isEmpty ? null : detailParts.join(' • '),
        eventType: passed ? 'qc_pass' : 'qc_fail',
      ));
    }

    // Newest first; entries without a timestamp sink to the bottom.
    entries.sort((a, b) {
      final at = a.timestamp;
      final bt = b.timestamp;
      if (at == null && bt == null) return 0;
      if (at == null) return 1;
      if (bt == null) return -1;
      return bt.compareTo(at);
    });

    return entries;
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
