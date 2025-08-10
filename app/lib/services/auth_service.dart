import 'dart:convert';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// خدمة مصغّرة للتعامل مع JWT المحفوظ محلّيًا
class AuthService {
  static const _kTokenKey = 'token';

  /// حفظ الـ JWT
  static Future<void> saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kTokenKey, token);
    debugPrint('TOKEN ⮕ $token');
  }

  /// جلب الـ JWT
  static Future<String?> get token async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kTokenKey);
  }

  /// مسح الـ JWT
  static Future<void> clearToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kTokenKey);
  }

  /// فك الـ payload داخل الـ JWT
  static Future<Map<String, dynamic>?> get _payload async {
    final t = await token;
    if (t == null) return null;
    try {
      final parts = t.split('.');
      if (parts.length != 3) return null;
      final normalized = base64Url.normalize(parts[1]);
      final decoded = utf8.decode(base64Url.decode(normalized));
      return json.decode(decoded) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('AuthService payload decode error: $e');
      return null;
    }
  }

  /// إيدي المستخدم الحالي
  static Future<int?> get currentUserId async {
    final v = (await _payload)?['id'];
    if (v is int) return v;
    return int.tryParse('$v');
  }

  static Future<String?> get role async {
    final p = await _payload;
    final r = p?['role'];
    if (r != null) return r.toString(); // ← المصدر الموثوق: التوكن
    // fallback (اختياري) لو عندك كود قديم كان يخزّن role بالمخزن:
    final sp = await SharedPreferences.getInstance();
    return sp.getString('role');
  }

  static Future<String> genderForAdmin() async {
    final r = await role;
    final col = await college;

    if (r == 'admin_dash_f') return 'female';
    if (r == 'admin_dashboard') return 'male';

    // مسؤولو/مسؤولات كلية واحدة
    const femaleCols = {'NewCampus', 'OldCampus', 'Agriculture'};
    return femaleCols.contains(col) ? 'female' : 'male';
  }

  /// الكلية المُعرّفة في التوكن
  static Future<String?> get college async {
    return (await _payload)?['college'] as String?;
  }

  /// هل المستخدم “root” (admin_dashboard)
  static Future<bool> get isRoot async {
    return await role == 'admin_dashboard';
  }

  /// هل انتهت صلاحية التوكن؟
  static Future<bool> get isExpired async {
    final exp = (await _payload)?['exp'];
    if (exp is! int) return true;
    final expiry = DateTime.fromMillisecondsSinceEpoch(exp * 1000);
    return expiry.isBefore(DateTime.now());
  }

  /// إذا انتهى التوكن → مسحه وإعادة توجيه المستخدم للـ login
  static Future<void> ensureValidOrLogout(BuildContext ctx) async {
    if (await isExpired) {
      await clearToken();
      if (ctx.mounted) {
        Navigator.of(ctx).pushNamedAndRemoveUntil('/login', (_) => false);
      }
    }
  }

  /// أداة تشخيصية
  static Future<void> debugDumpToken() async {
    final t = await token;
    final pl = await _payload;
    debugPrint('──── JWT DEBUG ────');
    debugPrint('raw: $t');
    debugPrint('payload: $pl');

    // نتأكد إن payload موجود وإن exp رقم
    if (pl != null && pl['exp'] is int) {
      final expInt = pl['exp'] as int;
      final expDate = DateTime.fromMillisecondsSinceEpoch(expInt * 1000);
      debugPrint('exp: $expDate   (now: ${DateTime.now()})');
    }

    debugPrint('────────────────────');
  }
}
