import 'dart:convert';

import '../../core/constants/api_endpoints.dart';
import '../../core/network/api_exception.dart';
import '../../core/network/dio_client.dart';
import '../../domain/repositories/trailer_repository.dart';
import '../models/trailer.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TrailerRepositoryImpl implements TrailerRepository {
  final DioClient _api;
  static const _pageSize = 25;
  static const _listCachePrefix = 'trailers_list_cache_';
  static const _listCacheTsPrefix = 'trailers_list_cache_ts_';
  static const _detailCachePrefix = 'trailers_detail_cache_';
  static const _detailCacheTsPrefix = 'trailers_detail_cache_ts_';

  TrailerRepositoryImpl({required DioClient api}) : _api = api;

  @override
  Future<TrailerListResult> getTrailers({
    int page = 1,
    int limit = 25,
    String? search,
    String? status,
    String? series,
    int? locationId,
    String? saleStatus,
    bool hotOnly = false,
  }) async {
    final params = <String, dynamic>{
      'page': page,
      'limit': limit,
    };
    if (search != null && search.isNotEmpty) params['search'] = search;
    if (status != null) params['status'] = status;
    if (series != null) params['series'] = series;
    if (locationId != null) params['locationId'] = locationId;
    if (saleStatus != null) params['saleStatus'] = saleStatus;
    if (hotOnly) params['isHot'] = true;

    final cacheKey = _listCacheKey(params);
    try {
      final response = await _api.get<Map<String, dynamic>>(
        ApiEndpoints.trailers,
        queryParameters: params,
        fromJson: (d) => d as Map<String, dynamic>,
      );

      final envelope = response.data ?? {};
      await _saveJsonCache(_listCachePrefix + cacheKey, envelope);
      await _saveTimestamp(_listCacheTsPrefix + cacheKey, DateTime.now());

      return _parseTrailerListResult(envelope, page: page, fromCache: false);
    } on NetworkException {
      final cached = await _readJsonCache(_listCachePrefix + cacheKey);
      if (cached == null) rethrow;
      final lastUpdated = await _readTimestamp(_listCacheTsPrefix + cacheKey);
      return _parseTrailerListResult(
        cached,
        page: page,
        fromCache: true,
        lastUpdated: lastUpdated,
      );
    }
  }

  @override
  Future<Trailer> getTrailer(int id) async {
    try {
      final response = await _api.get<Map<String, dynamic>>(
        ApiEndpoints.trailer(id),
        fromJson: (d) => d as Map<String, dynamic>,
      );
      final payload = response.data!;
      await _saveJsonCache('$_detailCachePrefix$id', payload);
      await _saveTimestamp('$_detailCacheTsPrefix$id', DateTime.now());
      return Trailer.fromJson(payload);
    } on NetworkException {
      final cached = await _readJsonCache('$_detailCachePrefix$id');
      if (cached == null) rethrow;
      return Trailer.fromJson(cached);
    }
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
  Future<Trailer> updateSaleStatus(
    int id,
    String saleStatus, {
    String? soldToName,
  }) async {
    final response = await _api.patch<Map<String, dynamic>>(
      ApiEndpoints.trailerSaleStatus(id),
      data: {
        'saleStatus': saleStatus,
        if (soldToName != null) 'soldToName': soldToName,
      },
      fromJson: (d) => d as Map<String, dynamic>,
    );
    return Trailer.fromJson(response.data!);
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
  Future<Map<String, dynamic>> getHistory(int trailerId) async {
    final response = await _api.get<Map<String, dynamic>>(
      ApiEndpoints.trailerHistory(trailerId),
      fromJson: (d) => d as Map<String, dynamic>,
    );
    return response.data ?? <String, dynamic>{};
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

  @override
  Future<void> deleteTrailer(int id) async {
    await _api.delete(ApiEndpoints.trailer(id));
  }

  TrailerListResult _parseTrailerListResult(
    Map<String, dynamic> envelope, {
    required int page,
    required bool fromCache,
    DateTime? lastUpdated,
  }) {
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

    return TrailerListResult(
      items: items,
      hasMore: hasMore,
      fromCache: fromCache,
      lastUpdated: lastUpdated,
    );
  }

  String _listCacheKey(Map<String, dynamic> params) {
    final entries = params.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
    return entries.map((e) => '${e.key}=${e.value}').join('&');
  }

  Future<void> _saveJsonCache(String key, Map<String, dynamic> value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, jsonEncode(value));
  }

  Future<Map<String, dynamic>?> _readJsonCache(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) return null;
    try {
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveTimestamp(String key, DateTime value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, value.toIso8601String());
  }

  Future<DateTime?> _readTimestamp(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }
}
