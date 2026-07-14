import '../../../core/constants/api_endpoints.dart';
import '../../../core/network/dio_client.dart';

/// One department's responsibility for an option, and whether it's done.
class OptionFitter {
  final String code;
  final bool acknowledged;
  final String? acknowledgedBy;

  const OptionFitter({
    required this.code,
    required this.acknowledged,
    this.acknowledgedBy,
  });

  factory OptionFitter.fromJson(Map<String, dynamic> j) => OptionFitter(
        code: j['code'] as String? ?? '',
        acknowledged: j['acknowledged'] as bool? ?? false,
        acknowledgedBy: j['acknowledgedBy'] as String?,
      );
}

/// An option (add-on) line item on a trailer.
///
/// An option can need MORE THAN ONE department (D-rings welded at JIG, touched
/// up at PAINT), and each acknowledges its own part independently — so the
/// acknowledgement lives per-department in [fittedBy], not on the option.
class TrailerOption {
  final int id;
  final String addonName;
  final String? notes;

  /// Every department that has to fit part of this option.
  final List<OptionFitter> fittedBy;

  /// True when THIS step's department must tick it before it can continue.
  final bool mustAcknowledge;

  /// True when this option is any of this department's business.
  final bool forThisDepartment;

  /// The id to POST when acknowledging — the option-department assignment,
  /// because each department acknowledges its own part.
  final int? myAckId;

  /// Added after the build had already started — the dangerous case.
  final bool addedDuringProduction;

  const TrailerOption({
    required this.id,
    required this.addonName,
    this.notes,
    this.fittedBy = const [],
    this.mustAcknowledge = false,
    this.forThisDepartment = false,
    this.myAckId,
    this.addedDuringProduction = false,
  });

  /// This department has already done its part.
  bool get isAcknowledgedByMe => forThisDepartment && !mustAcknowledge;

  /// Everyone still owing work on this option.
  List<String> get outstanding =>
      fittedBy.where((f) => !f.acknowledged).map((f) => f.code).toList();

