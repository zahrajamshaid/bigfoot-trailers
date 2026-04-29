// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'audit_log.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

AuditLogEntry _$AuditLogEntryFromJson(Map<String, dynamic> json) =>
    AuditLogEntry(
      id: (json['id'] as num).toInt(),
      entityType: json['entityType'] as String,
      entityId: (json['entityId'] as num).toInt(),
      userId: (json['userId'] as num?)?.toInt(),
      action: json['action'] as String,
      oldValues: json['oldValues'] as Map<String, dynamic>?,
      newValues: json['newValues'] as Map<String, dynamic>?,
      createdAt: json['createdAt'] == null
          ? null
          : DateTime.parse(json['createdAt'] as String),
      userName: json['userName'] as String?,
    );

Map<String, dynamic> _$AuditLogEntryToJson(AuditLogEntry instance) =>
    <String, dynamic>{
      'id': instance.id,
      'entityType': instance.entityType,
      'entityId': instance.entityId,
      'userId': instance.userId,
      'action': instance.action,
      'oldValues': instance.oldValues,
      'newValues': instance.newValues,
      'createdAt': instance.createdAt?.toIso8601String(),
      'userName': instance.userName,
    };
