import 'dart:io';

import '../../data/models/storage_upload.dart';

/// Abstract contract for file storage operations.
abstract class StorageRepository {
  Stream<int> get pendingCountStream;
  Stream<StorageUploadEvent> get events;
  int get pendingCount;

  Future<StorageUploadResult> uploadFile({
    required String fileType,
    required int trailerId,
    required String fileName,
    required List<int> bytes,
    String contentType,
    CapturedPhotoMetadata? metadata,
  });

  Future<String> getDownloadUrl(String storageKey);

  Future<File> downloadToTempFile(String storageKey, {String? fileName});

  Future<void> retryPendingUploads();

  Future<void> clearQueue();

  Future<void> removeQueuedUpload(String localId);

  Future<void> dispose();
}