  factory TrailerOption.fromJson(Map<String, dynamic> j) => TrailerOption(
        id: (j['id'] as num).toInt(),
        addonName: j['addonName'] as String? ?? '',
        notes: j['notes'] as String?,
        fittedBy: ((j['fittedBy'] as List<dynamic>?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(OptionFitter.fromJson)
            .toList(),
        mustAcknowledge: j['mustAcknowledge'] as bool? ?? false,
        forThisDepartment: j['forThisDepartment'] as bool? ?? false,
        myAckId: (j['myAckId'] as num?)?.toInt(),
        addedDuringProduction: j['addedDuringProduction'] as bool? ?? false,
      );
}

/// One stage on a trailer's line — the PM can move the build to any of these,
/// backwards or forwards.
class OptionStep {
  final int stepId;
  final int stepOrder;
  final String code;
  final String name;
  final String status;
  final bool isCurrent;

  /// This stage still has to fit the option.
  final bool owes;

  const OptionStep({
    required this.stepId,
    required this.stepOrder,
    required this.code,
    required this.name,
    required this.status,
    this.isCurrent = false,
    this.owes = false,
  });

  factory OptionStep.fromJson(Map<String, dynamic> j) => OptionStep(
        stepId: (j['stepId'] as num).toInt(),
        stepOrder: (j['stepOrder'] as num?)?.toInt() ?? 0,
        code: j['code'] as String? ?? '',
        name: j['name'] as String? ?? '',
        status: j['status'] as String? ?? '',
        isCurrent: j['isCurrent'] as bool? ?? false,
        owes: j['owes'] as bool? ?? false,
      );
}

/// A row on the production-manager dashboard: an option added mid-build.
class PendingOptionReview {
  final int id;
  final String option;
  final String? notes;
  final int trailerId;
  final String soNumber;
  final String model;
  final String addedBy;
  final String? addedAt;

  /// Where the build was when the option landed ("added past WELD").
  final String? addedPastDepartment;

  /// Everyone who has to fit it, and whether they've done their part.
  final List<OptionFitter> fittedBy;

  /// Departments that still owe work.
  final List<String> outstandingDepartments;

  /// Departments the build has ALREADY PASSED that still owe work — they will
  /// never see this option unless the trailer is sent back.
  final List<String> missedDepartments;

  /// Every stage on this trailer's line — move the build back or forward.
  final List<OptionStep> steps;

  /// The step to send it back to (earliest missed stage), if any.
  final int? rollbackStepId;

  /// The DEPARTMENT to send it back to — named, so nothing has to reason about
  /// opaque step ids ("send back to XP Jig", not "send back to step 529").
  final String? rollbackDepartmentCode;
  final String? rollbackDepartmentName;

  /// Where the build is right now.
  final String? currentDepartment;
  final int? currentStepId;

  /// THE signal: the build has already passed the department that must fit
  /// this option. Left alone, this trailer gets finished wrong.
  final bool needsRollback;

  const PendingOptionReview({
    required this.id,
    required this.option,
    this.notes,
    required this.trailerId,
    required this.soNumber,
    required this.model,
    required this.addedBy,
    this.addedAt,
    this.addedPastDepartment,
    this.fittedBy = const [],
    this.outstandingDepartments = const [],
    this.missedDepartments = const [],
    this.steps = const [],
    this.rollbackStepId,
    this.rollbackDepartmentCode,
    this.rollbackDepartmentName,
    this.currentDepartment,
    this.currentStepId,
    this.needsRollback = false,
  });

  static String? _code(dynamic v) =>
      v is Map<String, dynamic> ? v['code'] as String? : null;

  factory PendingOptionReview.fromJson(Map<String, dynamic> j) =>
      PendingOptionReview(
        id: (j['id'] as num).toInt(),
        option: j['option'] as String? ?? '',
        notes: j['notes'] as String?,
        trailerId: (j['trailerId'] as num).toInt(),
        soNumber: j['soNumber'] as String? ?? '-',
        model: j['model'] as String? ?? '-',
        addedBy: j['addedBy'] as String? ?? 'Unknown',
        addedAt: j['addedAt'] as String?,
        addedPastDepartment: j['addedPastDepartment'] as String?,
        fittedBy: ((j['fittedBy'] as List<dynamic>?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(OptionFitter.fromJson)
            .toList(),
        outstandingDepartments:
            ((j['outstandingDepartments'] as List<dynamic>?) ?? const [])
                .whereType<String>()
                .toList(),
        missedDepartments:
            ((j['missedDepartments'] as List<dynamic>?) ?? const [])
                .whereType<String>()
                .toList(),
        steps: ((j['steps'] as List<dynamic>?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(OptionStep.fromJson)
            .toList(),
        rollbackStepId: (j['rollbackStepId'] as num?)?.toInt(),
        rollbackDepartmentCode: _code(j['rollbackDepartment']),
        rollbackDepartmentName: j['rollbackDepartment'] is Map<String, dynamic>
            ? (j['rollbackDepartment'] as Map<String, dynamic>)['name'] as String?
            : null,
        currentDepartment: _code(j['currentDepartment']),
        currentStepId: (j['currentStepId'] as num?)?.toInt(),
        needsRollback: j['needsRollback'] as bool? ?? false,
      );
}

class TrailerOptionsApi {
  final DioClient _api;
  TrailerOptionsApi(this._api);

  /// Options at a step — what this department must acknowledge vs can skip.
  Future<List<TrailerOption>> forStep(int stepId) async {
    final res = await _api.get<List<dynamic>>(
      ApiEndpoints.stepOptions(stepId),
      fromJson: (d) => d as List<dynamic>,
    );
    return (res.data ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(TrailerOption.fromJson)
        .toList();
  }

  Future<List<TrailerOption>> forTrailer(int trailerId) async {
    final res = await _api.get<List<dynamic>>(
      ApiEndpoints.trailerOptions(trailerId),
      fromJson: (d) => d as List<dynamic>,
    );
    return (res.data ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(TrailerOption.fromJson)
        .toList();
  }

  /// Add an option. [installDepartmentIds] is EVERY department that has to fit
  /// part of it — an option can need more than one (D-rings welded at JIG,
  /// touched up at PAINT). Each must acknowledge its own part before it can
  /// complete its step. With none, the option blocks nobody — which is why the
  /// UI insists on at least one.
  Future<void> addOption({
    required int trailerId,
    required String addonName,
    required List<int> installDepartmentIds,
    String? notes,
  }) async {
    await _api.post<Map<String, dynamic>>(
      ApiEndpoints.trailerOptions(trailerId),
      data: {
        'addonName': addonName,
        'installDepartmentIds': installDepartmentIds,
        if (notes != null && notes.isNotEmpty) 'notes': notes,
      },
      fromJson: (d) => d as Map<String, dynamic>,
    );
  }

  /// Departments that can fit an option (production depts, not QC).
  Future<List<({int id, String code, String name})>> installDepartments() async {
    final res = await _api.get<List<dynamic>>(
      ApiEndpoints.productionDepartments,
      fromJson: (d) => d as List<dynamic>,
    );
    return (res.data ?? const [])
        .whereType<Map<String, dynamic>>()
        // A QC department inspects; it doesn't fit options.
        .where((d) => d['isQcStep'] != true)
        .map((d) => (
              id: (d['id'] as num).toInt(),
              code: d['code'] as String? ?? '',
              name: d['displayName'] as String? ?? d['code'] as String? ?? '',
            ))
        .toList();
  }

  /// "Yes, I fitted this." Unblocks this department's step completion.
  Future<void> acknowledge(int addonId) async {
    await _api.post<Map<String, dynamic>>(
      ApiEndpoints.optionAcknowledge(addonId),
      fromJson: (d) => d as Map<String, dynamic>,
    );
  }

  /// Production-manager dashboard: options added mid-build, unreviewed.
  Future<List<PendingOptionReview>> pendingReview() async {
    final res = await _api.get<List<dynamic>>(
      ApiEndpoints.optionsPendingReview,
      fromJson: (d) => d as List<dynamic>,
    );
    return (res.data ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(PendingOptionReview.fromJson)
        .toList();
  }

  /// Move the build to any stage — BACKWARDS to a stage that was missed, or
  /// FORWARDS past one. The jump-to-step endpoint handles both directions
  /// (forces upstream complete, resets downstream to waiting).
  Future<void> moveToStep({
    required int trailerId,
    required int stepId,
    String? reason,
  }) async {
    await _api.post<Map<String, dynamic>>(
      ApiEndpoints.trailerJumpToStep(trailerId),
      data: {'stepId': stepId, if (reason != null) 'reason': reason},
      fromJson: (d) => d as Map<String, dynamic>,
    );
  }

  /// PM has seen it → clears it off the dashboard.
  Future<void> review(int addonId) async {
    await _api.post<Map<String, dynamic>>(
      ApiEndpoints.optionReview(addonId),
      fromJson: (d) => d as Map<String, dynamic>,
    );
  }
}
