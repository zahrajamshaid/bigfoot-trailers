import '../../data/models/user.dart';

/// Auth result containing tokens and parsed user.
class AuthResult {
  final User user;
  final String accessToken;
  final String refreshToken;

  const AuthResult({
    required this.user,
    required this.accessToken,
    required this.refreshToken,
  });
}

/// Abstract contract for authentication operations.
abstract class AuthRepository {
  Future<AuthResult> login(String email, String password);
  Future<AuthResult> refreshTokens(String refreshToken);
  Future<void> logout(String refreshToken);
  Future<void> registerPushToken(String token);
}
