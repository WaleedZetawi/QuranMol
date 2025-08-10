// lib/features/auth/registration_page.dart

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // لأجل inputFormatters
import '../../services/api_config.dart';

class RegistrationPage extends StatefulWidget {
  const RegistrationPage({super.key});
  @override
  State<RegistrationPage> createState() => _RegistrationPageState();
}

class _RegistrationPageState extends State<RegistrationPage> {
  final _form = GlobalKey<FormState>();

  String _role = 'student'; // student | supervisor
  final _name = TextEditingController();
  final _regNumber = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final ValueNotifier<String> _studentType = ValueNotifier<String>('regular');

  String?
      _college; // Engineering | Medical | Sharia | NewCampus | OldCampus | Agriculture
  String? _gender; // male | female

  bool _busy = false;

  final Set<String> _femaleOnly = const {
    'NewCampus',
    'OldCampus',
    'Agriculture'
  };
  final Set<String> _maleOnly = const {'Engineering', 'Medical', 'Sharia'};

  @override
  void dispose() {
    _name.dispose();
    _regNumber.dispose();
    _email.dispose();
    _phone.dispose();
    _password.dispose();
    _studentType.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;

    if (_gender == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('الرجاء اختيار النوع')));
      return;
    }
    if (_college == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('الرجاء اختيار الكلية')));
      return;
    }
    if (_femaleOnly.contains(_college!) && _gender != 'female') {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('هذه الكلية خاصة بالإناث')));
      return;
    }
    if (_maleOnly.contains(_college!) && _gender != 'male') {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('هذه الكلية خاصة بالذكور')));
      return;
    }

    setState(() => _busy = true);
    try {
      await Dio().post(
        '${ApiConfig.baseUrl}/register',
        data: {
          'role': _role, // student | supervisor
          'name': _name.text.trim(),
          'reg_number': _regNumber.text.trim(),
          'email': _email.text.trim(),
          'phone': _phone.text.trim().isEmpty ? null : _phone.text.trim(),
          'college': _college,
          'password': _password.text.trim(),
          'student_type': _role == 'student' ? _studentType.value : null,
          'gender': _gender,
          // ⛔️ لا نرسل supervisor_id نهائيًا — التعيين لاحقًا من المسؤول/المسؤولة
        },
      );

      if (!mounted) return;

      // حوار تأكيد مع زر إغلاق
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('تم الإرسال'),
          content: const Text(
              'تم استلام طلبك، سيتم مراجعته وسيصلك بريد عند القبول.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('موافق'),
            ),
          ],
        ),
      );

      if (!mounted) return;
      // ارجاع المستخدم لصفحة تسجيل الدخول
      Navigator.of(context).pop();
    } on DioException catch (e) {
      final data = e.response?.data;
      final msg = (data is Map && data['message'] != null)
          ? data['message'].toString()
          : (data is String && data.isNotEmpty)
              ? data
              : (e.message ?? 'فشل الإرسال');
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(msg)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('فشل الإرسال')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xfff8f9fa),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xff27ae60)),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: Card(
                elevation: 6,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Form(
                    key: _form,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Image.asset('assets/logo1.png', height: 100),
                        const SizedBox(height: 10),
                        const Text(
                          'طلب تسجيل في الملتقى',
                          style: TextStyle(
                              fontSize: 22, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 20),

                        _radioRole(),
                        _field('الاسم', _name),

                        // رقم التسجيل (أرقام فقط)
                        _field(
                          'رقم التسجيل',
                          _regNumber,
                          kb: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly
                          ],
                          validator: (v) => (v != null && v.trim().isNotEmpty)
                              ? null
                              : 'مطلوب',
                        ),

                        // النوع قبل الكلية
                        _genderPicker(),

                        // الكلية (تظهر حسب الجنس)
                        _dropdownCollege(),

                        if (_role == 'student') _radioType(),

                        // ملاحظة ثابتة: التعيين لاحقًا من الإدارة
                        Padding(
                          padding: const EdgeInsets.only(top: 6, bottom: 4),
                          child: Text(
                            'ملاحظة: يتم تعيين المشرف/المشرفة لاحقًا من جهة الإدارة بعد قبول الطلب.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: Colors.grey[700], fontSize: 12),
                          ),
                        ),

                        _field('البريد الإلكتروني', _email,
                            kb: TextInputType.emailAddress),

                        // الهاتف (أرقام فقط – غير إلزامي)
                        _field(
                          'الهاتف',
                          _phone,
                          kb: TextInputType.phone,
                          req: false,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly
                          ],
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) return null;
                            return RegExp(r'^\d+$').hasMatch(v.trim())
                                ? null
                                : 'أرقام فقط';
                          },
                        ),

                        _field('كلمة السر', _password, obscure: true),

                        const SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _busy ? null : _submit,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xff27ae60),
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: _busy
                                ? const CircularProgressIndicator(
                                    color: Colors.white)
                                : const Text('إرسال الطلب',
                                    style: TextStyle(fontSize: 18)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _radioRole() => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _radio('student', 'طالب/ـة'),
          const SizedBox(width: 16),
          _radio('supervisor', 'مشرف/ـة'),
        ],
      );

  Widget _radio(String v, String lbl) => Row(
        children: [
          Radio<String>(
            value: v,
            groupValue: _role,
            onChanged: (s) => setState(() => _role = s!),
          ),
          Text(lbl),
        ],
      );

  Widget _radioType() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: ValueListenableBuilder(
          valueListenable: _studentType,
          builder: (_, String v, __) => Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _typeItem('regular', 'عادي', v),
              const SizedBox(width: 20),
              _typeItem('intensive', 'تثبيت', v),
            ],
          ),
        ),
      );

  Widget _typeItem(String val, String lbl, String g) => Row(
        children: [
          Radio<String>(
            value: val,
            groupValue: g,
            onChanged: (s) => _studentType.value = s!,
          ),
          Text(lbl),
        ],
      );

  // حقل نصي عام
  Widget _field(
    String l,
    TextEditingController c, {
    TextInputType? kb,
    bool req = true,
    bool obscure = false,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
  }) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: TextFormField(
          controller: c,
          obscureText: obscure,
          keyboardType: kb,
          inputFormatters: inputFormatters,
          validator: validator ??
              (v) =>
                  !req || (v != null && v.trim().isNotEmpty) ? null : 'مطلوب',
          decoration: InputDecoration(
            labelText: l,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            filled: true,
            fillColor: Colors.white,
          ),
        ),
      );

  // عناصر الكلية حسب الجنس
  List<DropdownMenuItem<String>> _collegeItems() {
    if (_gender == 'male') {
      return const [
        DropdownMenuItem(value: 'Engineering', child: Text('الهندسة (ذكور)')),
        DropdownMenuItem(value: 'Medical', child: Text('الطب (ذكور)')),
        DropdownMenuItem(value: 'Sharia', child: Text('الشريعة (ذكور)')),
      ];
    }
    if (_gender == 'female') {
      return const [
        DropdownMenuItem(value: 'NewCampus', child: Text('حرم جديد (إناث)')),
        DropdownMenuItem(value: 'OldCampus', child: Text('حرم قديم (إناث)')),
        DropdownMenuItem(value: 'Agriculture', child: Text('زراعة (إناث)')),
      ];
    }
    return const []; // لم يُحدَّد الجنس بعد
  }

  Widget _dropdownCollege() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: DropdownButtonFormField<String>(
          value: _college,
          decoration: InputDecoration(
            labelText: 'الكلية',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            filled: true,
            fillColor: Colors.white,
          ),
          items: _collegeItems(),
          validator: (v) => v == null ? 'مطلوب' : null,
          onChanged:
              (_gender == null) ? null : (v) => setState(() => _college = v),
        ),
      );

  Widget _genderPicker() => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Column(
          children: [
            const Text('النوع'),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(children: [
                  Radio<String>(
                    value: 'male',
                    groupValue: _gender,
                    onChanged: (s) => setState(() {
                      _gender = s;
                      _college = null; // نظّف الكلية عند تغيير الجنس
                    }),
                  ),
                  const Text('ذكر'),
                ]),
                const SizedBox(width: 24),
                Row(children: [
                  Radio<String>(
                    value: 'female',
                    groupValue: _gender,
                    onChanged: (s) => setState(() {
                      _gender = s;
                      _college = null; // نظّف الكلية عند تغيير الجنس
                    }),
                  ),
                  const Text('أنثى'),
                ]),
              ],
            ),
            if (_gender == null)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text(
                  'اختر النوع أولًا ليظهر لك اختيار الكلية',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
          ],
        ),
      );
}
