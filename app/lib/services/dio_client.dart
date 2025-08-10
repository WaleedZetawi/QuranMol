// lib/services/dio_client.dart
import 'package:dio/dio.dart';
import 'api_config.dart';
import 'auth_service.dart';

/// ديو واحد موحّد مع Interceptors
class DioClient {
  DioClient._();
  static final DioClient _instance = DioClient._();
  factory DioClient() => _instance;

  /// دالة مساعدة لتطبيع المسار:
  /// - تبقي الروابط المطلقة كما هي (http/https)
  /// - تحذف أي / في بداية المسار
  /// - تحذف بادئة api/ إن وُجدت في بداية المسار
  static String _normalizePath(String p) {
    if (p.startsWith('http://') || p.startsWith('https://')) return p;

    // افصل الاستعلام إن وُجد للحفاظ عليه كما هو
    final q = p.indexOf('?');
    String path = q == -1 ? p : p.substring(0, q);
    final qs = q == -1 ? '' : p.substring(q); // يبدأ بـ ?

    // احذف أي شرطات مائلة في البداية
    path = path.replaceFirst(RegExp(r'^/+'), '');

    // احذف بادئة api/ لو كانت في بداية المسار
    if (path.startsWith('api/')) {
      path = path.substring(4);
    }

    return '$path$qs';
  }

  /// الـ Dio الأساسى المستخدم فى جميع النداءات
  final Dio dio = Dio(
    BaseOptions(
      // ضمان وجود / في نهاية الـ baseUrl
      baseUrl: ApiConfig.baseUrl.endsWith('/')
          ? ApiConfig.baseUrl
          : '${ApiConfig.baseUrl}/',
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      responseType: ResponseType.json,
    ),
  )..interceptors.add(
      InterceptorsWrapper(
        /* ───────── إضافة هيدر الـ Authorization ───────── */
        onRequest: (options, handler) async {
          final t = await AuthService.token;
          if (t != null) {
            options.headers['Authorization'] = 'Bearer $t';
          }

          // طبّع المسار قبل تكوين الـ URI النهائي
          if (!(options.path.startsWith('http://') ||
              options.path.startsWith('https://'))) {
            options.path = _normalizePath(options.path);
          }

          return handler.next(options);
        },

        /* ───────── معالجة الأخطاء ─────────
           لا نمسح التوكن إلا إذا كان السبب حقيقى فى التوثيق */
        onError: (e, handler) async {
          final sc = e.response?.statusCode;
          final msg = e.response?.data is Map
              ? (e.response!.data['message'] as String?)
              : null;

          /* 401  ← لا يوجد توكن
             403  ← توكن موجود لكن غير صالح (رسالة الخادم: "bad token") */
          final mustLogout = sc == 401 || (sc == 403 && msg == 'bad token');

          if (mustLogout) {
            await AuthService.clearToken();

            // إذا لديك navigatorKey عمومى وتريد إعادة توجيه فورى:
            // navigatorKey.currentState
            //     ?.pushNamedAndRemoveUntil('/login', (_) => false);
          }

          /* نُعيد الخطأ لباقى السلسلة حتى تتم معالجته فى الطبقات العليا */
          return handler.next(e);
        },
      ),
    );
}
