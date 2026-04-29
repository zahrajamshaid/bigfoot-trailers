import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/models/worker_message.dart';
import '../../../domain/repositories/message_repository.dart';

class MessagesViewModel extends Cubit<int> {
  final MessageRepository _repository;

  MessagesViewModel({required MessageRepository repository})
      : _repository = repository,
        super(0);

  Future<List<WorkerMessage>> getThread(int trailerId) =>
      _repository.getThread(trailerId);

  Future<WorkerMessage> sendMessage({
    required int trailerId,
    required int recipientUserId,
    required String body,
  }) => _repository.sendMessage(
    trailerId: trailerId,
    recipientUserId: recipientUserId,
    body: body,
  );
}
