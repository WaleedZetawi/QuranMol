import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';

import '../../services/dio_client.dart';

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

  // تحقق
  final _emailRx = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
  final _digitsRx = RegExp(r'^\d+$');

  bool _busy = false;
  bool _canSave = false;

  @override
  void initState() {
    super.initState();
    final d = widget.data;
    _name = TextEditingController(text: d['name'] ?? '');
    _reg = TextEditingController(text: d['reg_number'] ?? '');
    _phone = TextEditingController(text: d['phone'] ?? '');
    _email = TextEditingController(text: d['email'] ?? '');

    // مراقبة الحقول لتفعيل/تعطيل زر الحفظ
    for (final c in [_name, _reg, _phone, _email]) {
      c.addListener(_recomputeCanSave);
    }
    _recomputeCanSave();
  }

  void _recomputeCanSave() {
    final name = _name.text.trim();
    final reg = _reg.text.trim();
    final phone = _phone.text.trim();
    final email = _email.text.trim();

    final ok = name.isNotEmpty &&
        !_digitsRx.hasMatch(name) && // الاسم ليس أرقامًا فقط
        _digitsRx.hasMatch(reg) && // التسجيل أرقام فقط
        _digitsRx.hasMatch(phone) && // الهاتف أرقام فقط
        _emailRx.hasMatch(email); // إيميل صحيح

    if (_canSave != ok) setState(() => _canSave = ok);
  }

  @override
  void dispose() {
    _name.dispose();
    _reg.dispose();
    _phone.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final dio = DioClient().dio;
      await dio.put('/users/${widget.data['id']}', data: {
        'name': _name.text.trim(),
        'reg_number': _reg.text.trim(),
        'phone': _phone.text.trim(),
        'email': _email.text.trim(),
      });
      if (!mounted) return;
      Navigator.pop(context, true);
    } on DioException catch (e) {
      final m = e.response?.data is Map
          ? (e.response?.data['message'] ?? 'فشل التعديل')
          : 'فشل التعديل';
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // حقل مع Validator مخصص + إمكانية تمرير الـ inputFormatters
  Widget _field(
    String lbl,
    TextEditingController ctrl, {
    TextInputType? type,
    bool req = true,
    String? Function(String?)? validator,
    List<TextInputFormatter>? formatters,
  }) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: TextFormField(
          controller: ctrl,
          keyboardType: type,
          inputFormatters: formatters,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          validator: (v) {
            final s = v?.trim() ?? '';
            if (req && s.isEmpty) return 'مطلوب';
            if (s.isNotEmpty && validator != null) return validator(s);
            return null;
          },
          decoration: const InputDecoration(
            border: OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(12)),
            ),
            filled: true,
            fillColor: Colors.white,
          ).copyWith(labelText: lbl),
        ),
      );

  @override
  Widget build(BuildContext ctx) {
    // الحقول مع القواعد:
    final nameField = _field(
      'الاسم',
      _name,
      validator: (s) =>
          _digitsRx.hasMatch(s!) ? 'الاسم لا يكون أرقامًا فقط' : null,
    );

    final regField = _field(
      'رقم التسجيل',
      _reg,
      type: TextInputType.number,
      formatters: [FilteringTextInputFormatter.digitsOnly],
      validator: (s) => _digitsRx.hasMatch(s!) ? null : 'أرقام فقط',
    );

    final phoneField = _field(
      'الهاتف',
      _phone,
      type: TextInputType.phone,
      formatters: [FilteringTextInputFormatter.digitsOnly],
      validator: (s) => _digitsRx.hasMatch(s!) ? null : 'أرقام فقط',
    );

    final emailField = _field(
      'البريد الإلكتروني',
      _email,
      type: TextInputType.emailAddress,
      validator: (s) => _emailRx.hasMatch(s!) ? null : 'بريد غير صالح',
    );

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
              // HEADER
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
                          icon:
                              const Icon(Icons.arrow_back, color: Colors.white),
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
              // FORM
              Expanded(
                child: Container(
                  color: _bgLight,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                            nameField,
                            regField,
                            phoneField,
                            emailField,
                            const SizedBox(height: 20),
                            SizedBox(
                              height: 48,
                              child: ElevatedButton(
                                onPressed: (_busy || !_canSave)
                                    ? null
                                    : () {
                                        if (_form.currentState!.validate())
                                          _save();
                                      },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _greenStart,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: _busy
                                    ? const CircularProgressIndicator(
                                        color: Colors.white)
                                    : const Text('حفظ',
                                        style: TextStyle(color: Colors.white)),
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
