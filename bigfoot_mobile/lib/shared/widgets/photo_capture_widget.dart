import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/camera/camera_service.dart';
import '../../core/constants/app_colors.dart';
import '../../data/models/storage_upload.dart';
import '../../domain/repositories/storage_repository.dart';
import 'image_viewer_screen.dart';

class PhotoCaptureSnapshot {
  final List<String> storageKeys;
  final int pendingCount;

  const PhotoCaptureSnapshot({
    required this.storageKeys,
    required this.pendingCount,
  });
}

class PhotoCaptureWidget extends StatefulWidget {
  final String fileType;
  final int trailerId;
  final int minPhotoCount;
  final String title;
  final ValueChanged<PhotoCaptureSnapshot>? onChanged;

  const PhotoCaptureWidget({
    super.key,
    required this.fileType,
    required this.title,
    required this.trailerId,
    this.minPhotoCount = 1,
    this.onChanged,
  });

  @override
  State<PhotoCaptureWidget> createState() => _PhotoCaptureWidgetState();
}

class _PhotoCaptureWidgetState extends State<PhotoCaptureWidget> {
  late final CameraService _cameraService;
  late final StorageRepository _storageRepository;
  final List<_PhotoItem> _items = [];
  StreamSubscription<StorageUploadEvent>? _uploadSub;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _cameraService = CameraService();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _storageRepository = context.read<StorageRepository>();
    _uploadSub ??= _storageRepository.events.listen(_handleUploadEvent);
  }

  @override
  void dispose() {
    _uploadSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final meetsMinimum = _items.length >= widget.minPhotoCount;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: meetsMinimum ? AppColors.divider : AppColors.error,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      widget.minPhotoCount > 0
                          ? 'Minimum ${widget.minPhotoCount} photo${widget.minPhotoCount == 1 ? '' : 's'}'
                          : 'Photos optional',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.disabled,
                      ),
                    ),
                  ],
                ),
              ),
              Chip(
                backgroundColor: _localPendingCount > 0
                    ? AppColors.warning.withValues(alpha: 0.18)
                    : AppColors.success.withValues(alpha: 0.12),
                label: Text(
                  _localPendingCount > 0
                      ? 'Pending $_localPendingCount'
                      : 'Ready',
                  style: TextStyle(
                    color: _localPendingCount > 0
                        ? AppColors.warning
                        : AppColors.success,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: _busy ? null : _captureFromCamera,
                icon: const Icon(Icons.photo_camera_outlined),
                label: const Text('Camera'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _busy ? null : _pickFromGallery,
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('Gallery'),
              ),
            ],
          ),
          if (!meetsMinimum)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                'Add at least the minimum required photos before submitting.',
                style: TextStyle(color: AppColors.error, fontSize: 12),
              ),
            ),
          const SizedBox(height: 10),
          SizedBox(
            height: 104,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _items.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, index) => _ThumbnailCard(
                item: _items[index],
                onTap: () => _openViewer(index),
                onDelete: () => _remove(index),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _captureFromCamera() async {
    try {
      await _addCaptured(await _cameraService.takePhoto());
    } on CameraPermissionDeniedException catch (e) {
      _showError(
        'Camera permission denied. Enable it in Settings → Apps → Bigfoot.',
      );
      debugPrint('takePhoto permission error: $e');
    } catch (e) {
      _showError('Could not capture or upload photo: $e');
    }
  }

  Future<void> _pickFromGallery() async {
    try {
      await _addCaptured(await _cameraService.pickFromGallery());
    } on CameraPermissionDeniedException catch (e) {
      _showError(
        'Gallery permission denied. Enable Photos access in Settings.',
      );
      debugPrint('pickFromGallery permission error: $e');
    } catch (e) {
      _showError('Could not select or upload photo: $e');
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  Future<void> _addCaptured(CapturedPhoto? photo) async {
    if (photo == null) return;
    final itemIndex = _items.length;
    setState(() {
      _busy = true;
      _items.add(
        _PhotoItem.local(bytes: photo.bytes, fileName: photo.fileName),
      );
    });
    _emitSnapshot();
    try {
      final result = await _storageRepository.uploadFile(
        fileType: widget.fileType,
        trailerId: widget.trailerId,
        fileName: photo.fileName,
        bytes: photo.bytes,
        metadata: photo.metadata,
      );
      if (!mounted) return;
      setState(() {
        final item = _items.last;
        _items[_items.length - 1] = item.copyWith(
          storageKey: result.storageKey,
          queued: result.queued,
          localId: result.localId,
        );
      });
    } catch (_) {
      if (mounted && itemIndex < _items.length) {
        setState(() => _items.removeAt(itemIndex));
        _emitSnapshot();
      }
      rethrow;
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _emitSnapshot();
      }
    }
  }

  void _handleUploadEvent(StorageUploadEvent event) {
    final index = _items.indexWhere((item) => item.localId == event.localId);
    if (index == -1) return;
    setState(() {
      _items[index] = _items[index].copyWith(
        storageKey: event.storageKey,
        queued: false,
      );
    });
    _emitSnapshot();
  }

  void _remove(int index) {
    final item = _items[index];
    if (item.queued && item.localId != null) {
      _storageRepository.removeQueuedUpload(item.localId!);
    }
    setState(() => _items.removeAt(index));
    _emitSnapshot();
  }

  void _openViewer(int index) {
    final images = _items.map((e) => e.bytes).toList();
    final names = _items.map((e) => e.fileName).toList();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ImageViewerScreen(
          images: images,
          fileNames: names,
          initialIndex: index,
        ),
      ),
    );
  }

  void _emitSnapshot() {
    widget.onChanged?.call(
      PhotoCaptureSnapshot(
        storageKeys: _items
            .map((e) => e.storageKey)
            .whereType<String>()
            .toList(),
        pendingCount: _localPendingCount,
      ),
    );
  }

  int get _localPendingCount => _items.where((e) => e.queued).length;
}

class _PhotoItem {
  final Uint8List bytes;
  final String fileName;
  final String? storageKey;
  final String? localId;
  final bool queued;

  const _PhotoItem({
    required this.bytes,
    required this.fileName,
    this.storageKey,
    this.localId,
    this.queued = false,
  });

  factory _PhotoItem.local({
    required List<int> bytes,
    required String fileName,
  }) {
    return _PhotoItem(
      bytes: Uint8List.fromList(bytes),
      fileName: fileName,
      queued: true,
    );
  }

  _PhotoItem copyWith({String? storageKey, String? localId, bool? queued}) {
    return _PhotoItem(
      bytes: bytes,
      fileName: fileName,
      storageKey: storageKey ?? this.storageKey,
      localId: localId ?? this.localId,
      queued: queued ?? this.queued,
    );
  }
}

class _ThumbnailCard extends StatelessWidget {
  final _PhotoItem item;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _ThumbnailCard({
    required this.item,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: 96,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: AppColors.background,
              border: Border.all(color: AppColors.divider),
            ),
            clipBehavior: Clip.antiAlias,
            child: Image.memory(item.bytes, fit: BoxFit.cover),
          ),
        ),
        Positioned(
          right: 4,
          top: 4,
          child: InkWell(
            onTap: onDelete,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                shape: BoxShape.circle,
              ),
              padding: const EdgeInsets.all(3),
              child: const Icon(Icons.close, color: Colors.white, size: 14),
            ),
          ),
        ),
        if (item.queued)
          Positioned.fill(
            child: Container(
              color: Colors.black.withValues(alpha: 0.25),
              child: const Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
