import '../../data/models/trailer.dart';

/// Abstract contract for trailer data operations.
abstract class TrailerRepository {
  Future<TrailerListResult> getTrailers({
    int page = 1,
    int limit = 25,
    String? search,
    String? status,
    String? series,
    int? locationId,
    bool hotOnly = false,
  });

  Future<Trailer> getTrailer(int id);

  Future<Trailer> createTrailer(Map<String, dynamic> data);

  Future<Trailer> updateTrailer(int id, Map<String, dynamic> data);

  Future<void> updatePriority(int id, int priority);

  Future<void> toggleHot(int id, bool isHot);

  Future<void> addAddon(int trailerId, Map<String, dynamic> data);

  Future<void> removeAddon(int trailerId, int addonId);

  Future<List<ProductionStepSummary>> getSteps(int trailerId);

  Future<Map<String, dynamic>> getHistory(int trailerId);

  Future<String?> getQbPdfUrl(int trailerId);

  Future<void> uploadQbPdf({
    required int trailerId,
    required String storageKey,
    required String storageUrl,
  });

  /// Permanently delete a trailer and all related records.
  /// Owner role only — backend rejects 403 otherwise.
  Future<void> deleteTrailer(int id);
}

class TrailerListResult {
  final List<Trailer> items;
  final bool hasMore;
  final bool fromCache;
  final DateTime? lastUpdated;

  const TrailerListResult({
    required this.items,
    required this.hasMore,
    this.fromCache = false,
    this.lastUpdated,
  });
}
