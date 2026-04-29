// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'delivery_batch.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

DeliveryBatch _$DeliveryBatchFromJson(Map<String, dynamic> json) =>
    DeliveryBatch(
      id: (json['id'] as num).toInt(),
      batchNumber: json['batchNumber'] as String,
      batchType: json['batchType'] as String,
      status: json['status'] as String,
      driverUserId: (json['driverUserId'] as num?)?.toInt(),
      destinationLocationId: (json['destinationLocationId'] as num?)?.toInt(),
      destinationName: json['destinationName'] as String?,
      departedAt: json['departedAt'] == null
          ? null
          : DateTime.parse(json['departedAt'] as String),
      completedAt: json['completedAt'] == null
          ? null
          : DateTime.parse(json['completedAt'] as String),
      createdAt: json['createdAt'] == null
          ? null
          : DateTime.parse(json['createdAt'] as String),
      driverUser: json['driverUser'] == null
          ? null
          : DeliveryUserInfo.fromJson(
              json['driverUser'] as Map<String, dynamic>,
            ),
      destinationLocation: json['destinationLocation'] == null
          ? null
          : DeliveryLocationInfo.fromJson(
              json['destinationLocation'] as Map<String, dynamic>,
            ),
      deliveries: (json['deliveries'] as List<dynamic>?)
          ?.map((e) => BatchDeliveryItem.fromJson(e as Map<String, dynamic>))
          .toList(),
    );

Map<String, dynamic> _$DeliveryBatchToJson(DeliveryBatch instance) =>
    <String, dynamic>{
      'id': instance.id,
      'batchNumber': instance.batchNumber,
      'batchType': instance.batchType,
      'status': instance.status,
      'driverUserId': instance.driverUserId,
      'destinationLocationId': instance.destinationLocationId,
      'destinationName': instance.destinationName,
      'departedAt': instance.departedAt?.toIso8601String(),
      'completedAt': instance.completedAt?.toIso8601String(),
      'createdAt': instance.createdAt?.toIso8601String(),
      'driverUser': instance.driverUser,
      'destinationLocation': instance.destinationLocation,
      'deliveries': instance.deliveries,
    };

BatchDeliveryItem _$BatchDeliveryItemFromJson(Map<String, dynamic> json) =>
    BatchDeliveryItem(
      id: (json['id'] as num).toInt(),
      trailerId: (json['trailerId'] as num).toInt(),
      status: json['status'] as String,
      trailer: json['trailer'] == null
          ? null
          : DeliveryTrailerInfo.fromJson(
              json['trailer'] as Map<String, dynamic>,
            ),
    );

Map<String, dynamic> _$BatchDeliveryItemToJson(BatchDeliveryItem instance) =>
    <String, dynamic>{
      'id': instance.id,
      'trailerId': instance.trailerId,
      'status': instance.status,
      'trailer': instance.trailer,
    };
