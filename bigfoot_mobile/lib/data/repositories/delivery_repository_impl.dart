import '../../core/constants/api_endpoints.dart';
import '../../core/network/dio_client.dart';
import '../../domain/repositories/delivery_repository.dart';
import '../models/delivery.dart';
import '../models/delivery_batch.dart';
import '../models/user.dart';

class DeliveryRepositoryImpl implements DeliveryRepository {
  final DioClient _api;

  DeliveryRepositoryImpl({required DioClient api}) : _api = api;

  @override
  Future<List<Delivery>> getDeliveries({
    String? status,
    String? deliveryType,
    int? driverUserId,
    String? dateFrom,
    String? dateTo,
  }) async {
    final params = <String, dynamic>{};
    if (status != null) params['status'] = status;
    if (deliveryType != null) params['deliveryType'] = deliveryType;
    if (driverUserId != null) params['driverUserId'] = driverUserId;
    if (dateFrom != null && dateFrom.isNotEmpty) params['dateFrom'] = dateFrom;
    if (dateTo != null && dateTo.isNotEmpty) params['dateTo'] = dateTo;

    final response = await _api.get<List<dynamic>>(
      ApiEndpoints.deliveries,
      queryParameters: params,
      fromJson: (d) => d as List<dynamic>,
    );

    return (response.data ?? [])
        .whereType<Map<String, dynamic>>()
        .map(Delivery.fromJson)
        .toList();
  }

  @override
  Future<Delivery> getDelivery(int id) async {
    final response = await _api.get<Map<String, dynamic>>(
      ApiEndpoints.delivery(id),
      fromJson: (d) => d as Map<String, dynamic>,
    );
    return Delivery.fromJson(response.data!);
  }

  @override
  Future<DeliveryFormData> getCreateFormData() async {
    final trailersFuture = _api.get<Map<String, dynamic>>(
      ApiEndpoints.trailers,
      queryParameters: {'status': 'ready_for_delivery', 'limit': 100, 'page': 1},
      fromJson: (d) => d as Map<String, dynamic>,
    );
    final driversFuture = _api.get<List<dynamic>>(
      ApiEndpoints.users,
      fromJson: (d) => d as List<dynamic>,
    );
    final batchesFuture = _api.get<List<dynamic>>(
      ApiEndpoints.deliveryBatches,
      fromJson: (d) => d as List<dynamic>,
    );

    final trailersResp = await trailersFuture;
    final driversResp = await driversFuture;
    final batchesResp = await batchesFuture;

    final trailersEnvelope = trailersResp.data ?? {};
    final trailers = ((trailersEnvelope['trailers'] as List<dynamic>?) ?? [])
        .whereType<Map<String, dynamic>>()
        .toList();

    final drivers = (driversResp.data ?? [])
        .whereType<Map<String, dynamic>>()
        .map(User.fromJson)
        .where((u) => u.role == UserRole.driver)
        .toList();

    final batches = (batchesResp.data ?? [])
        .whereType<Map<String, dynamic>>()
        .map(DeliveryBatch.fromJson)
        .toList();

    const locations = [
      DeliveryLocationInfo(id: 1, name: 'Bigfoot Trailers Mulberry', city: 'Mulberry', state: 'FL'),
      DeliveryLocationInfo(id: 2, name: 'Bigfoot Trailers Jacksonville', city: 'Jacksonville', state: 'FL'),
      DeliveryLocationInfo(id: 3, name: 'Bigfoot Trailers Ashland', city: 'Ashland', state: 'VA'),
      DeliveryLocationInfo(id: 4, name: 'Bigfoot Trailers Atlanta', city: 'Atlanta', state: 'GA'),
    ];

    return DeliveryFormData(
      trailers: trailers,
      drivers: drivers,
      locations: locations,
      batches: batches,
    );
  }

