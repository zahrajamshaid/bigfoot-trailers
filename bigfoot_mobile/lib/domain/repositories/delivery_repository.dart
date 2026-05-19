import '../../data/models/delivery.dart';
import '../../data/models/delivery_batch.dart';
import '../../data/models/stock_inventory.dart';
import '../../data/models/user.dart';

class DeliveryFormData {
  final List<Map<String, dynamic>> trailers;
  final List<User> drivers;
  final List<DeliveryLocationInfo> locations;
  final List<DeliveryBatch> batches;

  const DeliveryFormData({
    required this.trailers,
    required this.drivers,
    required this.locations,
    required this.batches,
  });
}

/// Abstract contract for delivery data operations.
abstract class DeliveryRepository {
  Future<List<Delivery>> getDeliveries({
    String? status,
    String? deliveryType,
    int? driverUserId,
    String? dateFrom,
    String? dateTo,
  });

  Future<Delivery> getDelivery(int id);

  Future<DeliveryFormData> getCreateFormData();

  Future<void> createDelivery({
    required int trailerId,
    required String deliveryType,
    int? driverUserId,
    int? destinationLocationId,
    String? customerDeliveryAddress,
    String? contactPhone,
    double? balanceDue,
    int? deliveryBatchId,
    // factory_pickup only — recorded as already picked up on creation.
    String? pickedUpByName,
    double? paymentCollected,
  });

  Future<void> markFailed(int deliveryId, String failReason);

  /// Deletes a delivery (transport manager / owner). The trailer is freed back
  /// to ready_for_delivery at its prior location.
  Future<void> deleteDelivery(int deliveryId);

  /// One-tap completion — the driver confirms the trailer was delivered.
  /// [paymentCollected] is the optional balance the driver collected on
  /// delivery; omit it when nothing was collected.
  Future<void> completeDelivery(int deliveryId, {double? paymentCollected});

  /// Trailers currently parked at each stock-location yard.
  Future<List<StockLocationGroup>> getStockInventory();

  Future<void> uploadPhotos({
    required int deliveryId,
    required List<String> storageKeys,
    String photoType,
  });

  Future<List<DeliveryBatch>> getBatches();

  Future<DeliveryBatch> createBatch({
    required String batchNumber,
    required String batchType,
    int? driverUserId,
    int? destinationLocationId,
    String? destinationName,
    List<int>? trailerIds,
  });

  Future<void> updateBatch({
    required int batchId,
    int? driverUserId,
    int? destinationLocationId,
    String? destinationName,
    List<int>? addTrailerIds,
    List<int>? removeDeliveryIds,
  });

  Future<void> dispatchBatch(int batchId);

  /// Completes a whole batch in one action — every in-transit trailer in the
  /// batch is marked delivered. [photoStorageKeys] are optional proof photos.
  Future<void> completeBatch(int batchId, {List<String>? photoStorageKeys});

  /// Permanently deletes a batch and all of its deliveries. Trailers still
  /// held by a not-yet-delivered delivery are freed back to ready_for_delivery.
  Future<void> deleteBatch(int batchId);

  /// Completes a factory pickup, optionally recording who collected the
  /// trailer and any balance taken at pickup.
  Future<void> completeFactoryPickup(
    int id, {
    String? pickedUpByName,
    double? paymentCollected,
  });
}
