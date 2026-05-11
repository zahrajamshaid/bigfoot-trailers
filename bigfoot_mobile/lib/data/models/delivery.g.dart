// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'delivery.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Delivery _$DeliveryFromJson(Map<String, dynamic> json) => Delivery(
  id: (json['id'] as num).toInt(),
  trailerId: (json['trailerId'] as num).toInt(),
  driverUserId: (json['driverUserId'] as num?)?.toInt(),
  destinationLocationId: (json['destinationLocationId'] as num?)?.toInt(),
  customerDeliveryAddress: json['customerDeliveryAddress'] as String?,
  deliveryType: json['deliveryType'] as String,
  status: json['status'] as String,
  balanceDue: (json['balanceDue'] as num?)?.toDouble(),
  paymentCollected: (json['paymentCollected'] as num?)?.toDouble(),
  paymentMethod: json['paymentMethod'] as String?,
  failReason: json['failReason'] as String?,
  tcAccepted: json['tcAccepted'] as bool?,
  departedAt: json['departedAt'] == null
      ? null
      : DateTime.parse(json['departedAt'] as String),
  deliveredAt: json['deliveredAt'] == null
      ? null
      : DateTime.parse(json['deliveredAt'] as String),
  createdAt: json['createdAt'] == null
      ? null
      : DateTime.parse(json['createdAt'] as String),
  deliveryBatchId: (json['deliveryBatchId'] as num?)?.toInt(),
  signatureUrl: json['signatureUrl'] as String?,
  gpsLat: (json['gpsLat'] as num?)?.toDouble(),
  gpsLng: (json['gpsLng'] as num?)?.toDouble(),
  tcAcceptedAt: json['tcAcceptedAt'] == null
      ? null
      : DateTime.parse(json['tcAcceptedAt'] as String),
  trailer: json['trailer'] == null
      ? null
      : DeliveryTrailerInfo.fromJson(json['trailer'] as Map<String, dynamic>),
  driverUser: json['driverUser'] == null
      ? null
      : DeliveryUserInfo.fromJson(json['driverUser'] as Map<String, dynamic>),
  destinationLocation: json['destinationLocation'] == null
      ? null
      : DeliveryLocationInfo.fromJson(
          json['destinationLocation'] as Map<String, dynamic>,
        ),
  deliveryPhotos: (json['deliveryPhotos'] as List<dynamic>?)
      ?.map((e) => DeliveryPhoto.fromJson(e as Map<String, dynamic>))
      .toList(),
);

Map<String, dynamic> _$DeliveryToJson(Delivery instance) => <String, dynamic>{
  'id': instance.id,
  'trailerId': instance.trailerId,
  'driverUserId': instance.driverUserId,
  'destinationLocationId': instance.destinationLocationId,
  'customerDeliveryAddress': instance.customerDeliveryAddress,
  'deliveryType': instance.deliveryType,
  'status': instance.status,
  'balanceDue': instance.balanceDue,
  'paymentCollected': instance.paymentCollected,
  'paymentMethod': instance.paymentMethod,
  'failReason': instance.failReason,
  'tcAccepted': instance.tcAccepted,
  'departedAt': instance.departedAt?.toIso8601String(),
  'deliveredAt': instance.deliveredAt?.toIso8601String(),
  'createdAt': instance.createdAt?.toIso8601String(),
  'deliveryBatchId': instance.deliveryBatchId,
  'signatureUrl': instance.signatureUrl,
  'gpsLat': instance.gpsLat,
  'gpsLng': instance.gpsLng,
  'tcAcceptedAt': instance.tcAcceptedAt?.toIso8601String(),
  'trailer': instance.trailer,
  'driverUser': instance.driverUser,
  'destinationLocation': instance.destinationLocation,
  'deliveryPhotos': instance.deliveryPhotos,
};

DeliveryTrailerInfo _$DeliveryTrailerInfoFromJson(Map<String, dynamic> json) =>
    DeliveryTrailerInfo(
      id: (json['id'] as num).toInt(),
      soNumber: json['soNumber'] as String,
      trailerModel: json['trailerModel'] == null
          ? null
          : DeliveryTrailerModelInfo.fromJson(
              json['trailerModel'] as Map<String, dynamic>,
            ),
      customer: json['customer'] == null
          ? null
          : DeliveryCustomerInfo.fromJson(
              json['customer'] as Map<String, dynamic>,
            ),
    );

Map<String, dynamic> _$DeliveryTrailerInfoToJson(
  DeliveryTrailerInfo instance,
) => <String, dynamic>{
  'id': instance.id,
  'soNumber': instance.soNumber,
  'trailerModel': instance.trailerModel,
  'customer': instance.customer,
};

DeliveryTrailerModelInfo _$DeliveryTrailerModelInfoFromJson(
  Map<String, dynamic> json,
) => DeliveryTrailerModelInfo(
  id: (json['id'] as num).toInt(),
  displayName: json['displayName'] as String,
  series: json['series'] as String,
);

Map<String, dynamic> _$DeliveryTrailerModelInfoToJson(
  DeliveryTrailerModelInfo instance,
) => <String, dynamic>{
  'id': instance.id,
  'displayName': instance.displayName,
  'series': instance.series,
};

DeliveryCustomerInfo _$DeliveryCustomerInfoFromJson(
  Map<String, dynamic> json,
) => DeliveryCustomerInfo(
  id: (json['id'] as num).toInt(),
  name: json['name'] as String,
  smsPhone: json['smsPhone'] as String?,
  smsOptOut: json['smsOptOut'] as bool?,
);

Map<String, dynamic> _$DeliveryCustomerInfoToJson(
  DeliveryCustomerInfo instance,
) => <String, dynamic>{
  'id': instance.id,
  'name': instance.name,
  'smsPhone': instance.smsPhone,
  'smsOptOut': instance.smsOptOut,
};

DeliveryUserInfo _$DeliveryUserInfoFromJson(Map<String, dynamic> json) =>
    DeliveryUserInfo(
      id: (json['id'] as num).toInt(),
      fullName: json['fullName'] as String,
    );

Map<String, dynamic> _$DeliveryUserInfoToJson(DeliveryUserInfo instance) =>
    <String, dynamic>{'id': instance.id, 'fullName': instance.fullName};

DeliveryLocationInfo _$DeliveryLocationInfoFromJson(
  Map<String, dynamic> json,
) => DeliveryLocationInfo(
  id: (json['id'] as num).toInt(),
  name: json['name'] as String,
  city: json['city'] as String?,
  state: json['state'] as String?,
  shortLabel: json['shortLabel'] as String?,
);

Map<String, dynamic> _$DeliveryLocationInfoToJson(
  DeliveryLocationInfo instance,
) => <String, dynamic>{
  'id': instance.id,
  'name': instance.name,
  'city': instance.city,
  'state': instance.state,
  'shortLabel': instance.shortLabel,
};

DeliveryPhoto _$DeliveryPhotoFromJson(Map<String, dynamic> json) =>
    DeliveryPhoto(
      id: (json['id'] as num).toInt(),
      storageUrl: json['storageUrl'] as String,
      storageKey: json['storageKey'] as String,
      photoType: json['photoType'] as String,
      takenAt: json['takenAt'] == null
          ? null
          : DateTime.parse(json['takenAt'] as String),
    );

Map<String, dynamic> _$DeliveryPhotoToJson(DeliveryPhoto instance) =>
    <String, dynamic>{
      'id': instance.id,
      'storageUrl': instance.storageUrl,
      'storageKey': instance.storageKey,
      'photoType': instance.photoType,
      'takenAt': instance.takenAt?.toIso8601String(),
    };
