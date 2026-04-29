import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants/api_endpoints.dart';
import '../../core/network/dio_client.dart';
import '../../domain/repositories/storage_repository.dart';
import '../models/storage_upload.dart';

class StorageRepositoryImpl implements StorageRepository {
  static const _cachePrefix = 'storage_download_cache_';
  static const _queueFileName = 'storage_upload_queue.json';
  static const _cacheTtl = Duration(minutes: 15);

  final DioClient _api;
  final Connectivity _connectivity;
  final Uuid _uuid = const Uuid();
  final Map<String, DownloadUrlCacheEntry> _downloadCache = {};
  final StreamController<int> _pendingCountController =
      StreamController<int>.broadcast();
  final StreamController<StorageUploadEvent> _eventsController =
      StreamController<StorageUploadEvent>.broadcast();

  List<QueuedUpload> _queue = const [];
  bool _initialized = false;
  bool _processingQueue = false;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  StorageRepositoryImpl({required DioClient api, Connectivity? connectivity})
    : _api = api,
      _connectivity = connectivity ?? Connectivity() {
    _bootstrap();
  }

  @override
  Stream<int> get pendingCountStream => _pendingCountController.stream;
  @override
  Stream<StorageUploadEvent> get events => _eventsController.stream;
  @override
  int get pendingCount => _queue.length;

  @override
  Future<StorageUploadResult> uploadFile({
    required String fileType,
    required int trailerId,
    required String fileName,
    required List<int> bytes,
    String contentType = 'image/jpeg',
    CapturedPhotoMetadata? metadata,
  }) async {
    await _bootstrap();
    final captureMetadata =
        metadata ?? CapturedPhotoMetadata(capturedAt: DateTime.now().toUtc());

    try {
      final presign = await _requestPresign(
        fileType: fileType,
        trailerId: trailerId,
        fileName: fileName,
        contentType: contentType,
        metadata: captureMetadata,
      );
      await _putBytes(presign.uploadUrl, bytes, contentType);
      return StorageUploadResult.uploaded(presign.storageKey);
    } catch (e) {
      if (kIsWeb) rethrow;
      if (!_isNetworkish(e)) rethrow;
      final queued = await _enqueueUpload(
        fileType: fileType,
        trailerId: trailerId,
        fileName: fileName,
        bytes: bytes,
        contentType: contentType,
        metadata: captureMetadata,
      );
      return StorageUploadResult.queued(queued.localId);
    }
  }

  @override
  Future<String> getDownloadUrl(String storageKey) async {
    await _bootstrap();
    final cached = _downloadCache[storageKey];
    if (cached != null && cached.isValid) return cached.url;

    final prefs = await SharedPreferences.getInstance();
    final cacheRaw = prefs.getString('$_cachePrefix$storageKey');
    if (cacheRaw != null) {
      try {
        final json = jsonDecode(cacheRaw) as Map<String, dynamic>;
        final entry = DownloadUrlCacheEntry(
          url: json['url'] as String,
          expiresAt:
              DateTime.tryParse(json['expiresAt'] as String? ?? '') ??
              DateTime.now(),
        );
        if (entry.isValid) {
          _downloadCache[storageKey] = entry;
          return entry.url;
        }
      } catch (_) {}
    }

    final response = await _api.get<Map<String, dynamic>>(
      ApiEndpoints.storagePresignKey(Uri.encodeComponent(storageKey)),
      fromJson: (d) => d as Map<String, dynamic>,
    );
    final data = response.data ?? <String, dynamic>{};
    final downloadUrl = (data['downloadUrl'] ?? data['download_url']) as String;
    final entry = DownloadUrlCacheEntry(
      url: downloadUrl,
      expiresAt: DateTime.now().add(_cacheTtl),
    );
    _downloadCache[storageKey] = entry;
    await prefs.setString(
      '$_cachePrefix$storageKey',
      jsonEncode({
        'url': downloadUrl,
        'expiresAt': entry.expiresAt.toIso8601String(),
      }),
    );
    return downloadUrl;
  }

  @override
  Future<File> downloadToTempFile(String storageKey, {String? fileName}) async {
    if (kIsWeb) {
      throw UnsupportedError(
        'Temporary file downloads are not supported on web.',
      );
    }
    final url = await getDownloadUrl(storageKey);
    final dir = await getTemporaryDirectory();
    final output = File(
      p.join(dir.path, fileName ?? storageKey.replaceAll('/', '_')),
    );
    await _api.dio.download(url, output.path);
    return output;
  }

  @override
  Future<void> retryPendingUploads() async {
    await _bootstrap();
    if (kIsWeb) return;
    if (_processingQueue || _queue.isEmpty) return;

    _processingQueue = true;
    try {
      final currentQueue = List<QueuedUpload>.from(_queue);
      for (final item in currentQueue) {
        try {
          final file = File(item.filePath);
          if (!await file.exists()) {
            await _removeFromQueue(item.localId);
            continue;
          }
          final bytes = await file.readAsBytes();
          final presign = await _requestPresign(
            fileType: item.fileType,
            trailerId: item.trailerId,
            fileName: item.fileName,
            contentType: item.contentType,
            metadata: item.metadata,
          );
          await _putBytes(presign.uploadUrl, bytes, item.contentType);
          await _removeFromQueue(item.localId);
          if (await file.exists()) {
            await file.delete();
          }
          _eventsController.add(
            StorageUploadEvent(
              localId: item.localId,
              storageKey: presign.storageKey,
            ),
          );
        } catch (_) {
          // Leave item queued for the next connectivity change.
        }
      }
    } finally {
      _processingQueue = false;
      _emitCount();
    }
  }

