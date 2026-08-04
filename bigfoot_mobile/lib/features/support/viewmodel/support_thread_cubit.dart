import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../data/support_api.dart';
import '../model/support_ticket.dart';

class SupportThreadState extends Equatable {
  final bool loading;
  final bool sending;
  final SupportTicketDetail? detail;
  final String? error;

  const SupportThreadState({
    this.loading = false,
    this.sending = false,
    this.detail,
    this.error,
  });

  SupportThreadState copyWith({
    bool? loading,
    bool? sending,
    SupportTicketDetail? detail,
    String? error,
  }) =>
      SupportThreadState(
        loading: loading ?? this.loading,
        sending: sending ?? this.sending,
        detail: detail ?? this.detail,
        error: error,
      );

  @override
  List<Object?> get props => [loading, sending, detail, error];
}

class SupportThreadCubit extends Cubit<SupportThreadState> {
  final SupportApi _api;
  final int ticketId;
  SupportThreadCubit(this._api, this.ticketId)
      : super(const SupportThreadState());

  Future<void> load() async {
    emit(state.copyWith(loading: true, error: null));
    try {
      final detail = await _api.getTicket(ticketId);
      emit(SupportThreadState(loading: false, detail: detail));
    } catch (e) {
      emit(SupportThreadState(loading: false, detail: state.detail, error: '$e'));
    }
  }

  Future<bool> reply(String body) async {
    if (body.trim().isEmpty) return false;
    emit(state.copyWith(sending: true, error: null));
    try {
      final detail = await _api.addMessage(ticketId, body.trim());
      emit(SupportThreadState(loading: false, sending: false, detail: detail));
      return true;
    } catch (e) {
      emit(state.copyWith(sending: false, error: '$e'));
      return false;
    }
  }

  Future<void> setResolved(bool resolved) async {
    try {
      final detail = await _api.setResolved(ticketId, resolved);
      emit(SupportThreadState(loading: false, detail: detail));
    } catch (e) {
      emit(state.copyWith(error: '$e'));
    }
  }
}
