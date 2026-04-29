import 'package:json_annotation/json_annotation.dart';

part 'audit_log.g.dart';

@JsonSerializable()
class AuditLogEntry {
  final int id;
  final String entityType;
  final int entityId;
  final int? userId;
  final String action;
  final Map<String, dynamic>? oldValues;
  final Map<String, dynamic>? newValues;
  final DateTime? createdAt;
  final String? userName;

  const AuditLogEntry({
    required this.id,
    required this.entityType,
    required this.entityId,
    this.userId,
    required this.action,
    this.oldValues,
    this.newValues,
    this.createdAt,
    this.userName,
  });

  factory AuditLogEntry.fromJson(Map<String, dynamic> json) =>
      _$AuditLogEntryFromJson(json);
  Map<String, dynamic> toJson() => _$AuditLogEntryToJson(this);
}
