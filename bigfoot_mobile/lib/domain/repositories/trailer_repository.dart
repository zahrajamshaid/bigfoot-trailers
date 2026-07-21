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
    String? saleStatus,
    bool hotOnly = false,
    String? completedSince,
    /// Filter to trailers physically at this location code (e.g. MULBERRY).
    /// ANDs with [intendedStockLocationCode] — together they isolate
    /// "stock at Mulberry destined for Tappahannock" without the broader
    /// locationId OR-match.
    String? currentLocationCode,
    String? intendedStockLocationCode,
    /// true → stock builds only, false → customer orders only, null → both.
    bool? isStockBuild,
    bool? readyForPickupAtMulberry,
  });

  Future<Trailer> getTrailer(int id);

  Future<Trailer> createTrailer(Map<String, dynamic> data);

  Future<Trailer> updateTrailer(int id, Map<String, dynamic> data);

  Future<void> updatePriority(int id, int priority);

  Future<void> toggleHot(int id, bool isHot);

  /// Set the sale status (`available` / `sale_pending` / `sold`).
  /// Marking `sold` requires a buyer — pass [soldToName] unless the trailer
  /// already has a customer. When [fulfilmentType] is provided on a sold
  /// transition, the backend auto-creates a scheduled Delivery (`factory_pickup`
  /// for `pickup`, `single_pull` or `stack_to_dealer` for `delivery`).
  /// Owner / sales / production_manager only.
  Future<Trailer> updateSaleStatus(
    int id,
    String saleStatus, {
    String? soldToName,
    String? fulfilmentType,
    String? deliveryAddress,
  });

  /// Sales-facing terminal completion — closes the open scheduled delivery
  /// and flips the trailer to `delivered`. Idempotent; already-delivered
  /// trailers return without changes.
  Future<Trailer> markCompleted(int id);

  /// Owner / production_manager swap between paint booths. [code] is the
  /// target booth's department code: `PAINT_A` or `PAINT_B`. Rejects
  /// PAINT_A for ≥25ft trailers on the server.
  Future<Trailer> setPaintBooth(int id, String code);

  /// Move the trailer's step-9 department. [code] is `WIRE` or
  /// `HYDRAULICS`. Rejected server-side once that step is complete.
  Future<Trailer> setWireHydraulic(int id, String code);

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
