import '../../core/constants/api_endpoints.dart';
import '../../core/network/dio_client.dart';
import '../../domain/repositories/trailer_repository.dart';
import '../models/trailer.dart';

class TrailerRepositoryImpl implements TrailerRepository {
  final DioClient _api;
  static const _pageSize = 25;

  TrailerRepositoryImpl({required DioClient api}) : _api = api;

  @override
  Future<TrailerListResult> getTrailers({
    int page = 1,
    int limit = 25,
    String? search,
    String? status,
    String? series,
    bool hotOnly = false,
  }) async {
    final params = <String, dynamic>{
      'page': page,
      'limit': limit,
    };
    if (search != null && search.isNotEmpty) params['search'] = search;
    if (status != null) params['status'] = status;
    if (series != null) params['series'] = series;
    if (hotOnly) params['isHot'] = true;

    final response = await _api.get<Map<String, dynamic>>(
      ApiEndpoints.trailers,
      queryParameters: params,
      fromJson: (d) => d as Map<String, dynamic>,
    );

    final envelope = response.data ?? {};
    final rawList = (envelope['trailers'] as List<dynamic>?) ?? [];
    final items = rawList
        .whereType<Map<String, dynamic>>()
        .map(Trailer.fromJson)
        .toList();

    final total = envelope['total'] as int? ?? items.length;
    final currentPage = envelope['page'] as int? ?? page;
    final pageLimit = envelope['limit'] as int? ?? _pageSize;
    final totalPages = (total / pageLimit).ceil();
    final hasMore = currentPage < totalPages;

    return TrailerListResult(items: items, hasMore: hasMore);
  }

  @override
  Future<Trailer> getTrailer(int id) async {
    final response = await _api.get<Map<String, dynamic>>(
      ApiEndpoints.trailer(id),
      fromJson: (d) => d as Map<String, dynamic>,
    );
    return Trailer.fromJson(response.data!);
  }

  @override
  Future<Trailer> createTrailer(Map<String, dynamic> data) async {
    final response = await _api.post<Map<String, dynamic>>(
      ApiEndpoints.trailers,
      data: data,
      fromJson: (d) => d as Map<String, dynamic>,
    );
    return Trailer.fromJson(response.data!);
  }

  @override
  Future<Trailer> updateTrailer(int id, Map<String, dynamic> data) async {
    final response = await _api.patch<Map<String, dynamic>>(
      ApiEndpoints.trailer(id),
      data: data,
      fromJson: (d) => d as Map<String, dynamic>,
    );
    return Trailer.fromJson(response.data!);
  }

  @override
  Future<void> updatePriority(int id, int priority) async {
    await _api.patch(
      ApiEndpoints.trailerPriority(id),
      data: {'globalPriority': priority},
    );
  }

  @override
  Future<void> toggleHot(int id, bool isHot) async {
    await _api.patch(
      ApiEndpoints.trailerHot(id),
      data: {'isHot': isHot},
    );
  }

  @override
  Future<void> addAddon(int trailerId, Map<String, dynamic> data) async {
    await _api.post(ApiEndpoints.trailerAddons(trailerId), data: data);
  }

  @override
  Future<void> removeAddon(int trailerId, int addonId) async {
    await _api.delete(ApiEndpoints.trailerAddon(trailerId, addonId));
  }

  @override
  Future<List<ProductionStepSummary>> getSteps(int trailerId) async {
    final response = await _api.get<List<dynamic>>(
      ApiEndpoints.trailerSteps(trailerId),
      fromJson: (d) => d as List<dynamic>,
    );
    return (response.data ?? [])
        .whereType<Map<String, dynamic>>()
        .map(ProductionStepSummary.fromJson)
        .toList();
  }

  @override
  Future<List<Map<String, dynamic>>> getHistory(int trailerId) async {
    final response = await _api.get<List<dynamic>>(
      ApiEndpoints.trailerHistory(trailerId),
      fromJson: (d) => d as List<dynamic>,
    );
    return (response.data ?? []).whereType<Map<String, dynamic>>().toList();
  }

  @override
  Future<String?> getQbPdfUrl(int trailerId) async {
    final response = await _api.get<Map<String, dynamic>>(
      ApiEndpoints.trailerQbPdf(trailerId),
      fromJson: (d) => d as Map<String, dynamic>,
    );
    return response.data?['downloadUrl'] as String?;
  }

  @override
  Future<void> uploadQbPdf({
    required int trailerId,
    required String storageKey,
    required String storageUrl,
  }) async {
    await _api.post(
      ApiEndpoints.trailerQbPdf(trailerId),
      data: {'storageKey': storageKey, 'storageUrl': storageUrl},
    );
  }
}
