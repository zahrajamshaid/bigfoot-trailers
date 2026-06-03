// Cross-platform text-file download.
//
// On web this triggers a real browser file download (Blob + anchor click).
// On non-web platforms the stub throws — callers should guard with
// `kIsWeb` and use the platform share sheet for IO targets instead.
export 'file_download_stub.dart'
    if (dart.library.html) 'file_download_web.dart';
