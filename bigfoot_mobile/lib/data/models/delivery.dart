import 'package:json_annotation/json_annotation.dart';

part 'delivery.g.dart';

@JsonSerializable()
class Delivery {
  final int id;
  final int trailerId;
  final int? driverUserId;
  final int? destinationLocationId;
  final String? customerDeliveryAddress;
  final String deliveryType; // factory_pickup, stack_to_dealer, stack_to_location, single_pull
  final String status; // scheduled, in_transit, delivered, failed
  final double? balanceDue;
  final double? paymentCollected;
  final String? paymentMethod; // cashiers_check, debit, cash
  final String? failReason;
  final bool? tcAccepted;
  final DateTime? departedAt;
  final DateTime? deliveredAt;
  final DateTime? createdAt;
  final int? deliveryBatchId;
  final String? signatureUrl;
  final double? gpsLat;
  final double? gpsLng;
  final DateTime? tcAcceptedAt;

  // Expanded backend relations
  final DeliveryTrailerInfo? trailer;
  final DeliveryUserInfo? driverUser;
  final DeliveryLocationInfo? destinationLocation;
  final List<DeliveryPhoto>? deliveryPhotos;

  const Delivery({
    required this.id,
    required this.trailerId,
    this.driverUserId,
    this.destinationLocationId,
    this.customerDeliveryAddress,
    required this.deliveryType,
    required this.status,
    this.balanceDue,
    this.paymentCollected,
    this.paymentMethod,
    this.failReason,
    this.tcAccepted,
    this.departedAt,
    this.deliveredAt,
    this.createdAt,
    this.deliveryBatchId,
    this.signatureUrl,
    this.gpsLat,
    this.gpsLng,
    this.tcAcceptedAt,
    this.trailer,
    this.driverUser,
    this.destinationLocation,
    this.deliveryPhotos,
  });

  String get soNumber => trailer?.soNumber ?? 'SO-$trailerId';
  String get modelName => trailer?.trailerModel?.displayName ?? 'Unknown model';
  String get customerName => trailer?.customer?.name ?? 'Stock Build';
  String get driverName => driverUser?.fullName ?? '-';
  String get destinationLabel {
    if (destinationLocation != null) {
      return destinationLocation!.name;
    }
    return customerDeliveryAddress ?? '-';
  }

  factory Delivery.fromJson(Map<String, dynamic> json) =>
      _$DeliveryFromJson(json);
  Map<String, dynamic> toJson() => _$DeliveryToJson(this);
}

@JsonSerializable()
class DeliveryTrailerInfo {
  final int id;
  final String soNumber;
  final DeliveryTrailerModelInfo? trailerModel;
  final DeliveryCustomerInfo? customer;

  const DeliveryTrailerInfo({
    required this.id,
    required this.soNumber,
    this.trailerModel,
    this.customer,
  });

  factory DeliveryTrailerInfo.fromJson(Map<String, dynamic> json) =>
      _$DeliveryTrailerInfoFromJson(json);
  Map<String, dynamic> toJson() => _$DeliveryTrailerInfoToJson(this);
}

@JsonSerializable()
class DeliveryTrailerModelInfo {
  final int id;
  final String displayName;
  final String series;

  const DeliveryTrailerModelInfo({
    required this.id,
    required this.displayName,
    required this.series,
  });

  factory DeliveryTrailerModelInfo.fromJson(Map<String, dynamic> json) =>
      _$DeliveryTrailerModelInfoFromJson(json);
  Map<String, dynamic> toJson() => _$DeliveryTrailerModelInfoToJson(this);
}

@JsonSerializable()
class DeliveryCustomerInfo {
  final int id;
  final String name;
  final String? smsPhone;
  final bool? smsOptOut;

  const DeliveryCustomerInfo({
    required this.id,
    required this.name,
    this.smsPhone,
    this.smsOptOut,
  });

  factory DeliveryCustomerInfo.fromJson(Map<String, dynamic> json) =>
      _$DeliveryCustomerInfoFromJson(json);
  Map<String, dynamic> toJson() => _$DeliveryCustomerInfoToJson(this);
}

@JsonSerializable()
class DeliveryUserInfo {
  final int id;
  final String fullName;

  const DeliveryUserInfo({required this.id, required this.fullName});

  factory DeliveryUserInfo.fromJson(Map<String, dynamic> json) =>
      _$DeliveryUserInfoFromJson(json);
  Map<String, dynamic> toJson() => _$DeliveryUserInfoToJson(this);
}

@JsonSerializable()
class DeliveryLocationInfo {
  final int id;
  final String name;
  final String? city;
  final String? state;
  final String? shortLabel;

  const DeliveryLocationInfo({
    required this.id,
    required this.name,
    this.city,
    this.state,
    this.shortLabel,
  });

  factory DeliveryLocationInfo.fromJson(Map<String, dynamic> json) =>
      _$DeliveryLocationInfoFromJson(json);
  Map<String, dynamic> toJson() => _$DeliveryLocationInfoToJson(this);
}

@JsonSerializable()
class DeliveryPhoto {
  final int id;
  final String storageUrl;
  final String storageKey;
  final String photoType;
  final DateTime? takenAt;

  const DeliveryPhoto({
    required this.id,
    required this.storageUrl,
    required this.storageKey,
    required this.photoType,
    this.takenAt,
  });

  factory DeliveryPhoto.fromJson(Map<String, dynamic> json) =>
      _$DeliveryPhotoFromJson(json);
  Map<String, dynamic> toJson() => _$DeliveryPhotoToJson(this);
}
