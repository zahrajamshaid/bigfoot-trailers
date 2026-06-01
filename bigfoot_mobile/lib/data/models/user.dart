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
  static const String parts = 'parts';
}

@JsonSerializable()
class User extends Equatable {
  final int id;
  final String email;
  final String name;
  final String role;
  @JsonKey(name: 'primaryDepartmentId')
  final int? departmentId;
  /// Additional department IDs this user can view queues for, beyond their
  /// primary [departmentId]. Empty for normal accounts; populated for
  /// "master" accounts (e.g. paint-master covers PAINT_A + PAINT_B).
  @JsonKey(defaultValue: <int>[])
  final List<int> extraDepartmentIds;
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
    this.extraDepartmentIds = const <int>[],
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

  /// True for accounts that span multiple departments — i.e. master accounts
  /// like paint-master or wire-hyd-master. Triggers the queue dept selector
  /// even for non-managers so the user can switch between their assigned
  /// departments.
  bool get isMultiDept => extraDepartmentIds.isNotEmpty;

  /// All department IDs this user is allowed to view queues for, in order
  /// (primary first, then extras). Used by the queue screen to scope the
  /// dept selector for non-manager multi-dept accounts.
  List<int> get allDepartmentIds => [
        if (departmentId != null) departmentId!,
        ...extraDepartmentIds,
      ];

  @override
  List<Object?> get props => [id, email, name, role, departmentId, extraDepartmentIds];
}
