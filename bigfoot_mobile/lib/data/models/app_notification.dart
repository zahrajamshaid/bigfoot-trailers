class NotificationType {
  static const String qcFail = 'qc_fail';
  static const String paymentNotCollected = 'payment_not_collected';
  static const String trailerStalled = 'trailer_stalled';
  static const String deliveryDispatched = 'delivery_dispatched';
  static const String deliveryComplete = 'delivery_complete';
  static const String workerMessage = 'worker_message';

  static const values = [
    qcFail,
    paymentNotCollected,
    trailerStalled,
    deliveryDispatched,
    deliveryComplete,
    workerMessage,
  ];
}

class AppNotification {
  final String id;
  final String type;
  final String title;
  final String body;
  final DateTime timestamp;
  final bool isRead;
  final Map<String, dynamic>? payload;

  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.timestamp,
    this.isRead = false,
    this.payload,
  });

  AppNotification copyWith({
    bool? isRead,
  }) {
    return AppNotification(
      id: id,
      type: type,
      title: title,
      body: body,
      timestamp: timestamp,
      isRead: isRead ?? this.isRead,
      payload: payload,
    );
  }

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    return AppNotification(
      id: json['id']?.toString() ??
          '${json['type'] ?? 'n'}-${DateTime.now().millisecondsSinceEpoch}',
      type: json['type'] as String? ?? NotificationType.workerMessage,
      title: json['title'] as String? ?? 'Notification',
      body: json['body'] as String? ?? '',
      timestamp: json['timestamp'] == null
          ? DateTime.now()
          : DateTime.tryParse(json['timestamp'] as String) ?? DateTime.now(),
      isRead: json['isRead'] as bool? ?? false,
      payload: json['payload'] as Map<String, dynamic>?,
    );
  }
}
