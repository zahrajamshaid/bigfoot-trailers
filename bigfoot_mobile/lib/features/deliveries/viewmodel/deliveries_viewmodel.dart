import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/websocket/ws_client.dart';
import '../../../core/websocket/ws_event_stream.dart';
import '../../../data/models/delivery.dart';
import '../../../data/models/delivery_batch.dart';
import '../../../domain/repositories/delivery_repository.dart';

// Re-export for screens that need it
export '../../../domain/repositories/delivery_repository.dart' show DeliveryFormData;

sealed class DeliveriesState extends Equatable {
  const DeliveriesState();

  @override
  List<Object?> get props => [];
}

class DeliveriesInitial extends DeliveriesState {
  const DeliveriesInitial();
}

class DeliveriesLoading extends DeliveriesState {
  const DeliveriesLoading();
}

class DeliveriesLoaded extends DeliveriesState {
  final List<Delivery> deliveries;
  final String? status;
  final String? deliveryType;
  final int? driverUserId;
  final String? dateFrom;
  final String? dateTo;

  const DeliveriesLoaded({
    required this.deliveries,
    this.status,
    this.deliveryType,
    this.driverUserId,
    this.dateFrom,
    this.dateTo,
  });

  DeliveriesLoaded copyWith({
    List<Delivery>? deliveries,
    String? status,
    String? deliveryType,
    int? driverUserId,
    String? dateFrom,
    String? dateTo,
  }) {
    return DeliveriesLoaded(
      deliveries: deliveries ?? this.deliveries,
      status: status ?? this.status,
      deliveryType: deliveryType ?? this.deliveryType,
      driverUserId: driverUserId ?? this.driverUserId,
      dateFrom: dateFrom ?? this.dateFrom,
      dateTo: dateTo ?? this.dateTo,
    );
  }

  @override
  List<Object?> get props => [deliveries, status, deliveryType, driverUserId, dateFrom, dateTo];
}

class DeliveriesError extends DeliveriesState {
  final String message;

  const DeliveriesError(this.message);

  @override
  List<Object?> get props => [message];
}

class DeliveriesViewModel extends Cubit<DeliveriesState> {
  final DeliveryRepository _repository;
  final WsClient? _ws;
  StreamSubscription<WsEvent>? _wsSub;
  String? _lastStatus;
  String? _lastDeliveryType;
  int? _lastDriverUserId;
  String? _lastDateFrom;
  String? _lastDateTo;

  DeliveriesViewModel({required DeliveryRepository repository, WsClient? ws})
      : _repository = repository,
        _ws = ws,
        super(const DeliveriesInitial()) {
    _wsSub = _ws?.events.listen(_onWsEvent);
  }

  Future<void> load({
    String? status,
    String? deliveryType,
    int? driverUserId,
    String? dateFrom,
    String? dateTo,
  }) async {
    _lastStatus = status;
    _lastDeliveryType = deliveryType;
    _lastDriverUserId = driverUserId;
    _lastDateFrom = dateFrom;
    _lastDateTo = dateTo;
    emit(const DeliveriesLoading());
    try {
      final deliveries = await _repository.getDeliveries(
        status: status,
        deliveryType: deliveryType,
        driverUserId: driverUserId,
        dateFrom: dateFrom,
        dateTo: dateTo,
      );
      emit(DeliveriesLoaded(
        deliveries: deliveries,
        status: status,
        deliveryType: deliveryType,
        driverUserId: driverUserId,
        dateFrom: dateFrom,
        dateTo: dateTo,
      ));
    } on ApiException catch (e) {
      emit(DeliveriesError(e.displayMessage));
    } on NetworkException catch (e) {
      emit(DeliveriesError(e.message));
    } catch (e) {
      emit(DeliveriesError('Failed to load deliveries: $e'));
    }
  }

  Future<Delivery> getById(int id) => _repository.getDelivery(id);

  Future<DeliveryFormData> getCreateFormData() => _repository.getCreateFormData();

  Future<void> createDelivery({
    required int trailerId,
    required String deliveryType,
    int? driverUserId,
    int? destinationLocationId,
    String? customerDeliveryAddress,
    double? balanceDue,
    int? deliveryBatchId,
  }) => _repository.createDelivery(
    trailerId: trailerId,
    deliveryType: deliveryType,
    driverUserId: driverUserId,
    destinationLocationId: destinationLocationId,
    customerDeliveryAddress: customerDeliveryAddress,
    balanceDue: balanceDue,
    deliveryBatchId: deliveryBatchId,
  );

  Future<void> markDeparted(int deliveryId) => _repository.markDeparted(deliveryId);

  Future<void> markFailed(int deliveryId, String failReason) =>
      _repository.markFailed(deliveryId, failReason);

  Future<void> completeDelivery({
    required int deliveryId,
    required double paymentCollected,
    required String paymentMethod,
    required bool tcAccepted,
    String? signatureUrl,
    double? gpsLat,
    double? gpsLng,
    List<String> photoStorageKeys = const [],
  }) => _repository.completeDelivery(
    deliveryId: deliveryId,
    paymentCollected: paymentCollected,
    paymentMethod: paymentMethod,
    tcAccepted: tcAccepted,
    signatureUrl: signatureUrl,
    gpsLat: gpsLat,
    gpsLng: gpsLng,
    photoStorageKeys: photoStorageKeys,
  );

  Future<void> uploadPhotos({
    required int deliveryId,
    required List<String> storageKeys,
    String photoType = 'proof_of_delivery',
  }) => _repository.uploadPhotos(
    deliveryId: deliveryId,
    storageKeys: storageKeys,
    photoType: photoType,
  );

  Future<List<DeliveryBatch>> getBatches() => _repository.getBatches();

  Future<void> createBatch({
    required String batchNumber,
    required String batchType,
    int? driverUserId,
    int? destinationLocationId,
    String? destinationName,
  }) => _repository.createBatch(
    batchNumber: batchNumber,
    batchType: batchType,
    driverUserId: driverUserId,
    destinationLocationId: destinationLocationId,
    destinationName: destinationName,
  );

  Future<void> updateBatch({
    required int batchId,
    int? driverUserId,
    int? destinationLocationId,
    String? destinationName,
    List<int>? addTrailerIds,
    List<int>? removeDeliveryIds,
  }) => _repository.updateBatch(
    batchId: batchId,
    driverUserId: driverUserId,
    destinationLocationId: destinationLocationId,
    destinationName: destinationName,
    addTrailerIds: addTrailerIds,
    removeDeliveryIds: removeDeliveryIds,
  );

  Future<void> dispatchBatch(int batchId) => _repository.dispatchBatch(batchId);

  Future<void> completeFactoryPickup(int id) => _repository.completeFactoryPickup(id);

  void _onWsEvent(WsEvent event) {
    if (!const {
      WsEventType.deliveryDispatched,
      WsEventType.deliveryComplete,
      WsEventType.trailerReady,
    }.contains(event.type)) {
      return;
    }
    if (!isClosed) {
      load(
        status: _lastStatus,
        deliveryType: _lastDeliveryType,
        driverUserId: _lastDriverUserId,
        dateFrom: _lastDateFrom,
        dateTo: _lastDateTo,
      );
    }
  }

  @override
  Future<void> close() {
    _wsSub?.cancel();
    return super.close();
  }
}
