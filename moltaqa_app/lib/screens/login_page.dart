// lib/pages/login_page.dart

import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import '../services/api_config.dart';
import '../services/auth_service.dart';
import '../features/auth/registration_page.dart';
import 'forgot_password_page.dart';
import 'student_home_page.dart';
import 'admin_eng_page.dart';
import 'admin_medical_page.dart';
import 'admin_sharia_page.dart';
import 'admin_dashboard_page.dart';
import 'azkar_home_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({Key? key}) : super(key: key);

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _regCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _busy = false;
  bool _obscurePassword = true;

  Future<void> _login() async {
    if (_regCtrl.text.isEmpty || _passCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('الرجاء إدخال رقم التسجيل وكلمة السر')),
      );
      return;
    }

    setState(() => _busy = true);

    final dio = Dio();
    try {
      // محاولة دخول كمسؤول أولاً
      final r = await dio.post(
        '${ApiConfig.baseUrl}/login',
        data: {
          'reg_number': _regCtrl.text.trim(),
          'password': _passCtrl.text.trim(),
        },
      );
      await _onUserSuccess(r.data['token'], r.data['user']);
      return;
    } catch (_) {}

    try {
      // ثم محاولة دخول كطالب
      final r = await dio.post(
        '${ApiConfig.baseUrl}/student-login',
        data: {
          'reg_number': _regCtrl.text.trim(),
          'password': _passCtrl.text.trim(),
        },
      );
      await AuthService.saveToken(r.data['token']);
      debugPrint('TOKEN => ${r.data['token']}');

      final s = r.data['student'];
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => StudentHomePage(
            userName: s['name'],
            college: s['college'],
            studentType: s['student_type'] ?? 'regular',
            studentId: s['id'],
          ),
        ),
      );
    } on DioException catch (e) {
      final msg = e.response?.data['message'] ?? 'بيانات غير صحيحة';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _onUserSuccess(String token, Map u) async {
    await AuthService.saveToken(token);
    debugPrint('TOKEN => $token');

    final role = u['role'] as String?;
    final name = u['name'] ?? u['reg_number'];

    if (!mounted) return;
    switch (role) {
      case 'EngAdmin':
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => AdminEngPage(userName: name)),
        );
        break;
      case 'MedicalAdmin':
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => AdminMedicalPage(userName: name)),
        );
        break;
      case 'shariaAdmin':
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => AdminShariaPage(userName: name)),
        );
        break;
      case 'admin_dashboard':
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const AdminDashboardPage()),
        );
        break;
      default:
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('دور غير معروف')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cardW = MediaQuery.of(context).size.width > 500
        ? 440.0
        : MediaQuery.of(context).size.width * .95;

    const primaryColor = Color(0xFF2E7D32);
    const secondaryColor = Color(0xFF4CAF50);
    const forgotPasswordColor = Color(0xFF1565C0);

    return Scaffold(
      backgroundColor: const Color(0xFFF1F8E9),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 36),
          child: Container(
            width: cardW,
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 36),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 28,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // شعار الملتقى
                Image.asset('assets/logo1.png', width: 110),
                const SizedBox(height: 16),
                const Text(
                  'ملتقى القرآن الكريم',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: primaryColor,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 28),

                // رقم التسجيل
                TextField(
                  controller: _regCtrl,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(fontSize: 18),
                  decoration: InputDecoration(
                    labelText: 'رقم التسجيل',
                    labelStyle: const TextStyle(
                      color: primaryColor,
                      fontWeight: FontWeight.w600,
                    ),
                    prefixIcon:
                        const Icon(Icons.perm_identity, color: primaryColor),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderSide: const BorderSide(color: primaryColor),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: secondaryColor, width: 2),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    filled: true,
                    fillColor: const Color(0xFFF9FFF9),
                  ),
                ),
                const SizedBox(height: 22),

                // كلمة السر مع زر رؤية/إخفاء
                TextField(
                  controller: _passCtrl,
                  obscureText: _obscurePassword,
                  style: const TextStyle(fontSize: 18),
                  decoration: InputDecoration(
                    labelText: 'كلمة السر',
                    labelStyle: const TextStyle(
                      color: primaryColor,
                      fontWeight: FontWeight.w600,
                    ),
                    prefixIcon: const Icon(Icons.lock, color: primaryColor),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_off
                            : Icons.visibility,
                        color: primaryColor,
                      ),
                      onPressed: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderSide: const BorderSide(color: primaryColor),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: secondaryColor, width: 2),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    filled: true,
                    fillColor: const Color(0xFFF9FFF9),
                  ),
                ),
                const SizedBox(height: 20),

                // نسيت كلمة السر؟
                TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const ForgotPasswordPage()),
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: forgotPasswordColor,
                    textStyle: const TextStyle(
                      fontWeight: FontWeight.w700,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                  child: const Text('هل نسيت كلمة السر؟'),
                ),
                const SizedBox(height: 28),

                // زر دخول
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _busy ? null : _login,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryColor,
                      foregroundColor: Colors.white,
                      elevation: 6,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    child: _busy
                        ? const CircularProgressIndicator.adaptive(
                            valueColor: AlwaysStoppedAnimation(Colors.white),
                          )
                        : const Text('دخول'),
                  ),
                ),
                const SizedBox(height: 20),

                // زر الأذكار (🤲 Emoji بدون خلفية مربعات)
                InkWell(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const AzkarHomePage()),
                  ),
                  borderRadius: BorderRadius.circular(12),
                  child: Column(
                    children: [
                      Text(
                        '🤲',
                        style: TextStyle(
                          fontSize: 64, // حجم الإيموجي
                          height: 1, // يجعل الإيموجي يأخذ ارتفاعه الطبيعي
                        ),
                      ),
                      const SizedBox(height: 4), // مسافة صغيرة أكثر قربًا
                      const Text(
                        'أذكار المسلم',
                        style: TextStyle(
                          color: primaryColor,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // زر إنشاء حساب جديد
                TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const RegistrationPage()),
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: primaryColor,
                    textStyle: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                  child: const Text('إنشاء حساب جديد'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
