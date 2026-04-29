import '../../core/constants/api_endpoints.dart';
import '../../core/network/dio_client.dart';
import '../../domain/repositories/message_repository.dart';
import '../models/worker_message.dart';

class MessageRepositoryImpl implements MessageRepository {
  final DioClient _api;

  MessageRepositoryImpl({required DioClient api}) : _api = api;

  @override
  Future<List<WorkerMessage>> getThread(int trailerId) async {
    final response = await _api.get<Map<String, dynamic>>(
      ApiEndpoints.messages,
      queryParameters: {'trailerId': trailerId, 'limit': 200},
      fromJson: (d) => d as Map<String, dynamic>,
    );

    final data = response.data ?? <String, dynamic>{};
    return ((data['items'] as List<dynamic>?) ??
            (data['messages'] as List<dynamic>?) ??
            const [])
        .whereType<Map<String, dynamic>>()
        .map(WorkerMessage.fromJson)
        .toList();
  }

  @override
  Future<WorkerMessage> sendMessage({
    required int trailerId,
    required int recipientUserId,
    required String body,
  }) async {
    final response = await _api.post<Map<String, dynamic>>(
      ApiEndpoints.messages,
      data: {
        'trailerId': trailerId,
        'recipientUserId': recipientUserId,
        'body': body,
      },
      fromJson: (d) => d as Map<String, dynamic>,
    );

    return WorkerMessage.fromJson(response.data ?? <String, dynamic>{});
  }
}
