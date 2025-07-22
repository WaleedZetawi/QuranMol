import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import '../../services/api_config.dart'; // مسار ملفك

class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});
  @override
  _ForgotPasswordPageState createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final _email = TextEditingController();
  bool _sending = false;
  final _form = GlobalKey<FormState>();

  Future<void> _send() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _sending = true);
    try {
      await Dio().post(
        '${ApiConfig.baseUrl}/forgot-password',
        data: {'email': _email.text.trim()},
      );
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => VerifyCodePage(email: _email.text.trim()),
          ),
        );
      }
    } on DioException catch (e) {
      final msg = e.response?.data['message'] ?? 'حدث خطأ، حاول لاحقاً';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } finally {
      setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext ctx) {
    final primaryColor = const Color(0xFF1B5E20); // أخضر داكن رسمي
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8),
      appBar: AppBar(
        backgroundColor: primaryColor,
        title: const Text(
          'إعادة تعيين كلمة السر',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        elevation: 5,
        shadowColor: Colors.black45,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
          child: Container(
            padding: const EdgeInsets.all(24),
            constraints: const BoxConstraints(maxWidth: 400),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black12.withOpacity(0.1),
                  blurRadius: 25,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Form(
              key: _form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset("assets/logo1.png", width: 120),
                  const SizedBox(height: 24),
                  TextFormField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    validator: (v) =>
                        v != null && v.contains('@') ? null : 'البريد غير صحيح',
                    decoration: InputDecoration(
                      labelText: 'البريد الإلكتروني',
                      prefixIcon: const Icon(Icons.email),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 30),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _sending ? null : _send,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryColor,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 7,
                        shadowColor: Colors.black45,
                      ),
                      child: _sending
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Text(
                              'إرسال الكود',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class VerifyCodePage extends StatefulWidget {
  final String email;
  const VerifyCodePage({super.key, required this.email});
  @override
  State<VerifyCodePage> createState() => _VerifyCodePageState();
}

class _VerifyCodePageState extends State<VerifyCodePage> {
  final _code = TextEditingController();
  final _pass = TextEditingController();
  bool _busy = false;
  final _form = GlobalKey<FormState>();

  Future<void> _reset() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await Dio().post(
        '${ApiConfig.baseUrl}/reset-password',
        data: {
          'email': widget.email,
          'code': _code.text.trim(),
          'new_password': _pass.text.trim(),
        },
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم تغيير كلمة السر بنجاح')),
        );
        Navigator.popUntil(context, (r) => r.isFirst);
      }
    } on DioException catch (e) {
      final msg = e.response?.data['message'] ?? 'حدث خطأ، حاول لاحقاً';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } finally {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext ctx) {
    final primaryColor = const Color(0xFF1B5E20); // أخضر داكن رسمي
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8),
      appBar: AppBar(
        backgroundColor: primaryColor,
        title: const Text(
          'التحقق من الكود',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        elevation: 5,
        shadowColor: Colors.black45,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
          child: Container(
            padding: const EdgeInsets.all(24),
            constraints: const BoxConstraints(maxWidth: 400),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black12.withOpacity(0.1),
                  blurRadius: 25,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Form(
              key: _form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset("assets/logo1.png", width: 120),
                  const SizedBox(height: 24),
                  TextFormField(
                    controller: _code,
                    keyboardType: TextInputType.number,
                    validator: (v) => v != null && v.length == 6
                        ? null
                        : 'كود مكوّن من 6 أرقام',
                    decoration: InputDecoration(
                      labelText: 'الكود',
                      prefixIcon: const Icon(Icons.confirmation_number),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _pass,
                    obscureText: true,
                    validator: (v) => v != null && v.length >= 4
                        ? null
                        : 'كلمة السر قصيرة جداً',
                    decoration: InputDecoration(
                      labelText: 'كلمة السر الجديدة',
                      prefixIcon: const Icon(Icons.lock),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 30),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _busy ? null : _reset,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryColor,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 7,
                        shadowColor: Colors.black45,
                      ),
                      child: _busy
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Text(
                              'تأكيد',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
