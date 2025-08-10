// ignore_for_file: avoid_web_libraries_in_flutter
library cert_downloader_web;

import 'dart:typed_data';
import 'dart:html' as html;

/// يحفظ الملف (bytes) ثم يفتح نافذة تنزيل للمتصفّح.
Future<void> saveAndOpen({
  required Uint8List bytes,
  required String fileName,
}) async {
  final blob = html.Blob([bytes]);
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.AnchorElement(href: url)
    ..download = fileName
    ..click();
  html.Url.revokeObjectUrl(url);
}
