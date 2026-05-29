// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'user.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

User _$UserFromJson(Map<String, dynamic> json) => User(
  id: (json['id'] as num).toInt(),
  email: json['email'] as String,
  name: json['name'] as String,
  role: json['role'] as String,
  departmentId: (json['primaryDepartmentId'] as num?)?.toInt(),
  extraDepartmentIds:
      (json['extraDepartmentIds'] as List<dynamic>?)
          ?.map((e) => (e as num).toInt())
          .toList() ??
      [],
  locationId: (json['primaryLocationId'] as num?)?.toInt(),
  isActive: json['isActive'] as bool?,
  createdAt: json['createdAt'] == null
      ? null
      : DateTime.parse(json['createdAt'] as String),
);

Map<String, dynamic> _$UserToJson(User instance) => <String, dynamic>{
  'id': instance.id,
  'email': instance.email,
  'name': instance.name,
  'role': instance.role,
  'primaryDepartmentId': instance.departmentId,
  'extraDepartmentIds': instance.extraDepartmentIds,
  'primaryLocationId': instance.locationId,
  'isActive': instance.isActive,
  'createdAt': instance.createdAt?.toIso8601String(),
};