  @override
  Future<void> clearQueue() async {
    await _bootstrap();
    if (kIsWeb) {
      _queue = const [];
      _emitCount();
      return;
    }
    for (final item in _queue) {
      final file = File(item.filePath);
      if (await file.exists()) {
        await file.delete();
      }
    }
    _queue = const [];
    await _persistQueue();
    _emitCount();
  }

  @override
  Future<void> removeQueuedUpload(String localId) async {
    if (kIsWeb) return;
    await _removeFromQueue(localId);
    _emitCount();
  }

  Future<void> _bootstrap() async {
    if (_initialized) return;
    _initialized = true;
    if (kIsWeb) {
      _queue = const [];
      _emitCount();
      return;
    }
    await _loadQueue();
    _emitCount();
    _connectivitySub = _connectivity.onConnectivityChanged.listen((result) {
      if (result.isNotEmpty && !result.contains(ConnectivityResult.none)) {
        retryPendingUploads();
      }
    });
    final result = await _connectivity.checkConnectivity();
    if (result.isNotEmpty && !result.contains(ConnectivityResult.none)) {
      unawaited(retryPendingUploads());
    }
  }

  Future<_PresignResult> _requestPresign({
    required String fileType,
    required int trailerId,
    required String fileName,
    required String contentType,
    required CapturedPhotoMetadata metadata,
  }) async {
    final response = await _api.post<Map<String, dynamic>>(
      ApiEndpoints.storagePresign,
      data: {
        'fileType': fileType,
        'trailerId': trailerId,
        'fileName': fileName,
        'contentType': contentType,
        'metadata': metadata.toJson(),
      },
      fromJson: (d) => d as Map<String, dynamic>,
    );
    final data = response.data ?? <String, dynamic>{};
    final uploadUrl = (data['uploadUrl'] ?? data['upload_url']) as String;
    final storageKey = (data['storageKey'] ?? data['storage_key']) as String;
    return _PresignResult(uploadUrl: uploadUrl, storageKey: storageKey);
  }

  Future<void> _putBytes(
    String uploadUrl,
    List<int> bytes,
    String contentType,
  ) async {
    await _api.dio.put(
      uploadUrl,
      data: bytes,
      options: Options(headers: {'Content-Type': contentType}),
    );
  }

  Future<QueuedUpload> _enqueueUpload({
    required String fileType,
    required int trailerId,
    required String fileName,
    required List<int> bytes,
    required String contentType,
    required CapturedPhotoMetadata metadata,
  }) async {
    if (kIsWeb) {
      throw UnsupportedError('Offline upload queue is not supported on web.');
    }
    final dir = await getApplicationDocumentsDirectory();
    final uploadsDir = Directory(p.join(dir.path, 'pending_uploads'));
    if (!await uploadsDir.exists()) {
      await uploadsDir.create(recursive: true);
    }
    final localId = _uuid.v4();
    final filePath = p.join(uploadsDir.path, '$localId-$fileName');
    await File(filePath).writeAsBytes(bytes, flush: true);
    final item = QueuedUpload(
      localId: localId,
      fileType: fileType,
      trailerId: trailerId,
      fileName: fileName,
      filePath: filePath,
      contentType: contentType,
      metadata: metadata,
      createdAt: DateTime.now().toUtc(),
    );
    _queue = [..._queue, item];
    await _persistQueue();
    _emitCount();
    return item;
  }

  Future<void> _removeFromQueue(String localId) async {
    QueuedUpload? item;
    for (final queued in _queue) {
      if (queued.localId == localId) {
        item = queued;
        break;
      }
    }
    if (item == null) return;
    _queue = _queue.where((q) => q.localId != localId).toList();
    await _persistQueue();
  }

  Future<void> _loadQueue() async {
    final file = await _queueFile();
    if (!await file.exists()) {
      _queue = const [];
      return;
    }
    try {
      final raw = await file.readAsString();
      final decoded = jsonDecode(raw) as List<dynamic>;
      _queue = decoded
          .whereType<Map<String, dynamic>>()
          .map(QueuedUpload.fromJson)
          .toList();
    } catch (_) {
      _queue = const [];
    }
  }

  Future<void> _persistQueue() async {
    final file = await _queueFile();
    await file.writeAsString(
      jsonEncode(_queue.map((e) => e.toJson()).toList()),
      flush: true,
    );
  }

  Future<File> _queueFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File(p.join(dir.path, _queueFileName));
  }

  void _emitCount() {
    if (!_pendingCountController.isClosed) {
      _pendingCountController.add(_queue.length);
    }
  }

  bool _isNetworkish(Object e) {
    return e is DioException || e is SocketException || e is TimeoutException;
  }

  @override
  Future<void> dispose() async {
    await _connectivitySub?.cancel();
    await _pendingCountController.close();
    await _eventsController.close();
  }
}

class _PresignResult {
  final String uploadUrl;
  final String storageKey;

  const _PresignResult({required this.uploadUrl, required this.storageKey});
}
