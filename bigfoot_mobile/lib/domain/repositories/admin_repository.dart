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
  /// Human label for the changed entity (e.g. "SO 6715", "SO 6715 — QC_3 QC").
  /// Server-supplied. Falls back to "{entityType} #{entityId}" if the API is
  /// older or the entity has been deleted.
  final String entityLabel;
  /// Action rendered as a verb the admin recognises (e.g. "Updated",
  /// "Jumped to step"). Server-supplied; falls back to the raw action string.
  final String actionLabel;
  /// One-line description of what changed, derived from old/new values when
  /// possible (e.g. "Status: in_production → ready_for_delivery"). Server-
  /// supplied; falls back to the action label.
  final String summary;

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
    required this.entityLabel,
    required this.actionLabel,
    required this.summary,
  });

  factory AdminAuditLogEntry.fromJson(Map<String, dynamic> json) {
    final user = json['user'] as Map<String, dynamic>?;
    final entityType = json['entityType'] as String;
    final entityId = (json['entityId'] as num).toInt();
    final action = json['action'] as String;
    return AdminAuditLogEntry(
      id: (json['id'] as num).toInt(),
      userId: (json['userId'] as num?)?.toInt(),
      entityType: entityType,
      entityId: entityId,
      action: action,
      oldValues: json['oldValues'] as Map<String, dynamic>?,
      newValues: json['newValues'] as Map<String, dynamic>?,
      ipAddress: json['ipAddress'] as String?,
      createdAt: json['createdAt'] == null
          ? null
          : DateTime.tryParse(json['createdAt'] as String),
      userName: user?['fullName'] as String?,
      entityLabel:
          (json['entityLabel'] as String?) ?? '$entityType #$entityId',
      actionLabel: (json['actionLabel'] as String?) ?? action,
      summary: (json['summary'] as String?) ?? action,
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
    /// Free-text search. Numeric → resolves to a trailer SO and pulls in
    /// every step / QC / delivery row for that trailer. Non-numeric →
    /// matches against user.fullName + action (case-insensitive).
    String? q,
  });

  Future<List<AdminAuditLogEntry>> getAuditEntityHistory(String entityType, int id);

  Future<AdminWeeklyProductionReport> getWeeklyProductionReport(String weekStartIso);

  // ── Production cost matrix ───────────────────────────────────────────────
  Future<ProductionCostMatrix> getProductionCostMatrix();

  /// Upsert a single (trailer model, department) cost cell. Same-day calls
  /// for the same pair update in-place; backdating creates a new history row.
  Future<void> upsertProductionCost({
    required int trailerModelId,
    required int departmentId,
    required double costDollars,
    String? effectiveFrom,
  });

  // ── Health Check report (period throughput + sales + live dept board) ───
  // Internally still called the "production report" — only the user-facing
  // label was renamed. Server path: GET /admin/production-report.
  Future<HealthCheckReport> getHealthCheckReport(HealthCheckQuery query);
}

// ===========================================================================
// Production cost matrix
// ===========================================================================

class ProductionCostMatrix {
  final List<ProductionCostModel> models;
  final List<ProductionCostDepartment> departments;
  /// Sparse list — only cells that have a value. Mobile renders missing cells
  /// as a hint so admin can spot what still needs a number.
  final List<ProductionCostCell> cells;

  const ProductionCostMatrix({
    required this.models,
    required this.departments,
    required this.cells,
  });

