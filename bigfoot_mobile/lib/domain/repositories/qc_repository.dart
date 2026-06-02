import '../../data/models/department.dart';
import '../../data/models/qc_inspection.dart';

class QcQueueItem {
  final int stepId;
  final int trailerId;
  final String soNumber;
  final String? modelName;
  final String? series;
  final int departmentId;
  final String departmentCode;
  final String departmentName;
  final bool isRework;
  final int reworkCount;
  final String? customerName;
  final DateTime? becameActiveAt;
  final String status; // 'active' | 'waiting'
  final String? currentStageCode;
  final String? currentStageName;

  const QcQueueItem({
    required this.stepId,
    required this.trailerId,
    required this.soNumber,
    this.modelName,
    this.series,
    required this.departmentId,
    required this.departmentCode,
    required this.departmentName,
    this.isRework = false,
    this.reworkCount = 0,
    this.customerName,
    this.becameActiveAt,
    this.status = 'active',
    this.currentStageCode,
    this.currentStageName,
  });

  bool get isWaiting => status == 'waiting';

  static int _toInt(dynamic value, [int fallback = 0]) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? fallback;
    return fallback;
  }

  static bool _toBool(dynamic value, [bool fallback = false]) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final v = value.trim().toLowerCase();
      if (v == 'true' || v == '1') return true;
      if (v == 'false' || v == '0') return false;
    }
    return fallback;
  }

  factory QcQueueItem.fromJson(Map<String, dynamic> json) {
    return QcQueueItem(
      stepId: _toInt(json['stepId'] ?? json['step_id']),
      trailerId: _toInt(json['trailerId'] ?? json['trailer_id']),
      soNumber: json['soNumber'] as String? ?? json['so_number'] as String? ?? '',
      modelName: json['modelName'] as String? ?? json['model_name'] as String?,
      series: (json['series'] ?? json['trailerSeries'] ?? json['trailer_series']) as String?,
      departmentId: _toInt(json['departmentId'] ?? json['department_id']),
      departmentCode: json['departmentCode'] as String? ?? json['department_code'] as String? ?? '',
      departmentName: json['departmentName'] as String? ?? json['department_name'] as String? ?? '',
      isRework: _toBool(json['isRework'] ?? json['is_rework']),
      reworkCount: _toInt(json['reworkCount'] ?? json['rework_count']),
      customerName: json['customerName'] as String? ?? json['customer_name'] as String?,
      becameActiveAt: json['becameActiveAt'] != null
          ? DateTime.tryParse(json['becameActiveAt'].toString())
          : json['became_active_at'] != null
              ? DateTime.tryParse(json['became_active_at'].toString())
              : null,
      status: json['status'] as String? ?? 'active',
      currentStageCode:
          json['currentStageCode'] as String? ?? json['current_stage_code'] as String?,
      currentStageName:
          json['currentStageName'] as String? ?? json['current_stage_name'] as String?,
    );
  }
}

/// One row in the failed-QC drilldown list. Flattened from the nested
/// /qc/failed-inspections payload so the screen can iterate cheaply.
class FailedInspectionItem {
  final int inspectionId;
  final DateTime? inspectedAt;
  final String? failNotes;
  final int attemptNumber;
  final bool isFinalQc;
  final int trailerId;
  final String soNumber;
  final String? modelName;
  final String? series;
  final String? customerName;
  final String? inspectorName;
  final String? reworkTargetCode;
  final String? reworkTargetName;
  final String? stepDeptCode;
  final String? stepDeptName;
  final int? stepOrder;

  const FailedInspectionItem({
    required this.inspectionId,
    required this.trailerId,
    required this.soNumber,
    this.inspectedAt,
    this.failNotes,
    this.attemptNumber = 1,
    this.isFinalQc = false,
    this.modelName,
    this.series,
    this.customerName,
    this.inspectorName,
    this.reworkTargetCode,
    this.reworkTargetName,
    this.stepDeptCode,
    this.stepDeptName,
    this.stepOrder,
  });