  @override
  Future<void> createDelivery({
    required int trailerId,
    required String deliveryType,
    int? driverUserId,
    int? destinationLocationId,
    String? customerDeliveryAddress,
    double? balanceDue,
    int? deliveryBatchId,
  }) async {
    await _api.post(
      ApiEndpoints.deliveries,
      data: {
        'trailerId': trailerId,
        'deliveryType': deliveryType,
        if (driverUserId != null) 'driverUserId': driverUserId,
        if (destinationLocationId != null) 'destinationLocationId': destinationLocationId,
        if (customerDeliveryAddress != null && customerDeliveryAddress.isNotEmpty)
          'customerDeliveryAddress': customerDeliveryAddress,
        if (balanceDue != null) 'balanceDue': balanceDue,
        if (deliveryBatchId != null) 'deliveryBatchId': deliveryBatchId,
      },
    );
  }

  @override
  Future<void> markDeparted(int deliveryId) async {
    await _api.patch(ApiEndpoints.deliveryDepart(deliveryId));
  }

  @override
  Future<void> markFailed(int deliveryId, String failReason) async {
    await _api.patch(
      ApiEndpoints.deliveryFail(deliveryId),
      data: {'failReason': failReason},
    );
  }

  @override
  Future<void> completeDelivery({
    required int deliveryId,
    required double paymentCollected,
    required String paymentMethod,
    required bool tcAccepted,
    String? signatureUrl,
    double? gpsLat,
    double? gpsLng,
    List<String> photoStorageKeys = const [],
  }) async {
    await _api.post(
      ApiEndpoints.deliveryComplete(deliveryId),
      data: {
        'paymentCollected': paymentCollected,
        'paymentMethod': paymentMethod,
        'tcAccepted': tcAccepted,
        if (signatureUrl != null && signatureUrl.isNotEmpty) 'signatureUrl': signatureUrl,
        if (gpsLat != null) 'gpsLat': gpsLat,
        if (gpsLng != null) 'gpsLng': gpsLng,
        if (photoStorageKeys.isNotEmpty) 'photoStorageKeys': photoStorageKeys,
      },
    );
  }

  @override
  Future<void> uploadPhotos({
    required int deliveryId,
    required List<String> storageKeys,
    String photoType = 'proof_of_delivery',
  }) async {
    await _api.post(
      ApiEndpoints.deliveryPhotos(deliveryId),
      data: {'storageKeys': storageKeys, 'photoType': photoType},
    );
  }

  @override
  Future<List<DeliveryBatch>> getBatches() async {
    final response = await _api.get<List<dynamic>>(
      ApiEndpoints.deliveryBatches,
      fromJson: (d) => d as List<dynamic>,
    );
    return (response.data ?? [])
        .whereType<Map<String, dynamic>>()
        .map(DeliveryBatch.fromJson)
        .toList();
  }

  @override
  Future<void> createBatch({
    required String batchNumber,
    required String batchType,
    int? driverUserId,
    int? destinationLocationId,
    String? destinationName,
  }) async {
    await _api.post(
      ApiEndpoints.deliveryBatches,
      data: {
        'batchNumber': batchNumber,
        'batchType': batchType,
        if (driverUserId != null) 'driverUserId': driverUserId,
        if (destinationLocationId != null) 'destinationLocationId': destinationLocationId,
        if (destinationName != null && destinationName.isNotEmpty) 'destinationName': destinationName,
      },
    );
  }

  @override
  Future<void> updateBatch({
    required int batchId,
    int? driverUserId,
    int? destinationLocationId,
    String? destinationName,
    List<int>? addTrailerIds,
    List<int>? removeDeliveryIds,
  }) async {
    await _api.patch(
      ApiEndpoints.deliveryBatch(batchId),
      data: {
        if (driverUserId != null) 'driverUserId': driverUserId,
        if (destinationLocationId != null) 'destinationLocationId': destinationLocationId,
        if (destinationName != null) 'destinationName': destinationName,
        if (addTrailerIds != null && addTrailerIds.isNotEmpty) 'addTrailerIds': addTrailerIds,
        if (removeDeliveryIds != null && removeDeliveryIds.isNotEmpty) 'removeDeliveryIds': removeDeliveryIds,
      },
    );
  }

  @override
  Future<void> dispatchBatch(int batchId) async {
    await _api.post(ApiEndpoints.deliveryBatchDepart(batchId));
  }

  @override
  Future<void> completeFactoryPickup(int id) async {
    await _api.post(ApiEndpoints.factoryPickupComplete(id));
  }
}
