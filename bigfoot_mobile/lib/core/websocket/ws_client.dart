import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../storage/secure_storage.dart';
import 'ws_event_stream.dart';

enum WsConnectionState { disconnected, connecting, connected }

class WsQueuedAction {
  final String event;
  final Map<String, dynamic> payload;

  const WsQueuedAction({required this.event, required this.payload});

  Map<String, dynamic> toJson() => {'event': event, 'payload': payload};

  factory WsQueuedAction.fromJson(Map<String, dynamic> json) {
    return WsQueuedAction(
      event: json['event']?.toString() ?? '',
      payload: Map<String, dynamic>.from(json['payload'] as Map? ?? const {}),
    );
  }
}

class WsClient {
  static const _queuedActionsKey = 'ws_queued_actions';

  final String url;
  final SecureStorage storage;
  final Duration heartbeatInterval;

  io.Socket? _socket;
  Timer? _heartbeatTimer;
  Timer? _heartbeatWatchdogTimer;
  bool _manualDisconnect = false;
  DateTime _lastHeartbeatAck = DateTime.fromMillisecondsSinceEpoch(0);
  final Set<String> _requestedRooms = {};
  final List<WsQueuedAction> _queuedActions = [];

  final StreamController<WsConnectionState> _connectionStateController =
      StreamController<WsConnectionState>.broadcast();
  final StreamController<WsEvent> _eventsController =
      StreamController<WsEvent>.broadcast();

  WsClient({
    required this.url,
    required this.storage,
    this.heartbeatInterval = const Duration(seconds: 25),
  }) {
    _connectionStateController.add(WsConnectionState.disconnected);
  }

  Stream<WsConnectionState> get connectionState => _connectionStateController.stream;
    WsConnectionState get currentState => _currentState;

  WsConnectionState _currentState = WsConnectionState.disconnected;

  Stream<WsEvent> get events => _eventsController.stream;

  Future<void> connect() async {
    if (_currentState == WsConnectionState.connected ||
        _currentState == WsConnectionState.connecting) {
      return;
    }

    final token = await storage.getAccessToken();
    if (token == null || token.isEmpty) {
      return;
    }

    _manualDisconnect = false;
    _setState(WsConnectionState.connecting);

    final options = io.OptionBuilder()
        .disableAutoConnect()
        .setTransports(['websocket'])
        .enableReconnection()
        .setReconnectionAttempts(10)
        .setReconnectionDelay(1000)
        .setReconnectionDelayMax(10000)
        .setRandomizationFactor(0.5)
        .setAuth({'token': token})
        .build();

    final socket = io.io(url, options);
    _bindSocket(socket);
    _socket = socket;
    socket.connect();
  }

  void disconnect() {
    _manualDisconnect = true;
    _stopHeartbeat();
    _socket?.dispose();
    _socket = null;
    _setState(WsConnectionState.disconnected);
  }

  Future<void> dispose() async {
    disconnect();
    await _connectionStateController.close();
    await _eventsController.close();
  }

  Future<void> subscribeRoom(String room) async {
    _requestedRooms.add(room);
    _emitRoomAction('subscribe', room);
  }

  Future<void> unsubscribeRoom(String room) async {
    _requestedRooms.remove(room);
    _emitRoomAction('unsubscribe', room);
  }

  Future<void> queueAction(String event, Map<String, dynamic> payload) async {
    final action = WsQueuedAction(event: event, payload: payload);
    _queuedActions.add(action);
    await _persistQueuedActions();
    _flushQueuedActions();
  }

  Future<void> sendHeartbeat() async {
    final socket = _socket;
    if (socket == null || !_isConnected) return;
    final sentAt = DateTime.now();
    socket.emit('heartbeat', {'timestamp': sentAt.toIso8601String()});
    _heartbeatWatchdogTimer?.cancel();
    _heartbeatWatchdogTimer = Timer(heartbeatInterval + const Duration(seconds: 10), () {
      if (_lastHeartbeatAck.isBefore(sentAt) && !_manualDisconnect) {
        socket.disconnect();
      }
    });
  }

  bool get _isConnected => _currentState == WsConnectionState.connected && _socket?.connected == true;

  void _bindSocket(io.Socket socket) {
    socket.onConnect((_) {
      _setState(WsConnectionState.connected);
      _startHeartbeat();
      _rejoinRooms();
      _flushQueuedActions();
    });

    socket.onDisconnect((_) {
      _stopHeartbeat();
      if (_manualDisconnect) return;
      _setState(WsConnectionState.disconnected);
    });

    socket.onConnectError((_) {
      if (!_manualDisconnect) {
        _setState(WsConnectionState.disconnected);
      }
    });

    socket.onReconnectAttempt((_) {
      if (!_manualDisconnect) {
        _setState(WsConnectionState.connecting);
      }
    });

    socket.onReconnect((_) {
      if (!_manualDisconnect) {
        _setState(WsConnectionState.connected);
      }
    });

    socket.on('heartbeat_ack', (data) {
      _lastHeartbeatAck = DateTime.now();
    });

    for (final event in WsEventType.all) {
      socket.on(event, (data) {
        if (data is Map<String, dynamic>) {
          _eventsController.add(WsEvent.fromMap(event, data));
        } else if (data is Map) {
          _eventsController.add(WsEvent.fromMap(event, Map<String, dynamic>.from(data)));
        }
      });
    }
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(heartbeatInterval, (_) => sendHeartbeat());
    _lastHeartbeatAck = DateTime.now();
    sendHeartbeat();
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatWatchdogTimer?.cancel();
    _heartbeatTimer = null;
    _heartbeatWatchdogTimer = null;
  }

  void _rejoinRooms() {
    for (final room in _requestedRooms) {
      _socket?.emit('subscribe', {'room': room});
    }
  }

  void _emitRoomAction(String action, String room) {
    final socket = _socket;
    if (socket != null && _isConnected) {
      socket.emit(action, {'room': room});
    }
  }

  Future<void> _flushQueuedActions() async {
    if (!_isConnected) return;
    await _loadQueuedActions();
    if (_queuedActions.isEmpty) return;
    for (final action in List<WsQueuedAction>.from(_queuedActions)) {
      _socket?.emit(action.event, action.payload);
    }
    _queuedActions.clear();
    await _persistQueuedActions();
  }

  Future<void> _loadQueuedActions() async {
    if (_queuedActions.isNotEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_queuedActionsKey) ?? const [];
    _queuedActions
      ..clear()
      ..addAll(
        raw
            .map((item) => jsonDecode(item))
            .whereType<Map>()
            .map((item) => WsQueuedAction.fromJson(Map<String, dynamic>.from(item))),
      );
  }

  Future<void> _persistQueuedActions() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _queuedActionsKey,
      _queuedActions.map((action) => jsonEncode(action.toJson())).toList(),
    );
  }

  void _setState(WsConnectionState state) {
    _currentState = state;
    if (!_connectionStateController.isClosed) {
      _connectionStateController.add(state);
    }
  }
}