import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart' show debugPrint;

class AuthService {
  static const _kTokenKey = 'token';

  /// حفظ التوكن في SharedPreferences
  static Future<void> saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kTokenKey, token);

    // لطباعة التوكن في الـ console لسهولة فحصه عبر jwt.io
    debugPrint('TOKEN => $token');
  }

  /// جلب التوكن (أو null إذا ليس موجود)
  static Future<String?> get token async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kTokenKey);
  }

  /// مسح التوكن عند تسجيل الخروج
  static Future<void> clearToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kTokenKey);
  }

  /// يستخرج الـ userId من داخل الـ JWT، أو يُرجع null إذا لم يوجد
  static Future<int?> get currentUserId async {
    final t = await token;
    if (t == null) return null;

    try {
      // تقسيم الـ JWT إلى ثلاثة أجزاء
      final parts = t.split('.');
      if (parts.length != 3) return null;

      // الدفق الأوسط هو payload (base64Url)
      final payload = parts[1];
      // أحياناً يحتاج للتطبيع ليقبله الديكودر
      final normalized = base64Url.normalize(payload);
      final decoded = utf8.decode(base64Url.decode(normalized));

      final map = json.decode(decoded) as Map<String, dynamic>;
      // نفرض أن الحقل في الـ payload اسمه "id"
      final idValue = map['id'];
      if (idValue is int) return idValue;
      if (idValue is String) return int.tryParse(idValue);
      return null;
    } catch (e) {
      debugPrint('AuthService.currentUserId decode error: $e');
      return null;
    }
  }
}
