import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/websocket/ws_client.dart';
import '../../../core/websocket/ws_events.dart';
import '../../../data/models/app_notification.dart';
import '../../../domain/repositories/notification_repository.dart';
import '../../../services/push_notification_service.dart';

class NotificationsState extends Equatable {
  final List<AppNotification> items;
  final String? bannerId;

  const NotificationsState({
    this.items = const [],
    this.bannerId,
  });

  int get unreadCount => items.where((n) => !n.isRead).length;

  @override
  List<Object?> get props => [items, bannerId];

  NotificationsState copyWith({
    List<AppNotification>? items,
    String? bannerId,
  }) {
    return NotificationsState(
      items: items ?? this.items,
      bannerId: bannerId,
    );
  }
}

class NotificationsViewModel extends Cubit<NotificationsState> {
  final NotificationRepository _repository;
  final WsClient _ws;
  final PushNotificationService _pushService;
  StreamSubscription<WsEvent>? _wsSub;
  bool _initialized = false;

  NotificationsViewModel({
    required NotificationRepository repository,
    required WsClient ws,
    required PushNotificationService pushService,
  })  : _repository = repository,
        _ws = ws,
        _pushService = pushService,
        super(const NotificationsState()) {
    _subscribeWs();
  }

  Future<void> initializePush({
    required Future<void> Function(Map<String, dynamic> payload) onOpenPayload,
  }) async {
    if (_initialized) return;
    _initialized = true;

    await _pushService.initialize(
      onForeground: (payload) async {
        final notification = AppNotification(
          id: 'fcm-${DateTime.now().millisecondsSinceEpoch}',
          type: payload.type ?? NotificationType.workerMessage,
          title: payload.title ?? 'Notification',
          body: payload.body ?? '',
          timestamp: DateTime.now(),
          payload: payload.data,
        );
        _insertNotification(notification, showBanner: true);
      },
      onOpened: (payload) async {
        await onOpenPayload(payload.data);
      },
    );
  }

  Future<void> registerPushToken() async {
    try {
      final token = await _pushService.getToken();
      if (token == null || token.isEmpty) return;
      await _repository.registerPushToken(token);
    } catch (e, stack) {
      // Push registration failures shouldn't block the app, but must surface
      // to logs so missing notifications can be diagnosed.
      Zone.current.handleUncaughtError(e, stack);
    }
  }

  Future<void> loadHistory() async {
    try {
      final items = await _repository.getHistory();
      emit(state.copyWith(items: items));
    } catch (_) {
      emit(state.copyWith(items: const []));
    }
  }

  void markRead(String id) {
    final updated = state.items
        .map((n) => n.id == id ? n.copyWith(isRead: true) : n)
        .toList();
    emit(state.copyWith(items: updated));
  }

  void markAllRead() {
    final updated = state.items.map((n) => n.copyWith(isRead: true)).toList();
    emit(state.copyWith(items: updated));
  }

  void dismiss(String id) {
    final updated = state.items.where((n) => n.id != id).toList();
    emit(state.copyWith(items: updated));
  }

  void clearBanner(String id) {
    if (state.bannerId == id) {
      emit(state.copyWith(bannerId: null));
    }
  }

  void _subscribeWs() {
    _wsSub?.cancel();
    _wsSub = _ws.events.listen((event) {
      final mapped = _fromWsEvent(event);
      if (mapped != null) {
        _insertNotification(mapped, showBanner: false);
      }
    });
  }

  AppNotification? _fromWsEvent(WsEvent event) {
    switch (event.type) {
      case WsEventType.qcFail:
        return AppNotification(
          id: 'ws-${DateTime.now().microsecondsSinceEpoch}',
          type: NotificationType.qcFail,
          title: 'QC Failed',
          body: event.data['fail_notes']?.toString() ?? 'QC checkpoint failed',
          timestamp: event.timestamp,
          payload: event.data,
        );
      case WsEventType.trailerStalled:
        return AppNotification(
          id: 'ws-${DateTime.now().microsecondsSinceEpoch}',
          type: NotificationType.trailerStalled,
          title: 'Trailer Stalled',
          body: 'A trailer exceeded department stall threshold.',
          timestamp: event.timestamp,
          payload: event.data,
        );
      case WsEventType.deliveryDispatched:
        return AppNotification(
          id: 'ws-${DateTime.now().microsecondsSinceEpoch}',
          type: NotificationType.deliveryDispatched,
          title: 'Delivery Dispatched',
          body: 'A delivery has been marked en route.',
          timestamp: event.timestamp,
          payload: event.data,
        );
      case WsEventType.deliveryComplete:
        return AppNotification(
          id: 'ws-${DateTime.now().microsecondsSinceEpoch}',
          type: NotificationType.deliveryComplete,
          title: 'Delivery Complete',
          body: 'A delivery has been completed.',
          timestamp: event.timestamp,
          payload: event.data,
        );
      case WsEventType.workerMessage:
        return AppNotification(
          id: 'ws-${DateTime.now().microsecondsSinceEpoch}',
          type: NotificationType.workerMessage,
          title: 'Worker Message',
          body: event.data['message']?.toString() ?? 'New worker message',
          timestamp: event.timestamp,
          payload: event.data,
        );
      default:
        return null;
    }
  }

  void _insertNotification(AppNotification item, {required bool showBanner}) {
    final updated = [item, ...state.items];
    emit(state.copyWith(items: updated, bannerId: showBanner ? item.id : null));
  }

  @override
  Future<void> close() async {
    await _wsSub?.cancel();
    await _pushService.dispose();
    return super.close();
  }
}
