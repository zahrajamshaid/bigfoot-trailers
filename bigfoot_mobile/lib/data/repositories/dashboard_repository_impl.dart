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
      queryParameters: {'limit': 1},
      fromJson: (d) => d as Map<String, dynamic>,
    );
    // We used to page in 100 trailers and tally status / isHot in memory,
    // which undercounted active / ready / hot whenever the shop had more
    // than 100 trailers in the active set. The API exposes a `total`
    // count per filter — much cheaper and always accurate — so each tile
    // now gets its own filtered limit=1 round-trip. The first call above
    // is only used for totalTrailers + a quick reachability check.
    final totalTrailers = (trailersResp.data?['total'] as num?)?.toInt() ?? 0;

    Future<int> filteredTotal(Map<String, dynamic> q) async {
      try {
        final r = await _api.get<Map<String, dynamic>>(
          ApiEndpoints.trailers,
          queryParameters: {...q, 'limit': 1},
          fromJson: (d) => d as Map<String, dynamic>,
        );
        return (r.data?['total'] as num?)?.toInt() ?? 0;
      } catch (_) {
        return 0;
      }
    }

    final perStatus = await Future.wait([
      filteredTotal({'status': 'in_production'}),
      filteredTotal({'status': 'ready_for_delivery'}),
      // Backend filter is `isHot`, not `hot` — sending the wrong key
      // landed back as "no filter applied" and the count came back equal
      // to the full trailer total instead of the hot subset.
      filteredTotal({'isHot': 'true'}),
    ]);
    final active = perStatus[0];
    final ready = perStatus[1];
    final hot = perStatus[2];

    // Manager dashboard shows two QC fail-rate tiles (Today + 30d), and
    // both want the raw fraction next to the percent. Pull all six fields
    // off /qc/stats in one round-trip; fail soft if /qc/stats hiccups so
    // the rest of the manager card still renders.
    double qcFailRate = 0;
    int qcFailRateInspections = 0;
    int qcFailRateFails = 0;
    double failRateToday = 0;
    int inspectionsToday = 0;
    int failsToday = 0;
    int reworkQueue = 0;
    try {
      final qc = await _api.get<Map<String, dynamic>>(
        ApiEndpoints.qcStats,
        fromJson: (d) => d as Map<String, dynamic>,
      );
      final d = qc.data ?? const <String, dynamic>{};
      qcFailRate = _asPercent(d['qcFailRate']);
      qcFailRateInspections =
          (d['qcFailRateInspections'] as num?)?.toInt() ?? 0;
      qcFailRateFails = (d['qcFailRateFails'] as num?)?.toInt() ?? 0;
      failRateToday = _asPercent(d['failRateToday']);
      inspectionsToday = (d['inspectionsToday'] as num?)?.toInt() ?? 0;
      failsToday = (d['failsToday'] as num?)?.toInt() ?? 0;
      reworkQueue = (d['reworkQueue'] as num?)?.toInt() ?? 0;
    } catch (_) {
      // leave defaults at 0
    }

    // Pending production tile uses the API's `total` for accuracy — the
    // first-page iteration above only sees the first 100 trailers, which
    // would undercount the pre-build queue on a busy week. limit=1 keeps
    // the round-trip cheap. Fail soft so a hiccup doesn't break the card.
    int pendingProduction = 0;
    try {
      final pending = await _api.get<Map<String, dynamic>>(
        ApiEndpoints.trailers,
        queryParameters: {'status': 'pending_production', 'limit': 1},
        fromJson: (d) => d as Map<String, dynamic>,
      );
      pendingProduction = (pending.data?['total'] as num?)?.toInt() ?? 0;
    } catch (_) {
      pendingProduction = 0;
    }

    // Completed this week — same pattern. Filters delivered trailers by
    // the `completedSince` query (Delivery.deliveredAt >= Sunday 00:00
    // UTC) so the count is computed on the backend instead of relying on
    // the first-page iteration above.
    int weeklyCompleted = 0;
    try {
      final now = DateTime.now().toUtc();
      final daysBack = now.weekday % 7; // Sun=0 days back
      final sunday = DateTime.utc(now.year, now.month, now.day - daysBack);
      final completed = await _api.get<Map<String, dynamic>>(
        ApiEndpoints.trailers,
        queryParameters: {
          'status': 'delivered',
          'completedSince': sunday.toIso8601String(),
          'limit': 1,
        },
        fromJson: (d) => d as Map<String, dynamic>,
      );
      weeklyCompleted = (completed.data?['total'] as num?)?.toInt() ?? 0;
    } catch (_) {
      weeklyCompleted = 0;
    }

    // Stalled steps — was previously hard-zero on the dashboard because
    // we never asked the backend. /production/stalled-count returns the
    // count of unresolved StallAlert rows (one indexed COUNT, cheap).
    int stalledSteps = 0;
    try {
      final stall = await _api.get<Map<String, dynamic>>(
        ApiEndpoints.productionStalledCount,
        fromJson: (d) => d as Map<String, dynamic>,
      );
      stalledSteps = (stall.data?['count'] as num?)?.toInt() ?? 0;
    } catch (_) {
      stalledSteps = 0;
    }

    // Archived (all-time delivered) — total of trailers whose status is
    // `delivered`. Powers the new Archived tile + acts as the "how many
    // builds have we ever shipped" denominator.
    int archivedTotal = 0;
    try {
      final archived = await _api.get<Map<String, dynamic>>(
        ApiEndpoints.trailers,
        queryParameters: {'status': 'delivered', 'limit': 1},
        fromJson: (d) => d as Map<String, dynamic>,
      );
      archivedTotal = (archived.data?['total'] as num?)?.toInt() ?? 0;
    } catch (_) {
      archivedTotal = 0;
    }

    // Mulberry-ready breakdown — stock builds at Mulberry split by
    // destination yard, plus the count of customer-pickup trailers also
    // parked at Mulberry. Fail-soft: an older API that doesn't expose the
    // endpoint just renders the tiles with zero counts.
    Map<String, int> mulberryStockByYard = const <String, int>{};
    int mulberryStockTotal = 0;
    int mulberryCustomerPickups = 0;
    try {
      final m = await _api.get<Map<String, dynamic>>(
        ApiEndpoints.trailersMulberryReady,
        fromJson: (d) => d as Map<String, dynamic>,
      );
      final by = m.data?['stockByYard'] as Map<String, dynamic>? ?? const {};
      mulberryStockByYard = by.map(
        (k, v) => MapEntry(k, (v as num?)?.toInt() ?? 0),
      );
      mulberryStockTotal = (m.data?['totalStock'] as num?)?.toInt() ?? 0;
      mulberryCustomerPickups =
          (m.data?['customerPickupsAtMulberry'] as num?)?.toInt() ?? 0;
    } catch (_) {
      mulberryStockByYard = const <String, int>{};
      mulberryStockTotal = 0;
      mulberryCustomerPickups = 0;
    }

    // Options added mid-build, still unreviewed by the production manager.
    // Fail-soft: role-gated to owner/PM, so anyone else just sees zero.
    int optionsPendingReview = 0;
    try {
      final o = await _api.get<List<dynamic>>(
        ApiEndpoints.optionsPendingReview,
        fromJson: (d) => d as List<dynamic>,
      );
      optionsPendingReview = (o.data ?? const []).length;
    } catch (_) {
      optionsPendingReview = 0;
    }

    return DashboardStats(
      optionsPendingReview: optionsPendingReview,
      activeTrailers: active,
      readyForDelivery: ready,
      hotTrailers: hot,
      qcFailRate: qcFailRate,
      qcFailRateInspections: qcFailRateInspections,
      qcFailRateFails: qcFailRateFails,
      failRateToday: failRateToday,
      inspectionsToday: inspectionsToday,
      failsToday: failsToday,
      reworkQueue: reworkQueue,
      totalTrailers: totalTrailers,
      pendingProduction: pendingProduction,
      weeklyCompleted: weeklyCompleted,
      stalledSteps: stalledSteps,
      archivedTotal: archivedTotal,
      mulberryStockByYard: mulberryStockByYard,
      mulberryStockTotal: mulberryStockTotal,
      mulberryCustomerPickups: mulberryCustomerPickups,
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
      failsToday: (data['failsToday'] as num?)?.toInt() ?? 0,
      qcFailRate: _asPercent(data['qcFailRate']),
      // Raw 30-day counts behind the rolling fail-rate tile so the UI
      // can render "X.X% · F of N (30d)". Older API responses omit
      // these — default to 0 so the tile still works.
      qcFailRateInspections:
          (data['qcFailRateInspections'] as num?)?.toInt() ?? 0,
      qcFailRateFails: (data['qcFailRateFails'] as num?)?.toInt() ?? 0,
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
