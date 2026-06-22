import 'dart:typed_data';

import 'package:geolocator/geolocator.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../data/models/storage_upload.dart';
import '../platform/platform_support.dart';

class CameraPermissionDeniedException implements Exception {
  final String message;
  /// True when iOS has locked the permission to denied — `request()` will not
  /// show the prompt again. The user has to flip the toggle in Settings (or
  /// reinstall the app) to recover. The UI surfaces an "Open Settings" action
  /// only in that case so the snackbar stays terse otherwise.
  final bool permanentlyDenied;
  const CameraPermissionDeniedException(
    this.message, {
    this.permanentlyDenied = false,
  });

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
    if (status.isGranted || status.isLimited) return true;
    // On iOS, once the user has dismissed (or auto-dismissed) the system
    // prompt, future request() calls just return the cached state. Bubble
    // that up as `permanentlyDenied` so the UI can deep-link straight to
    // Settings instead of telling the user to find the toggle themselves.
    throw CameraPermissionDeniedException(
      'Camera permission denied',
      permanentlyDenied: status.isPermanentlyDenied || status.isRestricted,
    );
  }

  Future<bool> _ensureGalleryPermission() async {
    if (!PlatformSupport.supportsPermissionHandler) return true;
    final status = await Permission.photos.request();
    if (status.isGranted || status.isLimited) return true;
    final storageStatus = await Permission.storage.request();
    if (storageStatus.isGranted || storageStatus.isLimited) return true;
    throw CameraPermissionDeniedException(
      'Gallery permission denied',
      permanentlyDenied: status.isPermanentlyDenied ||
          status.isRestricted ||
          storageStatus.isPermanentlyDenied ||
          storageStatus.isRestricted,
    );
  }

  /// Deep-link the user into this app's iOS Settings page. Best-effort —
  /// returns false on platforms where permission_handler can't open settings.
  Future<bool> openSettings() async {
    if (!PlatformSupport.supportsPermissionHandler) return false;
    try {
      return await openAppSettings();
    } catch (_) {
      return false;
    }
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
