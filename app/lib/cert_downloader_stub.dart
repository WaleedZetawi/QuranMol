library cert_downloader_stub;

import 'dart:typed_data';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';

/// يكتب الملف في مجلّد مؤقّت ثم يفتحه بالتطبيق الافتراضي (Android / iOS / Desktop).
Future<void> saveAndOpen({
  required Uint8List bytes,
  required String fileName,
}) async {
  final dir = await getTemporaryDirectory();
  final path = '${dir.path}/$fileName';
  final file = File(path);
  await file.writeAsBytes(bytes, flush: true);
  await OpenFile.open(path);
}
