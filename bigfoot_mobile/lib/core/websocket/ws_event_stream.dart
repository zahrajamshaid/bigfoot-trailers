/// All 12 WebSocket event types emitted by the backend.
abstract final class WsEventType {
  static const String stepCompleted = 'STEP_COMPLETED';
  static const String stepReversed = 'STEP_REVERSED';
  static const String qcPass = 'QC_PASS';
  static const String qcFail = 'QC_FAIL';
  static const String trailerReady = 'TRAILER_READY';
  static const String queueReordered = 'QUEUE_REORDERED';
  static const String priorityChanged = 'PRIORITY_CHANGED';
  static const String trailerStalled = 'TRAILER_STALLED';
  static const String deliveryDispatched = 'DELIVERY_DISPATCHED';
  static const String deliveryComplete = 'DELIVERY_COMPLETE';
  static const String pointsUpdated = 'POINTS_UPDATED';
  static const String workerMessage = 'WORKER_MESSAGE';

  static const List<String> all = [
    stepCompleted,
    stepReversed,
    qcPass,
    qcFail,
    trailerReady,
    queueReordered,
    priorityChanged,
    trailerStalled,
    deliveryDispatched,
    deliveryComplete,
    pointsUpdated,
    workerMessage,
  ];
}

/// Parsed WebSocket event.
class WsEvent {
  final String type;
  final String? channel;
  final Map<String, dynamic> data;
  final DateTime timestamp;

  const WsEvent({
    required this.type,
    this.channel,
    required this.data,
    required this.timestamp,
  });

  factory WsEvent.fromMap(String type, Map<String, dynamic> raw) {
    return WsEvent(
      type: type,
      channel: raw['channel'] as String?,
      data: raw['data'] as Map<String, dynamic>? ?? raw,
      timestamp: DateTime.now(),
    );
  }

  int? get trailerId => _asInt(data['trailerId'] ?? data['trailer_id']);
  int? get stepId => _asInt(data['stepId'] ?? data['step_id']);
  int? get departmentId => _asInt(data['departmentId'] ?? data['department_id']);
  int? get userId => _asInt(data['userId'] ?? data['user_id']);
  String? get soNumber => data['soNumber']?.toString() ?? data['so_number']?.toString();

  bool affectsDepartment(int id) {
    final channelDeptId = _extractRoomId('dept');
    return departmentId == id || channelDeptId == id;
  }

  bool affectsTrailer(int id) => trailerId == id;

  bool get isProductionEvent => const {
        WsEventType.stepCompleted,
        WsEventType.stepReversed,
        WsEventType.qcPass,
        WsEventType.qcFail,
        WsEventType.trailerReady,
        WsEventType.queueReordered,
        WsEventType.priorityChanged,
        WsEventType.trailerStalled,
        WsEventType.pointsUpdated,
      }.contains(type);

  bool get isDeliveryEvent => const {
        WsEventType.deliveryDispatched,
        WsEventType.deliveryComplete,
      }.contains(type);

  int? _extractRoomId(String prefix) {
    final room = channel;
    if (room == null || !room.startsWith('$prefix:')) return null;
    return int.tryParse(room.substring(prefix.length + 1));
  }

  static int? _asInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }
}
