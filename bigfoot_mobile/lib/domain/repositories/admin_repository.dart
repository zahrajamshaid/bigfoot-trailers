import '../../data/models/department.dart';
import '../../data/models/role_option.dart';
import '../../data/models/trailer.dart';
import '../../data/models/user.dart';

class AdminDashboardStats {
  final int totalUsers;
  final int activeTrailers;
  final int weeklyProduction;
  final double qcFailRate;

  const AdminDashboardStats({
    this.totalUsers = 0,
    this.activeTrailers = 0,
    this.weeklyProduction = 0,
    this.qcFailRate = 0,
  });
}

class AdminWorkflowTemplate {
  final int id;
  final String series;
  final int departmentId;
  final String departmentCode;
  final String departmentName;
  final int stepOrder;
  final bool isQcStep;

  const AdminWorkflowTemplate({
    required this.id,
    required this.series,
    required this.departmentId,
    required this.departmentCode,
    required this.departmentName,
    required this.stepOrder,
    required this.isQcStep,
  });

  factory AdminWorkflowTemplate.fromJson(Map<String, dynamic> json) {
    return AdminWorkflowTemplate(
      id: (json['id'] as num).toInt(),
      series: json['series'] as String,
      departmentId: (json['department_id'] as num).toInt(),
      departmentCode: json['department_code'] as String,
      departmentName: json['department_name'] as String,
      stepOrder: (json['step_order'] as num).toInt(),
      isQcStep: json['is_qc_step'] as bool? ?? false,
    );
  }
}

class AdminAuditLogEntry {
  final int id;
  final int? userId;
  final String entityType;
  final int entityId;
  final String action;
  final Map<String, dynamic>? oldValues;
  final Map<String, dynamic>? newValues;
  final String? ipAddress;
  final DateTime? createdAt;
  final String? userName;

  const AdminAuditLogEntry({
    required this.id,
    this.userId,
    required this.entityType,
    required this.entityId,
    required this.action,
    this.oldValues,
    this.newValues,
    this.ipAddress,
    this.createdAt,
    this.userName,
  });

  factory AdminAuditLogEntry.fromJson(Map<String, dynamic> json) {
    final user = json['user'] as Map<String, dynamic>?;
    return AdminAuditLogEntry(
      id: (json['id'] as num).toInt(),
      userId: (json['userId'] as num?)?.toInt(),
      entityType: json['entityType'] as String,
      entityId: (json['entityId'] as num).toInt(),
      action: json['action'] as String,
      oldValues: json['oldValues'] as Map<String, dynamic>?,
      newValues: json['newValues'] as Map<String, dynamic>?,
      ipAddress: json['ipAddress'] as String?,
      createdAt: json['createdAt'] == null
          ? null
          : DateTime.tryParse(json['createdAt'] as String),
      userName: user?['fullName'] as String?,
    );
  }
}

class AdminWeeklyProductionReport {
  final String weekStart;
  final String weekEnd;
  final int totalStepsCompleted;
  final double totalPoints;
  final List<Map<String, dynamic>> steps;
  final List<Map<String, dynamic>> workerSummary;

  const AdminWeeklyProductionReport({
    required this.weekStart,
    required this.weekEnd,
    required this.totalStepsCompleted,
    required this.totalPoints,
    required this.steps,
    required this.workerSummary,
  });

  factory AdminWeeklyProductionReport.fromJson(Map<String, dynamic> json) {
    return AdminWeeklyProductionReport(
      weekStart: json['weekStart'] as String,
      weekEnd: json['weekEnd'] as String,
      totalStepsCompleted: (json['totalStepsCompleted'] as num?)?.toInt() ?? 0,
      totalPoints: (json['totalPoints'] as num?)?.toDouble() ?? 0,
      steps: ((json['steps'] as List<dynamic>?) ?? [])
          .whereType<Map<String, dynamic>>()
          .toList(),
      workerSummary: ((json['workerSummary'] as List<dynamic>?) ?? [])
          .whereType<Map<String, dynamic>>()
          .toList(),
    );
  }
}

class AdminUsersResult {
  final List<User> users;
  final int total;
  final int page;
  final int limit;

  const AdminUsersResult({
    required this.users,
    required this.total,
    required this.page,
    required this.limit,
  });
}

class AdminAuditResult {
  final List<AdminAuditLogEntry> items;
  final int total;
  final int page;
  final int limit;
  final int totalPages;

  const AdminAuditResult({
    required this.items,
    required this.total,
    required this.page,
    required this.limit,
    required this.totalPages,
  });
}

/// Abstract contract for admin operations.
abstract class AdminRepository {
  Future<AdminDashboardStats> getDashboardStats();

  Future<AdminUsersResult> getUsers({
    String? role,
    bool? isActive,
    int page,
    int limit,
  });

  Future<User> createUser({
    required String email,
    required String fullName,
    required String password,
    required String role,
    int? primaryDepartmentId,
    int? primaryLocationId,
    String? phone,
  });

  Future<User> updateUser({
    required int id,
    String? fullName,
    String? email,
    String? password,
    String? role,
    int? primaryDepartmentId,
    int? primaryLocationId,
    String? phone,
  });

  Future<void> deactivateUser(int id);

  /// Undo a soft-delete — flips isActive back to true.
  Future<User> reactivateUser(int id);

  /// Hard-delete an already-deactivated user. Backend rejects 400 if the
  /// user has any historical activity (completed steps, inspections, etc.).
  Future<void> hardDeleteUser(int id);

  Future<List<Department>> getDepartments();

  /// All user roles + display labels for admin pickers. Source of truth
  /// lives in the backend's UserRole enum so additions surface here without
  /// a mobile rebuild.
  Future<List<RoleOption>> getRoles();

  Future<Department> updateDepartmentThreshold({
    required int id,
    required int stallThresholdHours,
  });

  Future<List<AdminWorkflowTemplate>> getWorkflowTemplates();

  /// All trailer models — used to build the point-value matrix.
  Future<List<TrailerModelInfo>> getTrailerModels();

  Future<AdminAuditResult> getAuditLogs({
    String? entityType,
    int? userId,
    String? from,
    String? to,
    int page,
    int limit,
  });

  Future<List<AdminAuditLogEntry>> getAuditEntityHistory(String entityType, int id);

  Future<AdminWeeklyProductionReport> getWeeklyProductionReport(String weekStartIso);
}