  factory ProductionCostMatrix.fromJson(Map<String, dynamic> json) {
    return ProductionCostMatrix(
      models: (json['models'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(ProductionCostModel.fromJson)
          .toList(),
      departments: (json['departments'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(ProductionCostDepartment.fromJson)
          .toList(),
      cells: (json['cells'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(ProductionCostCell.fromJson)
          .toList(),
    );
  }

  /// Quick lookup for the cost at a given (model, dept) cell. Returns null
  /// when the admin hasn't filled it in yet.
  double? costFor(int modelId, int deptId) {
    for (final c in cells) {
      if (c.trailerModelId == modelId && c.departmentId == deptId) {
        return c.costDollars;
      }
    }
    return null;
  }
}

class ProductionCostModel {
  final int id;
  final String code;
  final String displayName;
  final String series;
  const ProductionCostModel({
    required this.id,
    required this.code,
    required this.displayName,
    required this.series,
  });
  factory ProductionCostModel.fromJson(Map<String, dynamic> j) =>
      ProductionCostModel(
        id: (j['id'] as num).toInt(),
        code: j['code'] as String,
        displayName: j['displayName'] as String,
        series: j['series'] as String,
      );
}

class ProductionCostDepartment {
  final int id;
  final String code;
  final String displayName;
  const ProductionCostDepartment({
    required this.id,
    required this.code,
    required this.displayName,
  });
  factory ProductionCostDepartment.fromJson(Map<String, dynamic> j) =>
      ProductionCostDepartment(
        id: (j['id'] as num).toInt(),
        code: j['code'] as String,
        displayName: j['displayName'] as String,
      );
}

class ProductionCostCell {
  final int trailerModelId;
  final int departmentId;
  final double costDollars;
  final String effectiveFrom;
  const ProductionCostCell({
    required this.trailerModelId,
    required this.departmentId,
    required this.costDollars,
    required this.effectiveFrom,
  });
  factory ProductionCostCell.fromJson(Map<String, dynamic> j) =>
      ProductionCostCell(
        trailerModelId: (j['trailerModelId'] as num).toInt(),
        departmentId: (j['departmentId'] as num).toInt(),
        costDollars: (j['costDollars'] as num).toDouble(),
        effectiveFrom: j['effectiveFrom'] as String,
      );
}

// ===========================================================================
// Health Check report (formerly "Production Report")
// ===========================================================================

enum HealthCheckPeriod { weekly, biweekly, monthly, custom }

extension HealthCheckPeriodWire on HealthCheckPeriod {
  String get wire {
    switch (this) {
      case HealthCheckPeriod.weekly:
        return 'weekly';
      case HealthCheckPeriod.biweekly:
        return 'biweekly';
      case HealthCheckPeriod.monthly:
        return 'monthly';
      case HealthCheckPeriod.custom:
        return 'custom';
    }
  }

  String get label {
    switch (this) {
      case HealthCheckPeriod.weekly:
        return 'Weekly';
      case HealthCheckPeriod.biweekly:
        return '2-week';
      case HealthCheckPeriod.monthly:
        return 'Monthly';
      case HealthCheckPeriod.custom:
        return 'Custom';
    }
  }
}

class HealthCheckQuery {
  final HealthCheckPeriod period;
  /// YYYY-MM-DD. For weekly/biweekly/monthly any date inside the desired
  /// window; for custom this is the inclusive window start.
  final String? start;
  /// YYYY-MM-DD. Only used (and required) when period == custom.
  final String? end;

  const HealthCheckQuery({
    required this.period,
    this.start,
    this.end,
  });
}

class HealthCheckReport {
  final HealthCheckWindow window;
  final HealthCheckWindow previousWindow;
  final HealthCheckPeriodSnapshot current;
  final HealthCheckPeriodSnapshot previous;
  final HealthCheckLive live;
  final ProductionWipCost wipCost;

  const HealthCheckReport({
    required this.window,
    required this.previousWindow,
    required this.current,
    required this.previous,
    required this.live,
    required this.wipCost,
  });

  factory HealthCheckReport.fromJson(Map<String, dynamic> j) =>
      HealthCheckReport(
        window: HealthCheckWindow.fromJson(
          j['window'] as Map<String, dynamic>,
        ),
        previousWindow: HealthCheckWindow.fromJson(
          j['previousWindow'] as Map<String, dynamic>,
        ),
        current: HealthCheckPeriodSnapshot.fromJson(
          j['current'] as Map<String, dynamic>,
        ),
        previous: HealthCheckPeriodSnapshot.fromJson(
          j['previous'] as Map<String, dynamic>,
        ),
        live: HealthCheckLive.fromJson(j['live'] as Map<String, dynamic>),
        wipCost: ProductionWipCost.fromJson(
          j['wipCost'] as Map<String, dynamic>,
        ),
      );
}

class HealthCheckWindow {
  /// Only present on the current window — the previous-window block sends
  /// just start/end so the period field is null for it.
  final HealthCheckPeriod? period;
  final String start; // inclusive YYYY-MM-DD
  final String end; // inclusive YYYY-MM-DD
  const HealthCheckWindow({this.period, required this.start, required this.end});

  factory HealthCheckWindow.fromJson(Map<String, dynamic> j) {
    HealthCheckPeriod? p;
    final wire = j['period'] as String?;
    switch (wire) {
      case 'weekly':
        p = HealthCheckPeriod.weekly;
        break;
      case 'biweekly':
        p = HealthCheckPeriod.biweekly;
        break;
      case 'monthly':
        p = HealthCheckPeriod.monthly;
        break;
      case 'custom':
        p = HealthCheckPeriod.custom;
        break;
      default:
        p = null;
    }
    return HealthCheckWindow(
      period: p,
      start: j['start'] as String,
      end: j['end'] as String,
    );
  }
}

class HealthCheckPeriodSnapshot {
  final HealthCheckThroughput throughput;
  final HealthCheckSales sales;
  final HealthCheckSoldVsBuilt soldVsBuilt;
  const HealthCheckPeriodSnapshot({
    required this.throughput,
    required this.sales,
    required this.soldVsBuilt,
  });

  factory HealthCheckPeriodSnapshot.fromJson(Map<String, dynamic> j) =>
      HealthCheckPeriodSnapshot(
        throughput: HealthCheckThroughput.fromJson(
          j['throughput'] as Map<String, dynamic>,
        ),
        sales:
            HealthCheckSales.fromJson(j['sales'] as Map<String, dynamic>),
        soldVsBuilt: HealthCheckSoldVsBuilt.fromJson(
          j['soldVsBuilt'] as Map<String, dynamic>,
        ),
      );
}

class HealthCheckThroughput {
  final int enteredProduction;
  final int exitedProduction;
  final int delivered;
  final Map<String, int> exitedBySeries;
  const HealthCheckThroughput({
    required this.enteredProduction,
    required this.exitedProduction,
    required this.delivered,
    required this.exitedBySeries,
  });
  factory HealthCheckThroughput.fromJson(Map<String, dynamic> j) {
    final raw = j['exitedBySeries'] as Map<String, dynamic>? ?? const {};
    return HealthCheckThroughput(
      enteredProduction: (j['enteredProduction'] as num).toInt(),
      exitedProduction: (j['exitedProduction'] as num).toInt(),
      delivered: (j['delivered'] as num).toInt(),
      exitedBySeries: raw.map((k, v) => MapEntry(k, (v as num).toInt())),
    );
  }
}

class HealthCheckSales {
  final int customerOrders;
  final int openStockSold;
  final int totalSales;
  const HealthCheckSales({
    required this.customerOrders,
    required this.openStockSold,
    required this.totalSales,
  });
  factory HealthCheckSales.fromJson(Map<String, dynamic> j) => HealthCheckSales(
        customerOrders: (j['customerOrders'] as num).toInt(),
        openStockSold: (j['openStockSold'] as num).toInt(),
        totalSales: (j['totalSales'] as num).toInt(),
      );
}

class HealthCheckSoldVsBuilt {
  final List<HealthCheckModelLine> perModel;
  final int totalSold;
  final int totalBuilt;
  const HealthCheckSoldVsBuilt({
    required this.perModel,
    required this.totalSold,
    required this.totalBuilt,
  });
  factory HealthCheckSoldVsBuilt.fromJson(Map<String, dynamic> j) =>
      HealthCheckSoldVsBuilt(
        perModel: (j['perModel'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(HealthCheckModelLine.fromJson)
            .toList(),
        totalSold: (j['totalSold'] as num).toInt(),
        totalBuilt: (j['totalBuilt'] as num).toInt(),
      );
}

class HealthCheckModelLine {
  final int modelId;
  final String modelCode;
  final String modelName;
  final String series;
  final int sold;
  final int built;
  const HealthCheckModelLine({
    required this.modelId,
    required this.modelCode,
    required this.modelName,
    required this.series,
    required this.sold,
    required this.built,
  });
  factory HealthCheckModelLine.fromJson(Map<String, dynamic> j) =>
      HealthCheckModelLine(
        modelId: (j['modelId'] as num).toInt(),
        modelCode: j['modelCode'] as String,
        modelName: j['modelName'] as String,
        series: j['series'] as String,
        sold: (j['sold'] as num).toInt(),
        built: (j['built'] as num).toInt(),
      );
}

class HealthCheckLive {
  final int inProduction;
  final int readyForDelivery;
  final List<ProductionInventoryYard> inventoryByYard;
  final List<HealthCheckDeptTile> departments;
  final int soldNotStartedTotal;

  const HealthCheckLive({
    required this.inProduction,
    required this.readyForDelivery,
    required this.inventoryByYard,
    required this.departments,
    required this.soldNotStartedTotal,
  });

  factory HealthCheckLive.fromJson(Map<String, dynamic> j) => HealthCheckLive(
        inProduction: (j['inProduction'] as num).toInt(),
        readyForDelivery: (j['readyForDelivery'] as num).toInt(),
        inventoryByYard: (j['inventoryByYard'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(ProductionInventoryYard.fromJson)
            .toList(),
        departments: (j['departments'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(HealthCheckDeptTile.fromJson)
            .toList(),
        soldNotStartedTotal: (j['soldNotStartedTotal'] as num?)?.toInt() ?? 0,
      );
}

class HealthCheckDeptTile {
  final int departmentId;
  final String code;
  final String displayName;
  /// Trailers currently active at this dept, including any QC steps rolled
  /// back to the prod step they inspect.
  final int waiting;
  /// Sold trailers (customer order OR pre-sold stock) with zero completed
  /// steps yet, bucketed onto their first workflow dept.
  final int soldNotStarted;

  const HealthCheckDeptTile({
    required this.departmentId,
    required this.code,
    required this.displayName,
    required this.waiting,
    required this.soldNotStarted,
  });

  factory HealthCheckDeptTile.fromJson(Map<String, dynamic> j) =>
      HealthCheckDeptTile(
        departmentId: (j['departmentId'] as num).toInt(),
        code: j['code'] as String,
        displayName: j['displayName'] as String,
        waiting: (j['waiting'] as num).toInt(),
        soldNotStarted: (j['soldNotStarted'] as num).toInt(),
      );
}

class ProductionInventoryYard {
  final int locationId;
  final String code;
  final String name;
  final bool isFactory;
  final int count;
  const ProductionInventoryYard({
    required this.locationId,
    required this.code,
    required this.name,
    required this.isFactory,
    required this.count,
  });
  factory ProductionInventoryYard.fromJson(Map<String, dynamic> j) =>
      ProductionInventoryYard(
        locationId: (j['locationId'] as num).toInt(),
        code: j['code'] as String,
        name: j['name'] as String,
        isFactory: j['isFactory'] as bool? ?? false,
        count: (j['count'] as num).toInt(),
      );
}

class ProductionWipCost {
  final double totalCumulativeDollars;
  final double totalProjectedDollars;
  final List<ProductionWipTrailer> perTrailer;
  const ProductionWipCost({
    required this.totalCumulativeDollars,
    required this.totalProjectedDollars,
    required this.perTrailer,
  });
  factory ProductionWipCost.fromJson(Map<String, dynamic> j) =>
      ProductionWipCost(
        totalCumulativeDollars:
            (j['totalCumulativeDollars'] as num).toDouble(),
        totalProjectedDollars:
            (j['totalProjectedDollars'] as num).toDouble(),
        perTrailer: (j['perTrailer'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(ProductionWipTrailer.fromJson)
            .toList(),
      );
}

class ProductionWipTrailer {
  final String trailerId;
  final String soNumber;
  final String modelCode;
  final String modelName;
  final double cumulativeDollars;
  final double projectedDollars;
  const ProductionWipTrailer({
    required this.trailerId,
    required this.soNumber,
    required this.modelCode,
    required this.modelName,
    required this.cumulativeDollars,
    required this.projectedDollars,
  });
  factory ProductionWipTrailer.fromJson(Map<String, dynamic> j) =>
      ProductionWipTrailer(
        trailerId: j['trailerId'] as String,
        soNumber: j['soNumber'] as String,
        modelCode: j['modelCode'] as String,
        modelName: j['modelName'] as String? ?? '',
        cumulativeDollars: (j['cumulativeDollars'] as num).toDouble(),
        projectedDollars: (j['projectedDollars'] as num).toDouble(),
      );
}
