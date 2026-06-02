/// Named route constants for GoRouter navigation.
abstract final class RouteNames {
  // ── Auth ─────────────────────────────────────────────────────────────────
  static const String splash = 'splash';
  static const String login = 'login';

  // ── Shell ────────────────────────────────────────────────────────────────
  static const String shell = 'shell';

  // ── Dashboard ────────────────────────────────────────────────────────────
  static const String dashboard = 'dashboard';

  // ── Trailers ─────────────────────────────────────────────────────────────
  static const String trailerList = 'trailerList';
  static const String trailerCreate = 'trailerCreate';
  static const String trailerEdit = 'trailerEdit';
  static const String trailerDetail = 'trailerDetail';

  // ── Production ───────────────────────────────────────────────────────────
  static const String productionQueue = 'productionQueue';
  static const String productionAllQueues = 'productionAllQueues';

  // ── QC ───────────────────────────────────────────────────────────────────
  static const String qcQueue = 'qcQueue';
  static const String qcFailed = 'qcFailed';
  static const String qcInspectionForm = 'qcInspectionForm';
  static const String qcInspectionDetail = 'qcInspectionDetail';

  // ── Deliveries ───────────────────────────────────────────────────────────
  static const String deliveryList = 'deliveryList';
  static const String deliveryCreate = 'deliveryCreate';
  static const String deliveryDetail = 'deliveryDetail';
  static const String deliveryBatches = 'deliveryBatches';
  static const String stockInventory = 'stockInventory';
  static const String deliveryDriver = 'deliveryDriver';

  // ── Payroll ──────────────────────────────────────────────────────────────
  static const String workerPoints = 'workerPoints';
  static const String weeklyReport = 'weeklyReport';
  static const String pointMatrix = 'pointMatrix';
  static const String dollarRates = 'dollarRates';

  // ── Admin ────────────────────────────────────────────────────────────────
  static const String adminDashboard = 'adminDashboard';
  static const String userManagement = 'userManagement';
  static const String departmentConfig = 'departmentConfig';
  static const String workflowViewer = 'workflowViewer';
  static const String auditLog = 'auditLog';
  static const String adminReports = 'adminReports';

  // ── Customers ────────────────────────────────────────────────────────────
  static const String customerList = 'customerList';
  static const String customerDetail = 'customerDetail';

  // ── Notifications ───────────────────────────────────────────────────────
  static const String notificationsCenter = 'notificationsCenter';
  static const String workerMessages = 'workerMessages';
  static const String pdfViewer = 'pdfViewer';

  // ── Settings ─────────────────────────────────────────────────────────────
  static const String settings = 'settings';
}
