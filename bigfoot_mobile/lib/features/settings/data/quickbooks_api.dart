import '../../../core/constants/api_endpoints.dart';
import '../../../core/network/dio_client.dart';

/// Connection status for the QuickBooks section in Settings.
class QboStatus {
  final bool enabled;
  final bool connected;
  final String? companyName;
  final String environment; // 'sandbox' | 'production'
  final String? realmId;

  const QboStatus({
    required this.enabled,
    required this.connected,
    required this.environment,
    this.companyName,
    this.realmId,
  });

  /// True when we're pointed at a real QuickBooks company (not the test one).
  bool get isProduction => environment == 'production';

  factory QboStatus.fromJson(Map<String, dynamic> j) => QboStatus(
        enabled: j['enabled'] as bool? ?? false,
        connected: j['connected'] as bool? ?? false,
        companyName: j['companyName'] as String?,
        environment: j['environment'] as String? ?? 'sandbox',
        realmId: j['realmId'] as String?,
      );
}

/// Connect / disconnect / status for QuickBooks Online.
class QuickBooksApi {
  QuickBooksApi(this._api);
  final DioClient _api;

  Future<QboStatus> status() async {
    final res = await _api.get<Map<String, dynamic>>(
      ApiEndpoints.quickbooksHealth,
      fromJson: (d) => d as Map<String, dynamic>,
    );
    return QboStatus.fromJson(res.data ?? const {});
  }

  /// The Intuit consent URL. Open it in a browser — the user signs in to the
  /// QuickBooks company there, and Intuit redirects back to our callback.
  Future<String> authorizationUrl() async {
    final res = await _api.get<Map<String, dynamic>>(
      ApiEndpoints.quickbooksConnect,
      fromJson: (d) => d as Map<String, dynamic>,
    );
    return (res.data ?? const {})['authorizationUrl'] as String? ?? '';
  }

  Future<void> disconnect() async {
    await _api.post<Map<String, dynamic>>(
      ApiEndpoints.quickbooksDisconnect,
      data: const {},
      fromJson: (d) => d as Map<String, dynamic>,
    );
  }
}
