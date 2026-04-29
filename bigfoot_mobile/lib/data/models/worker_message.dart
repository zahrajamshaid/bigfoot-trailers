class WorkerMessage {
  final int id;
  final int trailerId;
  final int senderUserId;
  final int recipientUserId;
  final String body;
  final DateTime sentAt;
  final String? senderName;
  final String? recipientName;

  const WorkerMessage({
    required this.id,
    required this.trailerId,
    required this.senderUserId,
    required this.recipientUserId,
    required this.body,
    required this.sentAt,
    this.senderName,
    this.recipientName,
  });

  factory WorkerMessage.fromJson(Map<String, dynamic> json) {
    return WorkerMessage(
      id: (json['id'] as num?)?.toInt() ?? 0,
      trailerId: (json['trailerId'] as num?)?.toInt() ?? 0,
      senderUserId: (json['senderUserId'] as num?)?.toInt() ?? 0,
      recipientUserId: (json['recipientUserId'] as num?)?.toInt() ?? 0,
      body: json['body'] as String? ?? '',
      sentAt: json['sentAt'] == null
          ? DateTime.now()
          : DateTime.tryParse(json['sentAt'] as String) ?? DateTime.now(),
      senderName: json['senderName'] as String?,
      recipientName: json['recipientName'] as String?,
    );
  }
}
