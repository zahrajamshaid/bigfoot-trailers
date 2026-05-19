import '../../core/constants/api_endpoints.dart';
import '../../core/network/dio_client.dart';
import '../../domain/repositories/delivery_repository.dart';
import '../../domain/repositories/location_repository.dart';
import '../models/delivery.dart';
import '../models/delivery_batch.dart';
import '../models/stock_inventory.dart';
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
      queryParameters: {
        'status': 'ready_for_delivery',
        // Drop trailers already committed to an open delivery so they can't
        // be added to another delivery or batch.
        'excludeOpenDeliveries': true,
        'limit': 100,
        'page': 1,
      },
      fromJson: (d) => d as Map<String, dynamic>,
    );
    // Dedicated drivers endpoint — readable by transport_manager + owner, so
    // the assignment dropdown populates regardless of who opens the form.
    final driversFuture = _api.get<List<dynamic>>(
      ApiEndpoints.usersDrivers,
      fromJson: (d) => d as List<dynamic>,
    );
    final batchesFuture = _api.get<List<dynamic>>(
      ApiEndpoints.deliveryBatches,
      fromJson: (d) => d as List<dynamic>,
    );

    final trailersResp = await trailersFuture;
    final batchesResp = await batchesFuture;

    List<dynamic> driversRaw = const [];
    try {
      final driversResp = await driversFuture;
      driversRaw = driversResp.data ?? const [];
    } catch (_) {
      // Driver assignment is optional when creating a delivery, so proceed
      // without blocking the form if the list can't be loaded.
      driversRaw = const [];
    }

    final trailersEnvelope = trailersResp.data ?? {};
    final trailers = ((trailersEnvelope['trailers'] as List<dynamic>?) ?? [])
        .whereType<Map<String, dynamic>>()
        .toList();

    final drivers = driversRaw
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
    String? contactPhone,
    double? balanceDue,
    int? deliveryBatchId,
    String? pickedUpByName,
    double? paymentCollected,
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
        if (contactPhone != null && contactPhone.isNotEmpty)
          'contactPhone': contactPhone,
        if (balanceDue != null) 'balanceDue': balanceDue,
        if (deliveryBatchId != null) 'deliveryBatchId': deliveryBatchId,
        if (pickedUpByName != null && pickedUpByName.isNotEmpty)
          'pickedUpByName': pickedUpByName,
        if (paymentCollected != null) 'paymentCollected': paymentCollected,
      },
    );
  }

  @override
  Future<void> markFailed(int deliveryId, String failReason) async {
    await _api.patch(
      ApiEndpoints.deliveryFail(deliveryId),
      data: {'failReason': failReason},
    );
  }

  @override
  Future<void> deleteDelivery(int deliveryId) async {
    await _api.delete(ApiEndpoints.delivery(deliveryId));
  }

  @override
  Future<void> completeDelivery(int deliveryId, {double? paymentCollected}) async {
    // One-tap completion. The backend marks the delivery delivered, updates
    // the trailer, and notifies the transport managers. The optional
    // paymentCollected lets the driver record a balance taken on delivery.
    await _api.post(
      ApiEndpoints.deliveryComplete(deliveryId),
      data: {
        if (paymentCollected != null) 'paymentCollected': paymentCollected,
      },
    );
  }

  @override
  Future<List<StockLocationGroup>> getStockInventory() async {
    final response = await _api.get<List<dynamic>>(
      ApiEndpoints.deliveryStockInventory,
      fromJson: (d) => d as List<dynamic>,
    );
    return (response.data ?? [])
        .whereType<Map<String, dynamic>>()
        .map(StockLocationGroup.fromJson)
        .toList();
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
  Future<DeliveryBatch> createBatch({
    required String batchNumber,
    required String batchType,
    int? driverUserId,
    int? destinationLocationId,
    String? destinationName,
    List<int>? trailerIds,
  }) async {
    final response = await _api.post<Map<String, dynamic>>(
      ApiEndpoints.deliveryBatches,
      data: {
        'batchNumber': batchNumber,
        'batchType': batchType,
        if (driverUserId != null) 'driverUserId': driverUserId,
        if (destinationLocationId != null) 'destinationLocationId': destinationLocationId,
        if (destinationName != null && destinationName.isNotEmpty) 'destinationName': destinationName,
        if (trailerIds != null && trailerIds.isNotEmpty) 'trailerIds': trailerIds,
      },
      fromJson: (d) => d as Map<String, dynamic>,
    );
    return DeliveryBatch.fromJson(response.data!);
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
  Future<void> completeBatch(int batchId, {List<String>? photoStorageKeys}) async {
    await _api.post(
      ApiEndpoints.deliveryBatchComplete(batchId),
      data: {
        if (photoStorageKeys != null && photoStorageKeys.isNotEmpty)
          'photoStorageKeys': photoStorageKeys,
      },
    );
  }

  @override
  Future<void> deleteBatch(int batchId) async {
    await _api.delete(ApiEndpoints.deliveryBatch(batchId));
  }

  @override
  Future<void> completeFactoryPickup(
    int id, {
    String? pickedUpByName,
    double? paymentCollected,
  }) async {
    await _api.post(
      ApiEndpoints.factoryPickupComplete(id),
      data: {
        if (pickedUpByName != null && pickedUpByName.isNotEmpty)
          'pickedUpByName': pickedUpByName,
        if (paymentCollected != null) 'paymentCollected': paymentCollected,
      },
    );
  }
}
