import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'user.g.dart';

/// User roles matching the backend enum.
abstract final class UserRole {
  static const String owner = 'owner';
  static const String productionManager = 'production_manager';
  static const String transportManager = 'transport_manager';
  static const String qcInspector = 'qc_inspector';
  static const String worker = 'worker';
  static const String driver = 'driver';
  static const String office = 'office';
  static const String sales = 'sales';
  static const String purchasing = 'purchasing';
}

@JsonSerializable()
class User extends Equatable {
  final int id;
  final String email;
  final String name;
  final String role;
  @JsonKey(name: 'primaryDepartmentId')
  final int? departmentId;
  @JsonKey(name: 'primaryLocationId')
  final int? locationId;
  final bool? isActive;
  final DateTime? createdAt;

  const User({
    required this.id,
    required this.email,
    required this.name,
    required this.role,
    this.departmentId,
    this.locationId,
    this.isActive,
    this.createdAt,
  });

  factory User.fromJson(Map<String, dynamic> json) => _$UserFromJson(json);
  Map<String, dynamic> toJson() => _$UserToJson(this);

  /// Whether this user can access admin features.
  bool get isAdmin => role == UserRole.owner;

  /// Whether this user can manage production.
  bool get isManager =>
      role == UserRole.owner || role == UserRole.productionManager;

  /// Whether this user can manage deliveries.
  bool get isTransportManager =>
      role == UserRole.owner || role == UserRole.transportManager;

  /// Whether this user is a QC inspector.
  bool get isQcInspector =>
      role == UserRole.qcInspector || isManager;

  @override
  List<Object?> get props => [id, email, name, role];
}
