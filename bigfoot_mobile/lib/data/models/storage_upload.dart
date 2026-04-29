class CapturedPhotoMetadata {
  final DateTime capturedAt;
  final double? latitude;
  final double? longitude;

  const CapturedPhotoMetadata({
    required this.capturedAt,
    this.latitude,
    this.longitude,
  });

  Map<String, dynamic> toJson() => {
        'capturedAt': capturedAt.toUtc().toIso8601String(),
        if (latitude != null) 'latitude': latitude,
        if (longitude != null) 'longitude': longitude,
      };
}

class CapturedPhoto {
  final List<int> bytes;
  final String fileName;
  final CapturedPhotoMetadata metadata;

  const CapturedPhoto({
    required this.bytes,
    required this.fileName,
    required this.metadata,
  });
}

class StorageUploadResult {
  final String? storageKey;
  final bool queued;
  final String? localId;

  const StorageUploadResult._({
    required this.storageKey,
    required this.queued,
    required this.localId,
  });

  const StorageUploadResult.uploaded(String storageKey)
      : this._(storageKey: storageKey, queued: false, localId: null);

  const StorageUploadResult.queued(String localId)
      : this._(storageKey: null, queued: true, localId: localId);
}

class DownloadUrlCacheEntry {
  final String url;
  final DateTime expiresAt;

  const DownloadUrlCacheEntry({required this.url, required this.expiresAt});

  bool get isValid => DateTime.now().isBefore(expiresAt);
}

class QueuedUpload {
  final String localId;
  final String fileType;
  final int trailerId;
  final String fileName;
  final String filePath;
  final String contentType;
  final CapturedPhotoMetadata metadata;
  final DateTime createdAt;
  final String? uploadUrl;
  final String? storageKey;

  const QueuedUpload({
    required this.localId,
    required this.fileType,
    required this.trailerId,
    required this.fileName,
    required this.filePath,
    required this.contentType,
    required this.metadata,
    required this.createdAt,
    this.uploadUrl,
    this.storageKey,
  });

  QueuedUpload copyWith({
    String? uploadUrl,
    String? storageKey,
    String? filePath,
  }) {
    return QueuedUpload(
      localId: localId,
      fileType: fileType,
      trailerId: trailerId,
      fileName: fileName,
      filePath: filePath ?? this.filePath,
      contentType: contentType,
      metadata: metadata,
      createdAt: createdAt,
      uploadUrl: uploadUrl ?? this.uploadUrl,
      storageKey: storageKey ?? this.storageKey,
    );
  }

  Map<String, dynamic> toJson() => {
        'localId': localId,
        'fileType': fileType,
        'trailerId': trailerId,
        'fileName': fileName,
        'filePath': filePath,
        'contentType': contentType,
        'metadata': metadata.toJson(),
        'createdAt': createdAt.toUtc().toIso8601String(),
        if (uploadUrl != null) 'uploadUrl': uploadUrl,
        if (storageKey != null) 'storageKey': storageKey,
      };

  factory QueuedUpload.fromJson(Map<String, dynamic> json) {
    final metadataJson = json['metadata'] as Map<String, dynamic>? ?? const {};
    return QueuedUpload(
      localId: json['localId'] as String,
      fileType: json['fileType'] as String,
      trailerId: (json['trailerId'] as num).toInt(),
      fileName: json['fileName'] as String,
      filePath: json['filePath'] as String,
      contentType: json['contentType'] as String? ?? 'image/jpeg',
      metadata: CapturedPhotoMetadata(
        capturedAt: DateTime.tryParse(metadataJson['capturedAt']?.toString() ?? '') ??
            DateTime.now(),
        latitude: (metadataJson['latitude'] as num?)?.toDouble(),
        longitude: (metadataJson['longitude'] as num?)?.toDouble(),
      ),
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      uploadUrl: json['uploadUrl'] as String?,
      storageKey: json['storageKey'] as String?,
    );
  }
}

class StorageUploadEvent {
  final String localId;
  final String storageKey;

  const StorageUploadEvent({required this.localId, required this.storageKey});
}
