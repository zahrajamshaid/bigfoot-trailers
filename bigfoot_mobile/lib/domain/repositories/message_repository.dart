import '../../data/models/worker_message.dart';

/// Abstract contract for worker message operations.
abstract class MessageRepository {
  Future<List<WorkerMessage>> getThread(int trailerId);

  Future<WorkerMessage> sendMessage({
    required int trailerId,
    required int recipientUserId,
    required String body,
  });
}
