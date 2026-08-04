import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/constants/api_endpoints.dart';
import '../../../core/network/dio_client.dart';
import '../model/jig_queue.dart';

class JigQueuesState extends Equatable {
  final bool loading;
  final JigQueueBoard? board;
  final String? error;

  const JigQueuesState({this.loading = false, this.board, this.error});

  JigQueuesState copyWith({bool? loading, JigQueueBoard? board, String? error}) =>
      JigQueuesState(
        loading: loading ?? this.loading,
        board: board ?? this.board,
        // error is intentionally reset unless explicitly passed.
        error: error,
      );

  @override
  List<Object?> get props => [loading, board, error];
}

/// Fetches the jig-queue board (GET /production/jig-queues). Used by both the
/// dashboard low-queue banner and the dedicated Jig Queues screen.
class JigQueuesCubit extends Cubit<JigQueuesState> {
  final DioClient _api;

  JigQueuesCubit({required DioClient api})
      : _api = api,
        super(const JigQueuesState());

  Future<void> load() async {
    emit(state.copyWith(loading: true, board: state.board));
    try {
      final resp = await _api.get<Map<String, dynamic>>(
        ApiEndpoints.productionJigQueues,
        fromJson: (d) => d as Map<String, dynamic>,
      );
      final board = JigQueueBoard.fromJson(resp.data ?? const <String, dynamic>{});
      emit(JigQueuesState(loading: false, board: board));
    } catch (e) {
      emit(JigQueuesState(loading: false, board: state.board, error: '$e'));
    }
  }
}
