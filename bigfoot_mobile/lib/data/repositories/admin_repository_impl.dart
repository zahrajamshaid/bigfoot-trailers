import '../../core/constants/api_endpoints.dart';
import '../../core/network/dio_client.dart';
import '../../domain/repositories/admin_repository.dart';
import '../models/department.dart';
import '../models/trailer.dart';
import '../models/user.dart';

class AdminRepositoryImpl implements AdminRepository {
  final DioClient _api;

  AdminRepositoryImpl({required DioClient api}) : _api = api;

  @override
  Future<AdminDashboardStats> getDashboardStats() async {
    final usersFuture = _api.get<Map<String, dynamic>>(
      ApiEndpoints.users,
      queryParameters: {'page': 1, 'limit': 1},
      fromJson: (d) => d as Map<String, dynamic>,
    );
    final activeTrailersFuture = _api.get<Map<String, dynamic>>(
      ApiEndpoints.trailers,
      queryParameters: {'status': 'in_production', 'page': 1, 'limit': 1},
      fromJson: (d) => d as Map<String, dynamic>,
    );
    final weeklyFuture = _api.get<Map<String, dynamic>>(
      ApiEndpoints.adminWeeklyProduction,
      queryParameters: {'weekStart': _weekStartSundayIso()},
      fromJson: (d) => d as Map<String, dynamic>,
    );

    final usersResp = await usersFuture;
    final trailersResp = await activeTrailersFuture;
    final weeklyResp = await weeklyFuture;

    return AdminDashboardStats(
      totalUsers: (usersResp.data?['total'] as num?)?.toInt() ?? 0,
      activeTrailers: (trailersResp.data?['total'] as num?)?.toInt() ?? 0,
      weeklyProduction: (weeklyResp.data?['totalStepsCompleted'] as num?)?.toInt() ?? 0,
      qcFailRate: 0,
    );
  }

  @override
  Future<AdminUsersResult> getUsers({
    String? role,
    bool? isActive,
    int page = 1,
    int limit = 25,
  }) async {
    final safePage = page < 1 ? 1 : page;
    final safeLimit = limit < 1 ? 1 : (limit > 100 ? 100 : limit);

    final response = await _api.get<Map<String, dynamic>>(
      ApiEndpoints.users,
      queryParameters: {
        'page': safePage,
        'limit': safeLimit,
        if (role != null && role.isNotEmpty) 'role': role,
        if (isActive != null) 'isActive': isActive,
      },
      fromJson: (d) => d as Map<String, dynamic>,
    );

  final data = response.data ?? {};

  // Backend list endpoints may use different keys depending on controller
  // or paginator middleware. Accept common variants so admin user list
  // still renders even if shape changes between environments.
  final rawUsers = (data['users'] as List<dynamic>?) ??
    (data['items'] as List<dynamic>?) ??
    (data['results'] as List<dynamic>?) ??
    (data['rows'] as List<dynamic>?) ??
    const <dynamic>[];

  final users = rawUsers
        .whereType<Map<String, dynamic>>()
        .map(_userFromApi)
        .toList();

    return AdminUsersResult(
      users: users,
    total: (data['total'] as num?)?.toInt() ??
      (data['count'] as num?)?.toInt() ??
      users.length,
    page: (data['page'] as num?)?.toInt() ??
      ((data['meta'] as Map<String, dynamic>?)?['page'] as num?)
        ?.toInt() ??
      safePage,
    limit: (data['limit'] as num?)?.toInt() ??
      ((data['meta'] as Map<String, dynamic>?)?['limit'] as num?)
        ?.toInt() ??
      safeLimit,
    );
  }

  @override
  Future<User> createUser({
    required String email,
    required String fullName,
    required String password,
    required String role,
    int? primaryDepartmentId,
    int? primaryLocationId,
    String? phone,
  }) async {
    final response = await _api.post<Map<String, dynamic>>(
      ApiEndpoints.users,
      data: {
        'email': email,
        'fullName': fullName,
        'password': password,
        'role': role,
        if (primaryDepartmentId != null) 'primaryDepartmentId': primaryDepartmentId,
        if (primaryLocationId != null) 'primaryLocationId': primaryLocationId,
        if (phone != null && phone.isNotEmpty) 'phone': phone,
      },
      fromJson: (d) => d as Map<String, dynamic>,
    );
    return _userFromApi(response.data!);
  }

  @override
  Future<User> updateUser({
    required int id,
    String? fullName,
    String? email,
    String? password,
    String? role,
    int? primaryDepartmentId,
    int? primaryLocationId,
    String? phone,
  }) async {
    final response = await _api.patch<Map<String, dynamic>>(
      ApiEndpoints.user(id),
      data: {
        if (fullName != null) 'fullName': fullName,
        if (email != null) 'email': email,
        if (password != null && password.isNotEmpty) 'password': password,
        if (role != null) 'role': role,
        if (phone != null) 'phone': phone,
        if (primaryDepartmentId != null) 'primaryDepartmentId': primaryDepartmentId,
        if (primaryLocationId != null) 'primaryLocationId': primaryLocationId,
      },
      fromJson: (d) => d as Map<String, dynamic>,
    );
    return _userFromApi(response.data!);
  }

