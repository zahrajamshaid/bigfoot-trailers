import '../../core/constants/api_endpoints.dart';
import '../../core/network/dio_client.dart';
import '../../domain/repositories/location_repository.dart';
import '../models/location.dart';

class LocationRepositoryImpl implements LocationRepository {
  final DioClient _api;
  List<Location>? _allCache;
  List<Location>? _stockCache;

  LocationRepositoryImpl({required DioClient api}) : _api = api;

  @override
  Future<List<Location>> getStockLocations({bool forceRefresh = false}) async {
    if (!forceRefresh && _stockCache != null) return _stockCache!;
    final response = await _api.get<List<dynamic>>(
      ApiEndpoints.locations,
      queryParameters: const {'stockOnly': true},
      fromJson: (d) => d as List<dynamic>,
    );
    final items = (response.data ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(Location.fromJson)
        .toList();
    _stockCache = items;
    return items;
  }

  @override
  Future<List<Location>> getAllLocations({bool forceRefresh = false}) async {
    if (!forceRefresh && _allCache != null) return _allCache!;
    final response = await _api.get<List<dynamic>>(
      ApiEndpoints.locations,
      // activeOnly=true keeps the factory (so trailer-list filters can show
      // Mul) while excluding decommissioned yards.
      queryParameters: const {'activeOnly': true},
      fromJson: (d) => d as List<dynamic>,
    );
    final items = (response.data ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(Location.fromJson)
        .toList();
    _allCache = items;
    return items;
  }
}
