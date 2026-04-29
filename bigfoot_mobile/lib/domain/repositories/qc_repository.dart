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

  factory QcQueueItem.fromJson(Map<String, dynamic> json) {
    return QcQueueItem(
      stepId: json['stepId'] as int? ?? json['step_id'] as int? ?? 0,
      trailerId: json['trailerId'] as int? ?? json['trailer_id'] as int? ?? 0,
      soNumber: json['soNumber'] as String? ?? json['so_number'] as String? ?? '',
      modelName: json['modelName'] as String? ?? json['model_name'] as String?,
      series: json['series'] as String?,
      departmentId: json['departmentId'] as int? ?? json['department_id'] as int? ?? 0,
      departmentCode: json['departmentCode'] as String? ?? json['department_code'] as String? ?? '',
      departmentName: json['departmentName'] as String? ?? json['department_name'] as String? ?? '',
      isRework: json['isRework'] as bool? ?? json['is_rework'] as bool? ?? false,
      reworkCount: json['reworkCount'] as int? ?? json['rework_count'] as int? ?? 0,
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