  @override
  Future<void> deactivateUser(int id) async {
    await _api.delete(ApiEndpoints.user(id));
  }

  @override
  Future<User> reactivateUser(int id) async {
    final response = await _api.post<Map<String, dynamic>>(
      ApiEndpoints.userReactivate(id),
      fromJson: (d) => d as Map<String, dynamic>,
    );
    return _userFromApi(response.data!);
  }

  @override
  Future<void> hardDeleteUser(int id) async {
    await _api.delete(ApiEndpoints.userPermanent(id));
  }

  @override
  Future<List<Department>> getDepartments() async {
    final response = await _api.get<List<dynamic>>(
      ApiEndpoints.adminDepartments,
      fromJson: (d) => d as List<dynamic>,
    );
    return (response.data ?? [])
        .whereType<Map<String, dynamic>>()
        .map(Department.fromJson)
        .toList();
  }

  @override
  Future<Department> updateDepartmentThreshold({
    required int id,
    required int stallThresholdHours,
  }) async {
    final response = await _api.patch<Map<String, dynamic>>(
      ApiEndpoints.adminDepartment(id),
      data: {'stallThresholdHours': stallThresholdHours},
      fromJson: (d) => d as Map<String, dynamic>,
    );
    return Department.fromJson(response.data!);
  }

  @override
  Future<List<AdminWorkflowTemplate>> getWorkflowTemplates() async {
    final response = await _api.get<List<dynamic>>(
      ApiEndpoints.adminWorkflowTemplates,
      fromJson: (d) => d as List<dynamic>,
    );
    return (response.data ?? [])
        .whereType<Map<String, dynamic>>()
        .map(AdminWorkflowTemplate.fromJson)
        .toList();
  }

  @override
  Future<List<TrailerModelInfo>> getTrailerModels() async {
    final response = await _api.get<List<dynamic>>(
      ApiEndpoints.adminTrailerModels,
      fromJson: (d) => d as List<dynamic>,
    );
    return (response.data ?? [])
        .whereType<Map<String, dynamic>>()
        .map(TrailerModelInfo.fromJson)
        .toList();
  }

  @override
  Future<AdminAuditResult> getAuditLogs({
    String? entityType,
    int? userId,
    String? from,
    String? to,
    int page = 1,
    int limit = 25,
  }) async {
    final response = await _api.get<Map<String, dynamic>>(
      ApiEndpoints.adminAuditLog,
      queryParameters: {
        if (entityType != null && entityType.isNotEmpty) 'entityType': entityType,
        if (userId != null) 'userId': userId,
        if (from != null) 'from': from,
        if (to != null) 'to': to,
        'page': page,
        'limit': limit,
      },
      fromJson: (d) => d as Map<String, dynamic>,
    );

    final data = response.data ?? {};
    final items = ((data['items'] as List<dynamic>?) ?? [])
        .whereType<Map<String, dynamic>>()
        .map(AdminAuditLogEntry.fromJson)
        .toList();

    return AdminAuditResult(
      items: items,
      total: (data['total'] as num?)?.toInt() ?? items.length,
      page: (data['page'] as num?)?.toInt() ?? page,
      limit: (data['limit'] as num?)?.toInt() ?? limit,
      totalPages: (data['totalPages'] as num?)?.toInt() ?? 1,
    );
  }

  @override
  Future<List<AdminAuditLogEntry>> getAuditEntityHistory(String entityType, int id) async {
    final response = await _api.get<List<dynamic>>(
      ApiEndpoints.adminAuditEntity(entityType, id),
      fromJson: (d) => d as List<dynamic>,
    );
    return (response.data ?? [])
        .whereType<Map<String, dynamic>>()
        .map(AdminAuditLogEntry.fromJson)
        .toList();
  }

  @override
  Future<AdminWeeklyProductionReport> getWeeklyProductionReport(String weekStartIso) async {
    final response = await _api.get<Map<String, dynamic>>(
      ApiEndpoints.adminWeeklyProduction,
      queryParameters: {'weekStart': weekStartIso},
      fromJson: (d) => d as Map<String, dynamic>,
    );
    return AdminWeeklyProductionReport.fromJson(response.data!);
  }

  User _userFromApi(Map<String, dynamic> json) {
    return User(
      id: (json['id'] as num).toInt(),
      email: json['email'] as String? ?? '',
      name: json['fullName'] as String? ?? json['name'] as String? ?? '',
      role: json['role'] as String? ?? UserRole.worker,
      departmentId: (json['primaryDepartmentId'] as num?)?.toInt(),
      locationId: (json['primaryLocationId'] as num?)?.toInt(),
      isActive: json['isActive'] as bool?,
      createdAt: json['createdAt'] == null
          ? null
          : DateTime.tryParse(json['createdAt'] as String),
    );
  }

  String _weekStartSundayIso() {
    final now = DateTime.now().toUtc();
    final day = now.weekday % 7;
    final sunday = DateTime.utc(now.year, now.month, now.day)
        .subtract(Duration(days: day));
    return sunday.toIso8601String().split('T').first;
  }
}
