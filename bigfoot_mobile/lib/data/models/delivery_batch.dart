import 'package:json_annotation/json_annotation.dart';

import 'delivery.dart';

part 'delivery_batch.g.dart';

@JsonSerializable()
class DeliveryBatch {
  final int id;
  final String batchNumber;
  final String batchType; // dealer, bf_location
  final String status; // building, scheduled, in_transit, complete
  final int? driverUserId;
  final int? destinationLocationId;
  final String? destinationName;
  final DateTime? departedAt;
  final DateTime? completedAt;
  final DateTime? createdAt;
  final DeliveryUserInfo? driverUser;
  final DeliveryLocationInfo? destinationLocation;
  final List<BatchDeliveryItem>? deliveries;

  const DeliveryBatch({
    required this.id,
    required this.batchNumber,
    required this.batchType,
    required this.status,
    this.driverUserId,
    this.destinationLocationId,
    this.destinationName,
    this.departedAt,
    this.completedAt,
    this.createdAt,
    this.driverUser,
    this.destinationLocation,
    this.deliveries,
  });

  factory DeliveryBatch.fromJson(Map<String, dynamic> json) =>
      _$DeliveryBatchFromJson(json);
  Map<String, dynamic> toJson() => _$DeliveryBatchToJson(this);

  /// Human-readable status. The raw `building` state is shown as "Open" — a
  /// batch that is assembled and awaiting delivery completion.
  String get statusLabel {
    switch (status) {
      case 'building':
      case 'scheduled':
        return 'Open';
      case 'in_transit':
        return 'In Transit';
      case 'complete':
        return 'Completed';
      default:
        return status;
    }
  }
}

@JsonSerializable()
class BatchDeliveryItem {
  final int id;
  final int trailerId;
  final String status;
  final DeliveryTrailerInfo? trailer;

  const BatchDeliveryItem({
    required this.id,
    required this.trailerId,
    required this.status,
    this.trailer,
  });

  factory BatchDeliveryItem.fromJson(Map<String, dynamic> json) =>
      _$BatchDeliveryItemFromJson(json);
  Map<String, dynamic> toJson() => _$BatchDeliveryItemToJson(this);
}
