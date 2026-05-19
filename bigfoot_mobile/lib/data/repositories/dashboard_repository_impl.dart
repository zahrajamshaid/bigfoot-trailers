import '../../core/constants/api_endpoints.dart';
import '../../core/network/dio_client.dart';
import '../../domain/repositories/dashboard_repository.dart';

class DashboardRepositoryImpl implements DashboardRepository {
  final DioClient _api;

  DashboardRepositoryImpl({required DioClient api}) : _api = api;

  @override
  Future<DashboardStats> fetchManagerStats() async {
    final trailersResp = await _api.get<Map<String, dynamic>>(
      ApiEndpoints.trailers,
      queryParameters: {'limit': 100},
      fromJson: (d) => d as Map<String, dynamic>,
    );
    final trailers = (trailersResp.data?['trailers'] as List<dynamic>?) ?? [];

    int active = 0, ready = 0, hot = 0;
    for (final t in trailers) {
      if (t is Map<String, dynamic>) {
        final status = t['status'] as String?;
        if (status == 'in_production') active++;
        if (status == 'ready_for_delivery') ready++;
        if (t['isHot'] == true) hot++;
      }
    }

    return DashboardStats(
      activeTrailers: active,
      readyForDelivery: ready,
      hotTrailers: hot,
    );
  }

  @override
  Future<DashboardStats> fetchWorkerStats(int userId, int? departmentId) async {
    final summary = await _api.get<Map<String, dynamic>>(
      ApiEndpoints.payrollWorkerSummary(userId),
      fromJson: (d) => d as Map<String, dynamic>,
    );
    final pointsWeek =
        (summary.data?['totalPoints'] as num?)?.toDouble() ?? 0;

    int queueCount = 0;
    if (departmentId != null) {
      final queue = await _api.get<List<dynamic>>(
        ApiEndpoints.productionQueue(departmentId),
        fromJson: (d) => d as List<dynamic>,
      );
      queueCount = queue.data?.length ?? 0;
    }

    return DashboardStats(
      myQueueCount: queueCount,
      myPointsWeek: pointsWeek,
    );
  }

  @override
  Future<DashboardStats> fetchQcStats() async {
    final resp = await _api.get<Map<String, dynamic>>(
      ApiEndpoints.qcStats,
      fromJson: (d) => d as Map<String, dynamic>,
    );
    final data = resp.data ?? const <String, dynamic>{};
    return DashboardStats(
      // Fall back to the legacy `pendingInspections` key so the card still
      // populates against an API that hasn't been redeployed with the
      // renamed field yet.
      readyForInspection: (data['readyForInspection'] as num?)?.toInt() ??
          (data['pendingInspections'] as num?)?.toInt() ??
          0,
      inspectionsToday: (data['inspectionsToday'] as num?)?.toInt() ?? 0,
      failRateToday: (data['failRateToday'] as num?)?.toDouble() ?? 0,
      reworkQueue: (data['reworkQueue'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  Future<DashboardStats> fetchDriverStats() async {
    final resp = await _api.get<List<dynamic>>(
      ApiEndpoints.deliveries,
      fromJson: (d) => d as List<dynamic>,
    );
    final deliveries = resp.data ?? [];

    int active = 0, upcoming = 0, completed = 0;
    for (final d in deliveries) {
      if (d is Map<String, dynamic>) {
        final status = d['status'] as String?;
        if (status == 'in_transit') active++;
        if (status == 'scheduled') upcoming++;
        if (status == 'delivered') completed++;
      }
    }

    return DashboardStats(
      activeDeliveries: active,
      upcomingDeliveries: upcoming,
      completedThisWeek: completed,
    );
  }

  @override
  Future<DashboardStats> fetchTransportStats() async {
    final resp = await _api.get<List<dynamic>>(
      ApiEndpoints.deliveries,
      fromJson: (d) => d as List<dynamic>,
    );
    final deliveries = resp.data ?? [];

    int scheduled = 0, inTransit = 0;
    for (final d in deliveries) {
      if (d is Map<String, dynamic>) {
        final status = d['status'] as String?;
        if (status == 'scheduled') scheduled++;
        if (status == 'in_transit') inTransit++;
      }
    }

    final trailersResp = await _api.get<Map<String, dynamic>>(
      ApiEndpoints.trailers,
      queryParameters: {'status': 'ready_for_delivery', 'limit': 100},
      fromJson: (d) => d as Map<String, dynamic>,
    );
    final readyTrailers =
        (trailersResp.data?['trailers'] as List<dynamic>?) ?? [];

    return DashboardStats(
      scheduledDeliveries: scheduled,
      inTransitCount: inTransit,
      readyForPickup: readyTrailers.length,
    );
  }
}
