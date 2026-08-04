import 'package:equatable/equatable.dart';

DateTime? _parseDate(dynamic v) =>
    v == null ? null : DateTime.tryParse(v.toString())?.toLocal();

/// A ticket row in the list view.
class SupportTicketSummary extends Equatable {
  final int id;
  final String subject;
  final String status; // 'open' | 'resolved'
  final DateTime? updatedAt;
  final String reporterName;
  final int messageCount;
  final String? lastPreview;
  final bool lastFromReporter;

  const SupportTicketSummary({
    required this.id,
    required this.subject,
    required this.status,
    required this.updatedAt,
    required this.reporterName,
    required this.messageCount,
    required this.lastPreview,
    required this.lastFromReporter,
  });

  bool get isOpen => status == 'open';

  factory SupportTicketSummary.fromJson(Map<String, dynamic> j) {
    final last = j['lastMessage'] as Map<String, dynamic>?;
    return SupportTicketSummary(
      id: int.tryParse('${j['id']}') ?? 0,
      subject: j['subject'] as String? ?? '',
      status: j['status'] as String? ?? 'open',
      updatedAt: _parseDate(j['updatedAt']),
      reporterName: j['reporterName'] as String? ?? '',
      messageCount: (j['messageCount'] as num?)?.toInt() ?? 0,
      lastPreview: last?['preview'] as String?,
      lastFromReporter: last?['fromReporter'] as bool? ?? true,
    );
  }

  @override
  List<Object?> get props => [id, status, updatedAt, messageCount];
}

/// One message in a thread.
class SupportMessage extends Equatable {
  final int id;
  final String body;
  final DateTime? at;
  final int senderId;
  final String senderName;
  final bool fromReporter;

  const SupportMessage({
    required this.id,
    required this.body,
    required this.at,
    required this.senderId,
    required this.senderName,
    required this.fromReporter,
  });

  factory SupportMessage.fromJson(Map<String, dynamic> j) => SupportMessage(
        id: int.tryParse('${j['id']}') ?? 0,
        body: j['body'] as String? ?? '',
        at: _parseDate(j['at']),
        senderId: int.tryParse('${j['senderId']}') ?? 0,
        senderName: j['senderName'] as String? ?? '',
        fromReporter: j['fromReporter'] as bool? ?? false,
      );

  @override
  List<Object?> get props => [id, body, senderId];
}

/// A ticket with its full thread.
class SupportTicketDetail extends Equatable {
  final int id;
  final String subject;
  final String status;
  final int reporterId;
  final String reporterName;
  final List<SupportMessage> messages;

  const SupportTicketDetail({
    required this.id,
    required this.subject,
    required this.status,
    required this.reporterId,
    required this.reporterName,
    required this.messages,
  });

  bool get isOpen => status == 'open';

  factory SupportTicketDetail.fromJson(Map<String, dynamic> j) =>
      SupportTicketDetail(
        id: int.tryParse('${j['id']}') ?? 0,
        subject: j['subject'] as String? ?? '',
        status: j['status'] as String? ?? 'open',
        reporterId: int.tryParse('${j['reporterId']}') ?? 0,
        reporterName: j['reporterName'] as String? ?? '',
        messages: ((j['messages'] as List<dynamic>?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(SupportMessage.fromJson)
            .toList(),
      );

  @override
  List<Object?> get props => [id, status, messages];
}
