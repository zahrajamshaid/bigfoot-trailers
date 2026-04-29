import 'dart:async';
import 'dart:convert';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/storage/secure_storage.dart';
import '../../../core/websocket/ws_client.dart';
import '../../../data/models/user.dart';
import '../../../domain/repositories/auth_repository.dart';

// ── Auth States ──────────────────────────────────────────────────────────────

sealed class AuthState extends Equatable {
  const AuthState();

  @override
  List<Object?> get props => [];
}

class AuthInitial extends AuthState {
  const AuthInitial();
}

class AuthLoading extends AuthState {
  const AuthLoading();
}

class Authenticated extends AuthState {
  final User user;
  final String accessToken;

  const Authenticated({required this.user, required this.accessToken});

  @override
  List<Object?> get props => [user, accessToken];
}

class Unauthenticated extends AuthState {
  final String? message;
  const Unauthenticated({this.message});

  @override
  List<Object?> get props => [message];
}

// ── Auth ViewModel ──────────────────────────────────────────────────────────

class AuthViewModel extends Cubit<AuthState> {
  static const _authRequestTimeout = Duration(seconds: 15);
  static const _wsConnectTimeout = Duration(seconds: 5);

  final AuthRepository _repository;
  final SecureStorage _storage;
  final WsClient _ws;
  Timer? _refreshTimer;

  AuthViewModel({
    required AuthRepository repository,
    required SecureStorage storage,
    required WsClient ws,
  })  : _repository = repository,
        _storage = storage,
        _ws = ws,
        super(const AuthInitial());

  Future<void> tryRestoreSession() async {
    emit(const AuthLoading());

    try {
      final hasTokens = await _storage
          .hasTokens()
          .timeout(_authRequestTimeout);
      if (!hasTokens) {
        emit(const Unauthenticated());
        return;
      }

      final refreshToken = await _storage
          .getRefreshToken()
          .timeout(_authRequestTimeout);
      if (refreshToken == null) {
        emit(const Unauthenticated());
        return;
      }

      final result = await _repository
          .refreshTokens(refreshToken)
          .timeout(_authRequestTimeout);
      _scheduleTokenRefresh(result.accessToken);
      await _ws.connect().timeout(_wsConnectTimeout);
      emit(Authenticated(user: result.user, accessToken: result.accessToken));
    } on TimeoutException {
      await _storage.clearTokens();
      emit(const Unauthenticated(
        message: 'Request timed out. Please check your server connection.',
      ));
    } catch (_) {
      await _storage.clearTokens();
      emit(const Unauthenticated());
    }
  }

  Future<void> login(String email, String password) async {
    emit(const AuthLoading());

    try {
      final result = await _repository
          .login(email, password)
          .timeout(_authRequestTimeout);
      _scheduleTokenRefresh(result.accessToken);
      await _ws.connect().timeout(_wsConnectTimeout);
      emit(Authenticated(user: result.user, accessToken: result.accessToken));
    } on TimeoutException {
      emit(const Unauthenticated(
        message: 'Request timed out. Please check your server connection.',
      ));
    } on ApiException catch (e) {
      emit(Unauthenticated(message: e.displayMessage));
    } on NetworkException catch (e) {
      emit(Unauthenticated(message: e.message));
    } catch (e) {
      emit(const Unauthenticated(message: 'An unexpected error occurred'));
    }
  }

  Future<void> logout() async {
    _cancelRefreshTimer();
    try {
      final refreshToken = await _storage.getRefreshToken();
      if (refreshToken != null) {
        await _repository.logout(refreshToken);
      }
    } catch (_) {
    } finally {
      await _storage.clearTokens();
      _ws.disconnect();
      emit(const Unauthenticated());
    }
  }

  void onAuthExpired() {
    _cancelRefreshTimer();
    _storage.clearTokens();
    _ws.disconnect();
    emit(const Unauthenticated(
        message: 'Session expired. Please sign in again.'));
  }

  void _scheduleTokenRefresh(String accessToken) {
    _cancelRefreshTimer();

    final expiresIn = _getTokenExpiryDuration(accessToken);
    if (expiresIn == null) return;

    final refreshIn = expiresIn - const Duration(seconds: 60);
    final delay =
        refreshIn.isNegative ? const Duration(seconds: 10) : refreshIn;

    _refreshTimer = Timer(delay, _performSilentRefresh);
  }

  Future<void> _performSilentRefresh() async {
    try {
      final refreshToken = await _storage.getRefreshToken();
      if (refreshToken == null) {
        await _forceLogout(message: 'Session expired');
        return;
      }

      final result = await _repository.refreshTokens(refreshToken);
      _scheduleTokenRefresh(result.accessToken);

      if (state is Authenticated) {
        emit(Authenticated(user: result.user, accessToken: result.accessToken));
      }
    } on ApiException catch (e) {
      if (e.statusCode == 401 || e.statusCode == 403) {
        await _forceLogout(message: 'Session expired — please log in again');
      } else {
        _refreshTimer = Timer(const Duration(seconds: 30), _performSilentRefresh);
      }
    } catch (_) {
      _refreshTimer = Timer(const Duration(seconds: 30), _performSilentRefresh);
    }
  }

  Future<void> _forceLogout({String? message}) async {
    _cancelRefreshTimer();
    await _storage.clearTokens();
    _ws.disconnect();
    emit(Unauthenticated(message: message));
  }

  void _cancelRefreshTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }

  Duration? _getTokenExpiryDuration(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return null;

      final payload = base64Url.normalize(parts[1]);
      final decoded = utf8.decode(base64Url.decode(payload));
      final map = json.decode(decoded) as Map<String, dynamic>;
      final exp = map['exp'] as int?;
      if (exp == null) return null;

      final expiryTime = DateTime.fromMillisecondsSinceEpoch(exp * 1000);
      return expiryTime.difference(DateTime.now());
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> close() {
    _cancelRefreshTimer();
    return super.close();
  }
}
