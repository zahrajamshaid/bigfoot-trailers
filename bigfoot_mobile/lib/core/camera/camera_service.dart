import 'dart:typed_data';

import 'package:geolocator/geolocator.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../data/models/storage_upload.dart';
import '../platform/platform_support.dart';

class CameraPermissionDeniedException implements Exception {
  final String message;
  const CameraPermissionDeniedException(this.message);

  @override
  String toString() => message;
}

class CameraService {
  final ImagePicker _picker = ImagePicker();

  Future<CapturedPhoto?> takePhoto() async {
    final granted = await _ensureCameraPermission();
    if (!granted) return null;

    final file = await _picker.pickImage(source: ImageSource.camera, imageQuality: 100);
    if (file == null) return null;
    return _captureFromBytes(await file.readAsBytes(), file.name);
  }

  Future<CapturedPhoto?> pickFromGallery() async {
    final granted = await _ensureGalleryPermission();
    if (!granted) return null;

    final file = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 100);
    if (file == null) return null;
    return _captureFromBytes(await file.readAsBytes(), file.name);
  }

  Future<CapturedPhoto> _captureFromBytes(List<int> rawBytes, String originalName) async {
    final bytes = await compressImage(rawBytes);
    final position = await _currentPosition();
    final metadata = CapturedPhotoMetadata(
      capturedAt: DateTime.now().toUtc(),
      latitude: position?.latitude,
      longitude: position?.longitude,
    );
    return CapturedPhoto(
      bytes: bytes,
      fileName: _normalizeFileName(originalName),
      metadata: metadata,
    );
  }

  Future<List<int>> compressImage(List<int> bytes) async {
    final decoded = img.decodeImage(Uint8List.fromList(bytes));
    if (decoded == null) return bytes;

    final targetWidth = decoded.width > 1024 ? 1024 : decoded.width;
    final resized = decoded.width > targetWidth
        ? img.copyResize(decoded, width: targetWidth)
        : decoded;
    return Uint8List.fromList(img.encodeJpg(resized, quality: 80));
  }

  Future<bool> _ensureCameraPermission() async {
    // Desktop targets get the system camera/file dialog from image_picker
    // itself — there's no permission_handler implementation to call.
    if (!PlatformSupport.supportsPermissionHandler) return true;
    final status = await Permission.camera.request();
    if (status.isGranted) return true;
    throw const CameraPermissionDeniedException('Camera permission denied');
  }

  Future<bool> _ensureGalleryPermission() async {
    if (!PlatformSupport.supportsPermissionHandler) return true;
    final status = await Permission.photos.request();
    if (status.isGranted) return true;
    final storageStatus = await Permission.storage.request();
    if (storageStatus.isGranted) return true;
    throw const CameraPermissionDeniedException('Gallery permission denied');
  }

  Future<Position?> _currentPosition() async {
    // GPS tagging is a phone-capture niceity; on desktop we skip it rather
    // than wire a separate location-permission flow.
    if (!PlatformSupport.supportsPermissionHandler) return null;
    try {
      if (!await Permission.locationWhenInUse.request().isGranted) return null;
      return Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.low),
      );
    } catch (_) {
      return null;
    }
  }

  String _normalizeFileName(String originalName) {
    final base = originalName.split('/').last.split('\\').last;
    final stem = base.contains('.') ? base.substring(0, base.lastIndexOf('.')) : base;
    return '$stem-${DateTime.now().millisecondsSinceEpoch}.jpg';
  }
}
