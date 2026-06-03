/// Non-web stub. IO platforms should share files via the platform share sheet
/// rather than calling this. Present only so the conditional export resolves.
Future<void> downloadTextFile(
  String content,
  String filename, {
  String mimeType = 'text/plain',
}) async {
  throw UnsupportedError('downloadTextFile is only available on web');
}
