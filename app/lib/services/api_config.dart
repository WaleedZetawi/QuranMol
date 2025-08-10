// lib/services/api_config.dart
import 'package:flutter/foundation.dart' show kIsWeb, kReleaseMode;

// استيراد شرطي: على المنصات غير الويب نجيب dart:io، وعلى الويب نستخدم بديل وهمي
import 'platform_stub.dart' if (dart.library.io) 'platform_io.dart';

/// الدومين في الإنتاج (لا تغيّر مسار `/api` هنا)
const _prodHost = 'https://api.moltaqa.app';

/// أثناء التطوير على الماك/ويندوز أو iOS simulator/desktop
const _devHost = 'http://localhost:5000';

/// عند استخدام محاكي أندرويد (10.0.2.2 ↔ localhost:5000)
const _androidEmuHost = 'http://10.0.2.2:5000';

class ApiConfig {
  /// يختار الدومين المناسب حسب المنصة ونمط البناء
  static String get host {
    if (kReleaseMode) return _prodHost; // إنتاج
    if (kIsWeb) return _devHost; // تطوير ويب
    if (Platform.isAndroid) return _androidEmuHost; // محاكي أندرويد
    return _devHost; // iOS simulator أو سطح المكتب
  }

  /// المسار الأساسي لكل نداءات الـ API
  static String get baseUrl => '$host/api';
}