  factory FailedInspectionItem.fromJson(Map<String, dynamic> json) {
    final trailer = json['trailer'] as Map<String, dynamic>?;
    final model = trailer?['trailerModel'] as Map<String, dynamic>?;
    final customer = trailer?['customer'] as Map<String, dynamic>?;
    final inspector = json['inspectorUser'] as Map<String, dynamic>?;
    final rework = json['reworkTargetDept'] as Map<String, dynamic>?;
    final step = json['productionStep'] as Map<String, dynamic>?;
    final stepDept = step?['department'] as Map<String, dynamic>?;
    return FailedInspectionItem(
      inspectionId: (json['id'] as num).toInt(),
      inspectedAt: json['inspectedAt'] != null
          ? DateTime.tryParse(json['inspectedAt'].toString())
          : null,
      failNotes: json['failNotes'] as String?,
      attemptNumber: (json['attemptNumber'] as num?)?.toInt() ?? 1,
      isFinalQc: json['isFinalQc'] as bool? ?? false,
      trailerId: (trailer?['id'] as num?)?.toInt() ?? 0,
      soNumber: (trailer?['soNumber'] as String?) ?? '',
      modelName: model?['displayName'] as String?,
      series: model?['series'] as String?,
      customerName:
          (customer?['name'] as String?) ?? (trailer?['soldToName'] as String?),
      inspectorName: inspector?['fullName'] as String?,
      reworkTargetCode: rework?['code'] as String?,
      reworkTargetName: rework?['displayName'] as String?,
      stepDeptCode: stepDept?['code'] as String?,
      stepDeptName: stepDept?['displayName'] as String?,
      stepOrder: (step?['stepOrder'] as num?)?.toInt(),
    );
  }
}

/// One row in the rework drilldown list. Flattens the production_step
/// payload (with the trailer + dept context the list view renders).
class ReworkQueueItem {
  final int stepId;
  final int stepOrder;
  final int? queuePosition;
  final int reworkCount;
  final DateTime? becameActiveAt;
  final String? deptCode;
  final String? deptName;
  final int trailerId;
  final String soNumber;
  final bool isHot;
  final int globalPriority;
  final String? modelName;
  final String? series;
  final String? customerName;

  const ReworkQueueItem({
    required this.stepId,
    required this.stepOrder,
    required this.trailerId,
    required this.soNumber,
    this.queuePosition,
    this.reworkCount = 0,
    this.becameActiveAt,
    this.deptCode,
    this.deptName,
    this.isHot = false,
    this.globalPriority = 9999,
    this.modelName,
    this.series,
    this.customerName,
  });

  factory ReworkQueueItem.fromJson(Map<String, dynamic> json) {
    final dept = json['department'] as Map<String, dynamic>?;
    final trailer = json['trailer'] as Map<String, dynamic>?;
    final model = trailer?['trailerModel'] as Map<String, dynamic>?;
    final customer = trailer?['customer'] as Map<String, dynamic>?;
    return ReworkQueueItem(
      stepId: (json['id'] as num).toInt(),
      stepOrder: (json['stepOrder'] as num?)?.toInt() ?? 0,
      queuePosition: (json['queuePosition'] as num?)?.toInt(),
      reworkCount: (json['reworkCount'] as num?)?.toInt() ?? 0,
      becameActiveAt: json['becameActiveAt'] != null
          ? DateTime.tryParse(json['becameActiveAt'].toString())
          : null,
      deptCode: dept?['code'] as String?,
      deptName: dept?['displayName'] as String?,
      trailerId: (trailer?['id'] as num?)?.toInt() ?? 0,
      soNumber: (trailer?['soNumber'] as String?) ?? '',
      isHot: trailer?['isHot'] as bool? ?? false,
      globalPriority: (trailer?['globalPriority'] as num?)?.toInt() ?? 9999,
      modelName: model?['displayName'] as String?,
      series: model?['series'] as String?,
      customerName:
          (customer?['name'] as String?) ?? (trailer?['soldToName'] as String?),
    );
  }
}

class QcInspectionResult {
  final int inspectionId;
  final String result;
  final int? nextStepId;
  final String? nextDepartment;
  final String? trailerStatus;
  final bool isFinalQc;
  final bool smsReady;
  final String? reworkTargetDepartment;
  final int? reworkTargetDeptId;
  final int? reworkQueuePosition;

