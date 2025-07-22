// lib/features/admin/students/add_student_page.dart

import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/api_config.dart';

class AddStudentPage extends StatefulWidget {
  const AddStudentPage({super.key});
  @override
  State<AddStudentPage> createState() => _AddStudentPageState();
}

class _AddStudentPageState extends State<AddStudentPage> {
  static const _greenStart = Color(0xff27ae60);
  static const _greenEnd = Color(0xff219150);
  static const _bgLight = Color(0xfff0faf2);

  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _regNo = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _pass = TextEditingController(text: '123456');

  String? _college;
  int? _supervisorId;
  List<Map<String, dynamic>> _supers = [];
  final ValueNotifier<String> _type = ValueNotifier('regular');
  bool _busy = false;

  Future<void> _fetchSupers(String? coll) async {
    setState(() => _supers = []);
    _supervisorId = null;
    if (coll == null) return;
    final r = await Dio().get(
      '${ApiConfig.baseUrl}/public/regular-supervisors',
      queryParameters: {'college': coll},
    );
    if (!mounted) return;
    setState(() => _supers = List<Map<String, dynamic>>.from(r.data));
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    final token =
        (await SharedPreferences.getInstance()).getString('token') ?? '';
    try {
      await Dio().post(
        '${ApiConfig.baseUrl}/students',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
        data: {
          'name': _name.text.trim(),
          'reg_number': _regNo.text.trim(),
          'email': _email.text.trim(),
          'phone': _phone.text.trim(),
          'college': _college,
          'password': _pass.text.trim(),
          'student_type': _type.value,
          'supervisor_id': _supervisorId,
        },
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } on DioException catch (e) {
      final m = e.response?.data['message'] ?? 'فشل الحفظ';
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(m, style: GoogleFonts.cairo())));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(24),
                    bottomRight: Radius.circular(24),
                  ),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Positioned(
                      right: 8,
                      child: IconButton(
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Image.asset('assets/logo1.png', width: 60, height: 60),
                        const SizedBox(height: 4),
                        Text(
                          'إضافة طالب جديد',
                          style: GoogleFonts.cairo(
                            textStyle: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // ─── FORM ───
              Expanded(
                child: Container(
                  color: _bgLight,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 24,
                  ),
                  child: AnimationLimiter(
                    child: Form(
                      key: _form,
                      child: ListView(
                        physics: const BouncingScrollPhysics(),
                        children: AnimationConfiguration.toStaggeredList(
                          duration: const Duration(milliseconds: 600),
                          childAnimationBuilder: (widget) => SlideAnimation(
                            verticalOffset: 50,
                            child: FadeInAnimation(child: widget),
                          ),
                          children: [
                            _field('الاسم الكامل', _name),
                            _field(
                              'رقم التسجيل',
                              _regNo,
                              kb: TextInputType.number,
                            ),
                            _field(
                              'البريد الإلكتروني',
                              _email,
                              kb: TextInputType.emailAddress,
                              req: false,
                            ),
                            _field(
                              'الهاتف',
                              _phone,
                              kb: TextInputType.phone,
                              req: false,
                            ),
                            _ddCollege(),
                            _radioType(),
                            _ddSupervisor(),
                            _field(
                              'كلمة المرور (افتراضية 123456)',
                              _pass,
                              obscure: true,
                            ),
                            const SizedBox(height: 24),
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
                                    : Text(
                                        'حفظ',
                                        style: GoogleFonts.cairo(
                                          color: Colors.white,
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
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(
    String label,
    TextEditingController ctrl, {
    TextInputType? kb,
    bool obscure = false,
    bool req = true,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: TextFormField(
        controller: ctrl,
        keyboardType: kb,
        obscureText: obscure,
        style: GoogleFonts.cairo(),
        validator: (v) =>
            !req || (v != null && v.trim().isNotEmpty) ? null : 'مطلوب',
        decoration: InputDecoration(
          labelText: label,
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  Widget _ddCollege() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: DropdownButtonFormField<String>(
        value: _college,
        decoration: InputDecoration(
          labelText: 'الكلية',
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
        items: const [
          DropdownMenuItem(value: 'Engineering', child: Text('Engineering')),
          DropdownMenuItem(value: 'Medical', child: Text('Medical')),
          DropdownMenuItem(value: 'Sharia', child: Text('Sharia')),
        ],
        validator: (v) => v == null ? 'مطلوب' : null,
        onChanged: (v) {
          setState(() => _college = v);
          _fetchSupers(v);
        },
      ),
    );
  }

  Widget _radioType() {
    return ValueListenableBuilder<String>(
      valueListenable: _type,
      builder: (_, v, __) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                Radio<String>(
                  value: 'regular',
                  groupValue: v,
                  onChanged: (s) => _type.value = s!,
                ),
                Text('عادي', style: GoogleFonts.cairo()),
              ],
            ),
            const SizedBox(width: 24),
            Row(
              children: [
                Radio<String>(
                  value: 'intensive',
                  groupValue: v,
                  onChanged: (s) => _type.value = s!,
                ),
                Text('تثبيت', style: GoogleFonts.cairo()),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _ddSupervisor() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: DropdownButtonFormField<int>(
        value: _supervisorId,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: 'المشرف',
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
        items: _supers
            .map(
              (s) =>
                  DropdownMenuItem<int>(value: s['id'], child: Text(s['name'])),
            )
            .toList(),
        validator: (v) => v == null ? 'اختر مشرفًا' : null,
        onChanged: (v) => setState(() => _supervisorId = v),
      ),
    );
  }
}
