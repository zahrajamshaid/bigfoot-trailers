import 'package:equatable/equatable.dart';

/// One jig-weld department's live queue depth. Mirrors the API's
/// GET /production/jig-queues rows.
class JigQueue extends Equatable {
  final int departmentId;
  final String code;
  final String displayName;

  /// Trailers currently at / about to enter this jig (active + waiting steps).
  final int count;

  /// 'ok' | 'warning' | 'critical'.
  final String severity;

  const JigQueue({
    required this.departmentId,
    required this.code,
    required this.displayName,
    required this.count,
    required this.severity,
  });

  bool get isCritical => severity == 'critical';
  bool get isWarning => severity == 'warning';
  bool get isLow => isCritical || isWarning;

  factory JigQueue.fromJson(Map<String, dynamic> j) => JigQueue(
        departmentId: (j['departmentId'] as num?)?.toInt() ?? 0,
        code: j['code'] as String? ?? '',
        displayName: j['displayName'] as String? ?? '',
        count: (j['count'] as num?)?.toInt() ?? 0,
        severity: j['severity'] as String? ?? 'ok',
      );

  @override
  List<Object?> get props => [departmentId, code, count, severity];
}

/// The whole jig board: per-jig queues plus the worst severity across them
/// (drives the dashboard banner) and the thresholds used to classify them.
class JigQueueBoard extends Equatable {
  final List<JigQueue> queues;
  final String worstSeverity; // 'ok' | 'warning' | 'critical'
  final int warnThreshold;
  final int criticalThreshold;

  const JigQueueBoard({
    required this.queues,
    required this.worstSeverity,
    required this.warnThreshold,
    required this.criticalThreshold,
  });

  bool get hasLow => worstSeverity != 'ok';
  bool get hasCritical => worstSeverity == 'critical';

  /// Jigs currently at warning or critical — the ones that need orders.
  List<JigQueue> get lowQueues => queues.where((q) => q.isLow).toList();

  factory JigQueueBoard.fromJson(Map<String, dynamic> j) => JigQueueBoard(
        queues: ((j['queues'] as List<dynamic>?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(JigQueue.fromJson)
            .toList(),
        worstSeverity: j['worstSeverity'] as String? ?? 'ok',
        warnThreshold: (j['warnThreshold'] as num?)?.toInt() ?? 5,
        criticalThreshold: (j['criticalThreshold'] as num?)?.toInt() ?? 2,
      );

  @override
  List<Object?> get props =>
      [queues, worstSeverity, warnThreshold, criticalThreshold];
}