  const QcInspectionResult({
    required this.inspectionId,
    required this.result,
    this.nextStepId,
    this.nextDepartment,
    this.trailerStatus,
    this.isFinalQc = false,
    this.smsReady = false,
    this.reworkTargetDepartment,
    this.reworkTargetDeptId,
    this.reworkQueuePosition,
  });

  factory QcInspectionResult.fromJson(Map<String, dynamic> json) {
    return QcInspectionResult(
      inspectionId: json['inspectionId'] as int? ?? json['inspection_id'] as int? ?? 0,
      result: json['result'] as String? ?? 'pass',
      nextStepId: json['nextStepId'] as int? ?? json['next_step_id'] as int?,
      nextDepartment: json['nextDepartment'] as String? ?? json['next_department'] as String?,
      trailerStatus: json['trailerStatus'] as String? ?? json['trailer_status'] as String?,
      isFinalQc: json['isFinalQc'] as bool? ?? json['is_final_qc'] as bool? ?? false,
      smsReady: json['smsReady'] as bool? ?? json['sms_ready'] as bool? ?? false,
      reworkTargetDepartment: json['reworkTargetDepartment'] as String? ?? json['rework_target_department'] as String?,
      reworkTargetDeptId: json['reworkTargetDeptId'] as int? ?? json['rework_target_dept_id'] as int?,
      reworkQueuePosition: json['reworkQueuePosition'] as int? ?? json['rework_queue_position'] as int?,
    );
  }

  bool get isPassed => result == 'pass';
}

class UpstreamCheck {
  final int id;
  final bool passed;
  final String? note;
  final String itemLabel;
  final String? checkedByName;
  final String departmentCode;
  final String departmentName;

  const UpstreamCheck({
    required this.id,
    required this.passed,
    this.note,
    required this.itemLabel,
    this.checkedByName,
    required this.departmentCode,
    required this.departmentName,
  });

  factory UpstreamCheck.fromJson(Map<String, dynamic> json) {
    final item = json['checklistItem'] as Map<String, dynamic>?;
    final user = json['checkedByUser'] as Map<String, dynamic>?;
    final step = json['productionStep'] as Map<String, dynamic>?;
    final dept = step == null ? null : step['department'] as Map<String, dynamic>?;
    return UpstreamCheck(
      id: (json['id'] as num).toInt(),
      passed: json['passed'] as bool? ?? false,
      note: json['note'] as String?,
      itemLabel: (item?['itemLabel'] ?? item?['label'] ?? '').toString(),
      checkedByName: user?['fullName'] as String?,
      departmentCode: (dept?['code'] ?? '').toString(),
      departmentName: (dept?['displayName'] ?? '').toString(),
    );
  }
}

/// Abstract contract for QC operations.
abstract class QcRepository {
  Future<Map<String, List<QcQueueItem>>> getQcQueues();

  Future<List<QcChecklistItem>> getChecklistItems({
    required int departmentId,
    String? series,
    int? trailerId,
  });

  Future<List<Department>> getReworkTargets(int trailerId);

  Future<QcInspectionResult> submitInspection({
    required int productionStepId,
    required String result,
    String? failNotes,
    int? reworkTargetDepartmentId,
    required List<Map<String, dynamic>> checklistResults,
    required List<String> photoStorageKeys,
  });

  Future<QcInspection> getInspection(int id);

  Future<List<QcInspection>> getInspectionsForStep(int stepId);

  /// Backs the dashboard fail-rate drilldown. Returns failed inspections
  /// over a rolling window with the trailer + dept context the list view
  /// needs. Default window is 30 days.
  Future<List<FailedInspectionItem>> getFailedInspections({int days});

  /// Backs the dashboard rework-queue drilldown. Returns active
  /// production_steps where isRework=true — trailers waiting on a
  /// worker to redo an earlier step.
  Future<List<ReworkQueueItem>> getReworkQueue();

  Future<String> uploadPhoto(List<int> bytes, String filename);

  Future<List<QcChecklistItem>> getAllChecklistItems();

  Future<void> createChecklistItem({
    required int departmentId,
    required String label,
    int sortOrder,
    String appliesToSeries,
  });

  Future<void> updateChecklistItem(int id, {String? label, int? sortOrder, bool? isActive});

  Future<void> sendCustomerSms(int inspectionId);

  Future<List<UpstreamCheck>> getUpstreamChecksForTrailer(int trailerId);
}
