import '../../data/models/delivery.dart';
import '../../data/models/delivery_batch.dart';
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
    double? balanceDue,
    int? deliveryBatchId,
  });

  Future<void> markDeparted(int deliveryId);

  Future<void> markFailed(int deliveryId, String failReason);

  Future<void> completeDelivery({
    required int deliveryId,
    required double paymentCollected,
    required String paymentMethod,
    required bool tcAccepted,
    String? signatureUrl,
    double? gpsLat,
    double? gpsLng,
    List<String> photoStorageKeys,
  });

  Future<void> uploadPhotos({
    required int deliveryId,
    required List<String> storageKeys,
    String photoType,
  });

  Future<List<DeliveryBatch>> getBatches();

  Future<void> createBatch({
    required String batchNumber,
    required String batchType,
    int? driverUserId,
    int? destinationLocationId,
    String? destinationName,
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

  Future<void> completeFactoryPickup(int id);
}
