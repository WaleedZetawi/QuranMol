import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';

import '../../services/api_config.dart';

class EditAdminPage extends StatefulWidget {
  final Map<String, dynamic> data;
  const EditAdminPage({super.key, required this.data});
  @override
  State<EditAdminPage> createState() => _EditAdminPageState();
}

class _EditAdminPageState extends State<EditAdminPage> {
  static const _greenStart = Color(0xff27ae60);
  static const _greenEnd = Color(0xff219150);
  static const _bgLight = Color(0xfff0faf2);

  final _form = GlobalKey<FormState>();
  late final TextEditingController _name, _reg, _phone, _email;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final d = widget.data;
    _name = TextEditingController(text: d['name'] ?? '');
    _reg = TextEditingController(text: d['reg_number'] ?? '');
    _phone = TextEditingController(text: d['phone'] ?? '');
    _email = TextEditingController(text: d['email'] ?? '');
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    final token =
        (await SharedPreferences.getInstance()).getString('token') ?? '';
    try {
      await Dio().put(
        '${ApiConfig.baseUrl}/users/${widget.data['id']}',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
        data: {
          'name': _name.text.trim(),
          'reg_number': _reg.text.trim(),
          'phone': _phone.text.trim(),
          'email': _email.text.trim(),
        },
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } on DioException catch (e) {
      final m = e.response?.data['message'] ?? 'فشل التعديل';
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _field(
    String lbl,
    TextEditingController ctrl, {
    TextInputType? type,
    bool req = true,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: TextFormField(
      controller: ctrl,
      keyboardType: type,
      validator: (v) =>
          !req || (v != null && v.trim().isNotEmpty) ? null : 'مطلوب',
      decoration: InputDecoration(
        labelText: lbl,
        border: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
        filled: true,
        fillColor: Colors.white,
      ),
    ),
  );

  @override
  Widget build(BuildContext ctx) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [_greenStart, _greenEnd],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // ─── HEADER ───
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [_greenStart, _greenEnd],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                  borderRadius: BorderRadius.vertical(
                    bottom: Radius.circular(24),
                  ),
                ),
                child: Directionality(
                  textDirection: TextDirection.rtl,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      PositionedDirectional(
                        start: 8,
                        child: IconButton(
                          icon: const Icon(
                            Icons.arrow_back,
                            color: Colors.white,
                          ),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ),
                      const Text(
                        'تعديل بيانات المسؤول',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // ─── FORM WITH ANIMATIONS ───
              Expanded(
                child: Container(
                  color: _bgLight,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Form(
                    key: _form,
                    child: AnimationLimiter(
                      child: ListView(
                        physics: const BouncingScrollPhysics(),
                        children: AnimationConfiguration.toStaggeredList(
                          duration: const Duration(milliseconds: 600),
                          childAnimationBuilder: (w) => SlideAnimation(
                            verticalOffset: 50,
                            child: FadeInAnimation(child: w),
                          ),
                          children: [
                            _field('الاسم', _name),
                            _field(
                              'رقم التسجيل',
                              _reg,
                              type: TextInputType.number,
                            ),
                            _field(
                              'الهاتف',
                              _phone,
                              type: TextInputType.phone,
                              req: false,
                            ),
                            _field(
                              'البريد الإلكتروني',
                              _email,
                              type: TextInputType.emailAddress,
                              req: false,
                            ),
                            const SizedBox(height: 20),
                            SizedBox(
                              height: 48,
                              child: ElevatedButton(
                                onPressed: _busy ? null : _save,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _greenStart,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: _busy
                                    ? const CircularProgressIndicator(
                                        color: Colors.white,
                                      )
                                    : const Text(
                                        'حفظ',
                                        style: TextStyle(color: Colors.white),
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
