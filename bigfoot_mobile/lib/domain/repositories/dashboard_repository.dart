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
  final int reworkQueue;

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
    this.myQueueCount = 0,
    this.myPointsToday = 0,
    this.myPointsWeek = 0,
    this.nextTrailerSo,
    this.nextTrailerColor,
    this.readyForInspection = 0,
    this.inspectionsToday = 0,
    this.failRateToday = 0,
    this.reworkQueue = 0,
    this.activeDeliveries = 0,
    this.upcomingDeliveries = 0,
    this.completedThisWeek = 0,
    this.scheduledDeliveries = 0,
    this.inTransitCount = 0,
    this.readyForPickup = 0,
  });
}
