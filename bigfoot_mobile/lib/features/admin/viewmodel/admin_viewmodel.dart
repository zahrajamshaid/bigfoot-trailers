import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/models/role_option.dart';
import '../../../data/models/trailer.dart';
import '../../../domain/repositories/admin_repository.dart';

// Re-export domain types for screens
export '../../../domain/repositories/admin_repository.dart'
    show AdminDashboardStats, AdminWorkflowTemplate, AdminAuditLogEntry,
         AdminWeeklyProductionReport, AdminUsersResult, AdminAuditResult;

class AdminViewModel extends Cubit<int> {
  final AdminRepository _repository;

  AdminViewModel({required AdminRepository repository})
      : _repository = repository,
        super(0);

  Future<AdminDashboardStats> getDashboardStats() => _repository.getDashboardStats();

  Future<AdminUsersResult> getUsers({
    String? role,
    bool? isActive,
    int page = 1,
    int limit = 25,
  }) => _repository.getUsers(role: role, isActive: isActive, page: page, limit: limit);

  Future<dynamic> createUser({
    required String email,
    required String fullName,
    required String password,
    required String role,
    int? primaryDepartmentId,
    int? primaryLocationId,
    String? phone,
  }) => _repository.createUser(
    email: email,
    fullName: fullName,
    password: password,
    role: role,
    primaryDepartmentId: primaryDepartmentId,
    primaryLocationId: primaryLocationId,
    phone: phone,
  );

  Future<dynamic> updateUser({
    required int id,
    String? fullName,
    String? email,
    String? password,
    String? role,
    int? primaryDepartmentId,
    int? primaryLocationId,
    String? phone,
  }) => _repository.updateUser(
    id: id,
    fullName: fullName,
    email: email,
    password: password,
    role: role,
    primaryDepartmentId: primaryDepartmentId,
    primaryLocationId: primaryLocationId,
    phone: phone,
  );

  Future<void> deactivateUser(int id) => _repository.deactivateUser(id);

  Future<dynamic> reactivateUser(int id) => _repository.reactivateUser(id);

  Future<void> hardDeleteUser(int id) => _repository.hardDeleteUser(id);

  Future<dynamic> getDepartments() => _repository.getDepartments();

  Future<List<RoleOption>> getRoles() => _repository.getRoles();

  Future<dynamic> updateDepartmentThreshold({
    required int id,
    required int stallThresholdHours,
  }) => _repository.updateDepartmentThreshold(id: id, stallThresholdHours: stallThresholdHours);

  Future<List<AdminWorkflowTemplate>> getWorkflowTemplates() =>
      _repository.getWorkflowTemplates();

  Future<List<TrailerModelInfo>> getTrailerModels() =>
      _repository.getTrailerModels();

  Future<AdminAuditResult> getAuditLogs({
    String? entityType,
    int? userId,
    String? from,
    String? to,
    int page = 1,
    int limit = 25,
  }) => _repository.getAuditLogs(
    entityType: entityType, userId: userId, from: from, to: to, page: page, limit: limit,
  );

  Future<List<AdminAuditLogEntry>> getAuditEntityHistory(String entityType, int id) =>
      _repository.getAuditEntityHistory(entityType, id);

  Future<AdminWeeklyProductionReport> getWeeklyProductionReport(String weekStartIso) =>
      _repository.getWeeklyProductionReport(weekStartIso);
}
