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
    // /trailers also returns the true total count (independent of the page
    // limit), so we surface it on the Owner / PM / Sales dashboards
    // instead of relying on the page we just fetched.
    final totalTrailers = (trailersResp.data?['total'] as num?)?.toInt() ??
        trailers.length;

    int active = 0, ready = 0, hot = 0;
    for (final t in trailers) {
      if (t is Map<String, dynamic>) {
        final status = t['status'] as String?;
        if (status == 'in_production') active++;
        if (status == 'ready_for_delivery') ready++;
        if (t['isHot'] == true) hot++;
      }
    }

    // Manager dashboard shows the "QC fail rate" tile, so pull the same
    // 30-day rate the QC dashboard uses. Don't fail the whole manager card
    // load if /qc/stats hiccups — fall back to 0 quietly.
    double qcFailRate = 0;
    try {
      final qc = await _api.get<Map<String, dynamic>>(
        ApiEndpoints.qcStats,
        fromJson: (d) => d as Map<String, dynamic>,
      );
      qcFailRate = (qc.data?['qcFailRate'] as num?)?.toDouble() ?? 0;
    } catch (_) {
      qcFailRate = 0;
    }

    return DashboardStats(
      activeTrailers: active,
      readyForDelivery: ready,
      hotTrailers: hot,
      qcFailRate: qcFailRate,
      totalTrailers: totalTrailers,
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
      // Rates come back as 0–100 percentages from the new backend; older
      // versions sent 0–1 fractions, so multiply when the value is < 1.0.
      // (A real 100% rate against the new API still reads as 100 here.)
      failRateToday: _asPercent(data['failRateToday']),
      qcFailRate: _asPercent(data['qcFailRate']),
      reworkQueue: (data['reworkQueue'] as num?)?.toInt() ?? 0,
    );
  }

  /// Coerce a 0-1 fraction or a 0-100 percentage into a 0-100 percentage.
  /// Any value at or above 1.0 is assumed to already be a percentage (so a
  /// real 100% from the new API still reads as 100); anything strictly
  /// below 1 — including the historical 0.25 = 25% shape — is multiplied.
  double _asPercent(dynamic value) {
    final n = (value as num?)?.toDouble();
    if (n == null) return 0;
    if (n <= 0) return 0;
    if (n < 1.0) return n * 100;
    return n;
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
