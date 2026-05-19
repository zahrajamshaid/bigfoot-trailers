// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'trailer.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Trailer _$TrailerFromJson(Map<String, dynamic> json) => Trailer(
  id: (json['id'] as num).toInt(),
  soNumber: json['soNumber'] as String,
  vinNumber: json['vinNumber'] as String?,
  trailerModelId: (json['trailerModelId'] as num?)?.toInt(),
  customerId: (json['customerId'] as num?)?.toInt(),
  currentLocationId: (json['currentLocationId'] as num?)?.toInt(),
  createdByUserId: (json['createdByUserId'] as num?)?.toInt(),
  color: json['color'] as String?,
  size: json['sizeFt'] as String?,
  optionsNotes: json['optionsNotes'] as String?,
  specialNote: json['specialNote'] as String?,
  qbSoPdfStorageKey: json['qbSoPdfStorageKey'] as String?,
  status: json['status'] as String,
  saleStatus: json['saleStatus'] as String? ?? 'available',
  soldToName: json['soldToName'] as String?,
  globalPriority: (json['globalPriority'] as num?)?.toInt() ?? 9999,
  isStockBuild: json['isStockBuild'] as bool? ?? false,
  isHot: json['isHot'] as bool? ?? false,
  customerLocked: json['customerLocked'] as bool? ?? false,
  createdAt: json['createdAt'] == null
      ? null
      : DateTime.parse(json['createdAt'] as String),
  updatedAt: json['updatedAt'] == null
      ? null
      : DateTime.parse(json['updatedAt'] as String),
  trailerModel: json['trailerModel'] == null
      ? null
      : TrailerModelInfo.fromJson(json['trailerModel'] as Map<String, dynamic>),
  customer: json['customer'] == null
      ? null
      : CustomerInfo.fromJson(json['customer'] as Map<String, dynamic>),
  currentLocation: json['currentLocation'] == null
      ? null
      : LocationInfo.fromJson(json['currentLocation'] as Map<String, dynamic>),
  addons: (json['addons'] as List<dynamic>?)
      ?.map((e) => TrailerAddon.fromJson(e as Map<String, dynamic>))
      .toList(),
  productionSteps: (json['productionSteps'] as List<dynamic>?)
      ?.map((e) => ProductionStepSummary.fromJson(e as Map<String, dynamic>))
      .toList(),
);

Map<String, dynamic> _$TrailerToJson(Trailer instance) => <String, dynamic>{
  'id': instance.id,
  'soNumber': instance.soNumber,
  'vinNumber': instance.vinNumber,
  'trailerModelId': instance.trailerModelId,
  'customerId': instance.customerId,
  'currentLocationId': instance.currentLocationId,
  'createdByUserId': instance.createdByUserId,
  'color': instance.color,
  'sizeFt': instance.size,
  'optionsNotes': instance.optionsNotes,
  'specialNote': instance.specialNote,
  'qbSoPdfStorageKey': instance.qbSoPdfStorageKey,
  'status': instance.status,
  'saleStatus': instance.saleStatus,
  'soldToName': instance.soldToName,
  'globalPriority': instance.globalPriority,
  'isStockBuild': instance.isStockBuild,
  'isHot': instance.isHot,
  'customerLocked': instance.customerLocked,
  'createdAt': instance.createdAt?.toIso8601String(),
  'updatedAt': instance.updatedAt?.toIso8601String(),
  'trailerModel': instance.trailerModel,
  'customer': instance.customer,
  'currentLocation': instance.currentLocation,
  'addons': instance.addons,
  'productionSteps': instance.productionSteps,
};

LocationInfo _$LocationInfoFromJson(Map<String, dynamic> json) => LocationInfo(
  id: (json['id'] as num).toInt(),
  code: json['code'] as String,
  name: json['name'] as String,
  city: json['city'] as String?,
  state: json['state'] as String?,
  shortLabel: json['shortLabel'] as String?,
);

Map<String, dynamic> _$LocationInfoToJson(LocationInfo instance) =>
    <String, dynamic>{
      'id': instance.id,
      'code': instance.code,
      'name': instance.name,
      'city': instance.city,
      'state': instance.state,
      'shortLabel': instance.shortLabel,
    };

TrailerModelInfo _$TrailerModelInfoFromJson(Map<String, dynamic> json) =>
    TrailerModelInfo(
      id: (json['id'] as num).toInt(),
      code: json['code'] as String,
      displayName: json['displayName'] as String,
      series: json['series'] as String,
      weightRating: json['weightRating'] as String?,
    );

Map<String, dynamic> _$TrailerModelInfoToJson(TrailerModelInfo instance) =>
    <String, dynamic>{
      'id': instance.id,
      'code': instance.code,
      'displayName': instance.displayName,
      'series': instance.series,
      'weightRating': instance.weightRating,
    };

CustomerInfo _$CustomerInfoFromJson(Map<String, dynamic> json) => CustomerInfo(
  id: (json['id'] as num).toInt(),
  name: json['name'] as String,
  company: json['company'] as String?,
  smsPhone: json['smsPhone'] as String?,
  email: json['email'] as String?,
  customerType: json['customerType'] as String,
);

Map<String, dynamic> _$CustomerInfoToJson(CustomerInfo instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'company': instance.company,
      'smsPhone': instance.smsPhone,
      'email': instance.email,
      'customerType': instance.customerType,
    };

TrailerAddon _$TrailerAddonFromJson(Map<String, dynamic> json) => TrailerAddon(
  id: (json['id'] as num).toInt(),
  trailerId: (json['trailerId'] as num?)?.toInt(),
  addonName: json['addonName'] as String,
  notes: json['notes'] as String?,
  addedAt: json['addedAt'] == null
      ? null
      : DateTime.parse(json['addedAt'] as String),
);

Map<String, dynamic> _$TrailerAddonToJson(TrailerAddon instance) =>
    <String, dynamic>{
      'id': instance.id,
      'trailerId': instance.trailerId,
      'addonName': instance.addonName,
      'notes': instance.notes,
      'addedAt': instance.addedAt?.toIso8601String(),
    };
