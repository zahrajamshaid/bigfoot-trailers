import '../../../core/constants/api_endpoints.dart';
import '../../../core/network/dio_client.dart';
import '../model/support_ticket.dart';

/// Thin API client for the support / problem-report endpoints.
class SupportApi {
  final DioClient _api;
  SupportApi(this._api);

  Future<SupportTicketDetail> createTicket({
    required String subject,
    required String body,
  }) async {
    final resp = await _api.post<Map<String, dynamic>>(
      ApiEndpoints.supportTickets,
      data: {'subject': subject, 'body': body},
      fromJson: (d) => d as Map<String, dynamic>,
    );
    return SupportTicketDetail.fromJson(resp.data ?? const {});
  }

  Future<List<SupportTicketSummary>> listTickets() async {
    final resp = await _api.get<Map<String, dynamic>>(
      ApiEndpoints.supportTickets,
      fromJson: (d) => d as Map<String, dynamic>,
    );
    final list = (resp.data?['tickets'] as List<dynamic>?) ?? const [];
    return list
        .whereType<Map<String, dynamic>>()
        .map(SupportTicketSummary.fromJson)
        .toList();
  }

  Future<SupportTicketDetail> getTicket(int id) async {
    final resp = await _api.get<Map<String, dynamic>>(
      ApiEndpoints.supportTicket(id),
      fromJson: (d) => d as Map<String, dynamic>,
    );
    return SupportTicketDetail.fromJson(resp.data ?? const {});
  }

  Future<SupportTicketDetail> addMessage(int id, String body) async {
    final resp = await _api.post<Map<String, dynamic>>(
      ApiEndpoints.supportTicketMessages(id),
      data: {'body': body},
      fromJson: (d) => d as Map<String, dynamic>,
    );
    return SupportTicketDetail.fromJson(resp.data ?? const {});
  }

  Future<SupportTicketDetail> setResolved(int id, bool resolved) async {
    final resp = await _api.patch<Map<String, dynamic>>(
      resolved
          ? ApiEndpoints.supportTicketResolve(id)
          : ApiEndpoints.supportTicketReopen(id),
      fromJson: (d) => d as Map<String, dynamic>,
    );
    return SupportTicketDetail.fromJson(resp.data ?? const {});
  }

  Future<int> openCount() async {
    try {
      final resp = await _api.get<Map<String, dynamic>>(
        ApiEndpoints.supportOpenCount,
        fromJson: (d) => d as Map<String, dynamic>,
      );
      return (resp.data?['count'] as num?)?.toInt() ?? 0;
    } catch (_) {
      return 0;
    }
  }
}
