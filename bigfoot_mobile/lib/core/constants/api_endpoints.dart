/// All API endpoint paths as typed constants.
/// Base URL is injected via DioClient configuration.
abstract final class ApiEndpoints {
  // ── Auth ─────────────────────────────────────────────────────────────────
  static const String login = '/auth/login';
  static const String refresh = '/auth/refresh';
  static const String logout = '/auth/logout';
    static const String authPushToken = '/auth/push-token';

  // ── Users ────────────────────────────────────────────────────────────────
  static const String users = '/users';
  static const String usersDrivers = '/users/drivers';
  static const String usersRoles = '/users/roles';
  static String user(int id) => '/users/$id';
  static String userRole(int id) => '/users/$id/role';
  static String userReactivate(int id) => '/users/$id/reactivate';
  static String userPermanent(int id) => '/users/$id/permanent';

  // ── Trailers ─────────────────────────────────────────────────────────────
  static const String trailers = '/trailers';
  static const String trailersMulberryReady =
      '/trailers/mulberry-ready-shipping';
  static String trailer(int id) => '/trailers/$id';
  static String trailerPriority(int id) => '/trailers/$id/priority';
  static String trailerHot(int id) => '/trailers/$id/hot';
  static String trailerSaleStatus(int id) => '/trailers/$id/sale-status';
  static String trailerMarkCompleted(int id) => '/trailers/$id/mark-completed';
  static String trailerPaintBooth(int id) => '/trailers/$id/paint-booth';
  static String trailerAddons(int id) => '/trailers/$id/addons';

  // ── Options / add-on accountability ──────────────────────────────────────
  /// Options on a trailer + who fits them + acknowledgement state.
  static String trailerOptions(int id) => '/trailers/$id/options';
  /// Options at a step, flagged with what THIS department must acknowledge.
  static String stepOptions(int stepId) => '/production/steps/$stepId/options';
  /// "I fitted it" — required before this department can complete its step.
  static String optionAcknowledge(int addonId) =>
      '/trailers/options/$addonId/acknowledge';
  /// Dashboard box: options added mid-build awaiting production-manager review.
  static const String optionsPendingReview = '/trailers/options/pending-review';
  /// Production manager clears an option off the dashboard.
  static String optionReview(int addonId) => '/trailers/options/$addonId/review';
  static String trailerAddon(int trailerId, int addonId) =>
      '/trailers/$trailerId/addons/$addonId';
  static String trailerQbPdf(int id) => '/trailers/$id/qb-pdf';
  static String trailerSteps(int id) => '/trailers/$id/steps';
  static String trailerHistory(int id) => '/trailers/$id/history';

  // ── Production ───────────────────────────────────────────────────────────
    static const String productionDepartments = '/production/departments';
  static const String productionStalledCount = '/production/stalled-count';
  static String productionQueue(int deptId) => '/production/queue/$deptId';
  static const String productionQueueAll = '/production/queue/all';
  static String stepComplete(int stepId) =>
      '/production/steps/$stepId/complete';
  static String stepChecklistItems(int stepId) =>
      '/production/steps/$stepId/checklist-items';
  static String trailerUpstreamChecks(int trailerId) =>
      '/production/trailers/$trailerId/upstream-checks';
  static String trailerJumpToStep(int trailerId) =>
      '/production/trailers/$trailerId/jump-to-step';
  static String stepReverse(int stepId) => '/production/steps/$stepId/reverse';
  static String reorderQueue(int deptId) =>
      '/production/queue/$deptId/reorder';

  // ── Quality Control ──────────────────────────────────────────────────────
  static const String qcStats = '/qc/stats';
  static const String qcFailedInspections = '/qc/failed-inspections';
  static const String qcReworkQueue = '/qc/rework-queue';
  static const String qcChecklistItems = '/qc/checklist-items';
  static const String qcInspections = '/qc/inspections';
  static String qcInspection(int id) => '/qc/inspections/$id';
  static String qcInspectionSendSms(int id) =>
      '/qc/inspections/$id/send-customer-sms';
  static String qcInspectionsForStep(int stepId) =>
      '/qc/inspections/step/$stepId';

  // ── Payroll ──────────────────────────────────────────────────────────────
  static const String payrollPointValues = '/payroll/point-values';
  static String payrollPointValue(int id) => '/payroll/point-values/$id';
  static const String payrollDollarRates = '/payroll/dollar-rates';
  static String payrollDollarRate(int id) => '/payroll/dollar-rates/$id';
  static const String payrollRecords = '/payroll/records';
  static String payrollWeekReport(String weekStart) =>
      '/payroll/records/week/$weekStart';
  static String payrollLockWeek(String weekStart) =>
      '/payroll/records/lock/$weekStart';
  static String payrollWorkerSummary(int userId) =>
      '/payroll/worker/$userId/summary';

  // ── Deliveries ───────────────────────────────────────────────────────────
  static const String deliveries = '/deliveries';
  static String delivery(int id) => '/deliveries/$id';
  static String deliveryDepart(int id) => '/deliveries/$id/depart';
  static String deliveryComplete(int id) => '/deliveries/$id/complete';
  static String deliveryFail(int id) => '/deliveries/$id/fail';
  static String deliveryPhotos(int id) => '/deliveries/$id/photos';
  static const String deliveryBatches = '/deliveries/batches';
  static String deliveryBatch(int id) => '/deliveries/batches/$id';
  static String deliveryBatchDepart(int id) =>
      '/deliveries/batches/$id/depart';
  static String deliveryBatchComplete(int id) =>
      '/deliveries/batches/$id/complete';
  static String factoryPickupComplete(int id) =>
      '/deliveries/factory-pickup/$id/complete';
  static const String deliveryStockInventory = '/deliveries/stock-inventory';

  // ── Customers ────────────────────────────────────────────────────────────
  static const String customers = '/customers';
  static String customer(int id) => '/customers/$id';


  // ── Locations ────────────────────────────────────────────────────────────
  static const String locations = '/locations';

    // ── Notifications & Messages ────────────────────────────────────────────
    static const String notifications = '/notifications';
    static const String messages = '/messages';

  // ── Storage ──────────────────────────────────────────────────────────────
  static const String storagePresign = '/storage/presign';
  static String storagePresignKey(String key) => '/storage/presign/$key';

  // ── Admin ────────────────────────────────────────────────────────────────
  static const String adminWorkflowTemplates = '/admin/workflow-templates';
  static const String adminDepartments = '/admin/departments';
  static const String adminTrailerModels = '/admin/trailer-models';
  static String adminDepartment(int id) => '/admin/departments/$id';
  static const String adminAuditLog = '/admin/audit-log';
  static String adminAuditEntity(String entityType, int id) =>
      '/admin/audit-log/$entityType/$id';
  static const String adminWeeklyProduction = '/admin/reports/weekly-production';
  static const String adminProductionCosts = '/admin/production-costs';
  static const String adminProductionReport = '/admin/production-report';

  // ── Announcements ────────────────────────────────────────────────────────
  static const String announcementsPending = '/announcements/pending';
  static String announcementAck(int id) => '/announcements/$id/ack';
  static const String adminAnnouncements = '/admin/announcements';
  static String adminAnnouncement(int id) => '/admin/announcements/$id';

  // ── Health ───────────────────────────────────────────────────────────────
  static const String health = '/health';
}
