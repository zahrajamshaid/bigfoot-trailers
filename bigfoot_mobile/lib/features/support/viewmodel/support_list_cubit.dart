import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../data/support_api.dart';
import '../model/support_ticket.dart';

class SupportListState extends Equatable {
  final bool loading;
  final List<SupportTicketSummary> tickets;
  final String? error;

  const SupportListState({
    this.loading = false,
    this.tickets = const [],
    this.error,
  });

  SupportListState copyWith({
    bool? loading,
    List<SupportTicketSummary>? tickets,
    String? error,
  }) =>
      SupportListState(
        loading: loading ?? this.loading,
        tickets: tickets ?? this.tickets,
        error: error,
      );

  @override
  List<Object?> get props => [loading, tickets, error];
}

class SupportListCubit extends Cubit<SupportListState> {
  final SupportApi _api;
  SupportListCubit(this._api) : super(const SupportListState());

  Future<void> load() async {
    emit(state.copyWith(loading: true, error: null));
    try {
      final tickets = await _api.listTickets();
      emit(SupportListState(loading: false, tickets: tickets));
    } catch (e) {
      emit(SupportListState(loading: false, tickets: state.tickets, error: '$e'));
    }
  }
}
