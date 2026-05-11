import '../../core/constants/api_endpoints.dart';
import '../../core/network/dio_client.dart';
import '../../domain/repositories/delivery_repository.dart';
import '../../domain/repositories/location_repository.dart';
import '../models/delivery.dart';
import '../models/delivery_batch.dart';
import '../models/user.dart';

class DeliveryRepositoryImpl implements DeliveryRepository {
  final DioClient _api;
  final LocationRepository _locationRepo;

  DeliveryRepositoryImpl({
    required DioClient api,
    required LocationRepository locationRepository,
  })  : _api = api,
        _locationRepo = locationRepository;

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
    final driversFuture = _api.get<Map<String, dynamic>>(
      ApiEndpoints.users,
      queryParameters: {
        'page': 1,
        // Users query DTO enforces limit <= 100.
        'limit': 100,
        'role': UserRole.driver,
        'isActive': true,
      },
      fromJson: (d) => d as Map<String, dynamic>,
    );
    final batchesFuture = _api.get<List<dynamic>>(
      ApiEndpoints.deliveryBatches,
      fromJson: (d) => d as List<dynamic>,
    );

    final trailersResp = await trailersFuture;
    final batchesResp = await batchesFuture;

    Map<String, dynamic> driversEnvelope = const <String, dynamic>{};
    try {
      final driversResp = await driversFuture;
      driversEnvelope = driversResp.data ?? const <String, dynamic>{};
    } catch (_) {
      // Some roles (for example transport_manager) may not have /users read access.
      // Driver assignment is optional when creating a delivery, so proceed without
      // blocking the form.
      driversEnvelope = const <String, dynamic>{};
    }

    final trailersEnvelope = trailersResp.data ?? {};
    final trailers = ((trailersEnvelope['trailers'] as List<dynamic>?) ?? [])
        .whereType<Map<String, dynamic>>()
        .toList();

    final drivers = ((driversEnvelope['users'] as List<dynamic>?) ?? [])
      .whereType<Map<String, dynamic>>()
      .map((u) => User(
          id: (u['id'] as num).toInt(),
          email: (u['email'] as String?) ?? '',
          name: (u['fullName'] as String?) ?? (u['name'] as String?) ?? '',
          role: (u['role'] as String?) ?? UserRole.driver,
          departmentId: (u['primaryDepartmentId'] as num?)?.toInt(),
          locationId: (u['primaryLocationId'] as num?)?.toInt(),
          isActive: u['isActive'] as bool?,
          createdAt: u['createdAt'] != null
            ? DateTime.tryParse(u['createdAt'].toString())
            : null,
        ))
      .toList();

    final batches = (batchesResp.data ?? [])
        .whereType<Map<String, dynamic>>()
        .map(DeliveryBatch.fromJson)
        .toList();

    // Stock destinations are sourced live from the API so renames or new
    // yards (e.g. Tappahannock, Tallahassee) propagate without an app build.
    final liveLocations = await _locationRepo.getStockLocations();
    final locations = liveLocations
        .map((l) => DeliveryLocationInfo(
              id: l.id,
              name: l.name,
              city: l.city,
              state: l.state,
              shortLabel: l.shortLabel,
            ))
        .toList();

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
