import '../../data/models/location.dart';

/// Reads trailer yard / factory locations from the API.
///
/// Implementations should cache the list for the duration of the app session
/// since locations rarely change at runtime — pickers can call this
/// repeatedly without spamming the network.
abstract class LocationRepository {
  /// All non-factory active locations (the destinations a stock build or
  /// delivery can be sent to).
  Future<List<Location>> getStockLocations({bool forceRefresh = false});

  /// Every location, including the factory.
  Future<List<Location>> getAllLocations({bool forceRefresh = false});
}
