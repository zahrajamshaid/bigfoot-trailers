/// Abstract contract for dashboard data operations.
abstract class DashboardRepository {
  Future<DashboardStats> fetchManagerStats();
  Future<DashboardStats> fetchWorkerStats(int userId, int? departmentId);
  Future<DashboardStats> fetchQcStats();
  Future<DashboardStats> fetchDriverStats();
  Future<DashboardStats> fetchTransportStats();
}

class DashboardStats {
  // Owner / Production Manager
  final int activeTrailers;
  final int readyForDelivery;
  final int hotTrailers;
  final int stalledSteps;
  final int weeklyCompleted;
  final double qcFailRate;
  /// Total trailers in the system across every status — surfaced on the
  /// Owner / PM / sales dashboards for the at-a-glance "how big is the
  /// herd right now" tile.
  final int totalTrailers;
  /// Trailers in `pending_production` — the pre-build queue. The 8th card
  /// in the manager grid; pairs naturally with active / ready / delivered.
  final int pendingProduction;
  /// All-time total of `delivered` trailers — the "Archived" tile on the
  /// manager dashboard. Deep-links to the trailers list with the Delivered
  /// chip on.
  final int archivedTotal;
  /// Stock builds physically at Mulberry that are `ready_for_delivery` and
  /// waiting on a stack-to-yard run, grouped by destination yard code
  /// (JACKSONVILLE / TAPPAHANNOCK / TALLAHASSEE / ATLANTA). Backs the new
  /// "Mulberry → Yards" dashboard tile + its drill-down.
  final Map<String, int> mulberryStockByYard;
  /// Sum of [mulberryStockByYard] — convenience for the tile's headline
  /// number. Defaults to 0 when the new endpoint is unreachable.
  final int mulberryStockTotal;
  /// Customer-order trailers (no intendedStockLocation) parked at Mulberry
  /// waiting on a factory pickup. Backs the second new tile.
  final int mulberryCustomerPickups;

  /// Options added AFTER a build started, awaiting production-manager review.
  final int optionsPendingReview;

  // Worker
  final int myQueueCount;
  final double myPointsToday;
  final double myPointsWeek;
  final String? nextTrailerSo;
  final String? nextTrailerColor;

  // QC Inspector
  final int readyForInspection;
  final int inspectionsToday;
  final double failRateToday;
  /// Today's raw fail count — paired with [inspectionsToday] for the
  /// "QC fail today" tile so it can show "0.0% · 0/0" honestly on a
  /// quiet morning instead of an empty percent.
  final int failsToday;
  final int reworkQueue;
  /// Raw 30-day inspection volume behind [qcFailRate] — surfaced so the
  /// manager-dashboard tile can render "X.X% · F of N (30d)" instead of
  /// the bare percent. A 100% rate off 1 inspection is wildly different
  /// from 100% off 200, and operators want both numbers visible.
  final int qcFailRateInspections;
  final int qcFailRateFails;

  // Driver
  final int activeDeliveries;
  final int upcomingDeliveries;
  final int completedThisWeek;

  // Transport Manager
  final int scheduledDeliveries;
  final int inTransitCount;
  final int readyForPickup;

  const DashboardStats({
    this.activeTrailers = 0,
    this.readyForDelivery = 0,
    this.hotTrailers = 0,
    this.stalledSteps = 0,
    this.weeklyCompleted = 0,
    this.qcFailRate = 0,
    this.totalTrailers = 0,
    this.pendingProduction = 0,
    this.archivedTotal = 0,
    this.mulberryStockByYard = const <String, int>{},
    this.mulberryStockTotal = 0,
    this.mulberryCustomerPickups = 0,
    this.optionsPendingReview = 0,
    this.myQueueCount = 0,
    this.myPointsToday = 0,
    this.myPointsWeek = 0,
    this.nextTrailerSo,
    this.nextTrailerColor,
    this.readyForInspection = 0,
    this.inspectionsToday = 0,
    this.failRateToday = 0,
    this.failsToday = 0,
    this.reworkQueue = 0,
    this.qcFailRateInspections = 0,
    this.qcFailRateFails = 0,
    this.activeDeliveries = 0,
    this.upcomingDeliveries = 0,
    this.completedThisWeek = 0,
    this.scheduledDeliveries = 0,
    this.inTransitCount = 0,
    this.readyForPickup = 0,
  });
}
