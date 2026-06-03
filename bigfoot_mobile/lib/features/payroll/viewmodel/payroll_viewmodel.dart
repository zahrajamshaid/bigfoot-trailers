import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/websocket/ws_client.dart';
import '../../../core/websocket/ws_events.dart';
import '../../../data/models/payroll_record.dart';
import '../../../domain/repositories/payroll_repository.dart';

sealed class PayrollState extends Equatable {
  const PayrollState();

  @override
  List<Object?> get props => [];
}

class PayrollInitial extends PayrollState {
  const PayrollInitial();
}

class PayrollLoading extends PayrollState {
  const PayrollLoading();
}

class PayrollLoaded extends PayrollState {
  final WorkerSummary summary;
  final List<PayrollRecord> history;
  final List<double> dailyPoints;
  final bool historyUnavailable;

  const PayrollLoaded({
    required this.summary,
    required this.history,
    required this.dailyPoints,
    this.historyUnavailable = false,
  });

  @override
  List<Object?> get props => [summary, history, dailyPoints, historyUnavailable];
}

class PayrollError extends PayrollState {
  final String message;

  const PayrollError(this.message);

  @override
  List<Object?> get props => [message];
}

class PayrollViewModel extends Cubit<PayrollState> {
  final PayrollRepository _repository;
  final WsClient _ws;
  StreamSubscription<WsEvent>? _wsSub;
  int? _activeWorkerUserId;

  PayrollViewModel({required PayrollRepository repository, required WsClient ws})
      : _repository = repository,
        _ws = ws,
        super(const PayrollInitial()) {
    _wsSub = _ws.events.listen(_onWsEvent);
  }

  Future<void> loadWorkerSummary(int userId) async {
    _activeWorkerUserId = userId;
    emit(const PayrollLoading());

    try {
      final summary = await _repository.getWorkerSummary(userId);

      List<PayrollRecord> history = const [];
      bool historyUnavailable = false;
      try {
        history = await _repository.getRecords(userId: userId);
      } catch (_) {
        historyUnavailable = true;
      }

      final daily = _estimatedDailyPoints(summary);

      emit(PayrollLoaded(
        summary: summary,
        history: history,
        dailyPoints: daily,
        historyUnavailable: historyUnavailable,
      ));
    } on ApiException catch (e) {
      emit(PayrollError(e.displayMessage));
    } on NetworkException catch (e) {
      emit(PayrollError(e.message));
    } catch (e) {
      emit(PayrollError('Failed to load payroll summary: $e'));
    }
  }

  Future<WeeklyPayrollReport> getWeeklyReport(String weekStart) =>
      _repository.getWeeklyReport(weekStart);

  Future<PayrollLockResult> lockWeek(String weekStart) =>
      _repository.lockWeek(weekStart);

  Future<List<PointValue>> getPointValues() => _repository.getPointValues();

  Future<PointValue> createPointValue({
    required int trailerModelId,
    required int departmentId,
    required double points,
    required DateTime effectiveFrom,
  }) => _repository.createPointValue(
    trailerModelId: trailerModelId,
    departmentId: departmentId,
    points: points,
    effectiveFrom: effectiveFrom,
  );

  Future<PointValue> updatePointValue({
    required int id,
    double? points,
    DateTime? effectiveTo,
  }) => _repository.updatePointValue(id: id, points: points, effectiveTo: effectiveTo);

  Future<List<DollarRate>> getDollarRates() => _repository.getDollarRates();

  Future<DollarRate> createDollarRate({
    required int departmentId,
    required double dollarPerPoint,
    required DateTime effectiveFrom,
  }) => _repository.createDollarRate(
    departmentId: departmentId,
    dollarPerPoint: dollarPerPoint,
    effectiveFrom: effectiveFrom,
  );

  Future<void> deleteDollarRate(int id) => _repository.deleteDollarRate(id);

  DateTime weekStartSunday(DateTime date) {
    final utc = DateTime.utc(date.year, date.month, date.day);
    final day = utc.weekday % 7;
    return utc.subtract(Duration(days: day));
  }

  void _onWsEvent(WsEvent event) {
    if (event.type == WsEventType.pointsUpdated && _activeWorkerUserId != null) {
      loadWorkerSummary(_activeWorkerUserId!);
    }
  }

  List<double> _estimatedDailyPoints(WorkerSummary summary) {
    final now = DateTime.now().toUtc();
    final sunday = weekStartSunday(now);
    final elapsed = now.difference(sunday).inDays + 1;
    final safeDays = elapsed.clamp(1, 7);
    final perDay = safeDays == 0 ? 0.0 : summary.totalPoints / safeDays;

    return List<double>.generate(7, (i) {
      if (i < safeDays) return perDay;
      return 0;
    });
  }

  @override
  Future<void> close() {
    _wsSub?.cancel();
    return super.close();
  }
}
