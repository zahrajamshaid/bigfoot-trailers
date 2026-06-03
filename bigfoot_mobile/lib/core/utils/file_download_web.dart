import 'dart:convert';
// ignore: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:html' as html;

/// Triggers a browser download of [content] as a file named [filename].
///
/// Prepends a UTF-8 BOM so Excel/Sheets detect the encoding and render
/// non-ASCII characters (e.g. the `·` department separator, accented names)
/// correctly instead of as mojibake.
Future<void> downloadTextFile(
  String content,
  String filename, {
  String mimeType = 'text/plain',
}) async {
  const bom = '﻿';
  final bytes = utf8.encode('$bom$content');
  final blob = html.Blob(<Object>[bytes], mimeType);
  final url = html.Url.createObjectUrlFromBlob(blob);
  try {
    final anchor = html.AnchorElement(href: url)
      ..setAttribute('download', filename)
      ..style.display = 'none';
    html.document.body!.append(anchor);
    anchor.click();
    anchor.remove();
  } finally {
    html.Url.revokeObjectUrl(url);
  }
}
