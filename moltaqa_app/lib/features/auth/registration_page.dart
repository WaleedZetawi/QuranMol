import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../../services/api_config.dart';

class RegistrationPage extends StatefulWidget {
  const RegistrationPage({super.key});

  @override
  State<RegistrationPage> createState() => _RegistrationPageState();
}

class _RegistrationPageState extends State<RegistrationPage> {
  final _form = GlobalKey<FormState>();

  String _role = 'student';
  final _name = TextEditingController();
  final _regNumber = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final ValueNotifier<String> _studentType = ValueNotifier<String>('regular');

  String? _college;
  List<Map<String, dynamic>> _supers = [];
  int? _supervisorId;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadSupers();
  }

  Future<void> _loadSupers() async {
    try {
      final r = await Dio().get(
        '${ApiConfig.baseUrl}/public/regular-supervisors',
        queryParameters: _college == null ? null : {'college': _college},
      );
      setState(() => _supers = List<Map<String, dynamic>>.from(r.data));
    } catch (_) {}
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);

    try {
      await Dio().post(
        '${ApiConfig.baseUrl}/register',
        data: {
          'role': _role,
          'name': _name.text.trim(),
          'reg_number': _regNumber.text.trim(),
          'email': _email.text.trim(),
          'phone': _phone.text.trim(),
          'college': _college,
          'password': _password.text.trim(),
          'supervisor_id': _role == 'student' ? _supervisorId : null,
          'student_type': _role == 'student' ? _studentType.value : null,
        },
      );
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('تم الإرسال'),
          content: const Text(
            'تم استلام طلبك، سيتم مراجعته وسيصلك بريد عند القبول.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('حسناً'),
            ),
          ],
        ),
      );
      _form.currentState!.reset();
      setState(() {
        _role = 'student';
        _college = null;
        _supervisorId = null;
        _studentType.value = 'regular';
      });
    } on DioException catch (e) {
      final msg = e.response?.data['message'] ?? 'فشل الإرسال';
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(msg)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xfff8f9fa),
      body: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 40,
                  horizontal: 20,
                ),
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
                              'طلب تسجيل فى الملتقى',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 20),
                            _radioRole(),
                            _field('الاسم', _name),
                            _field(
                              'رقم التسجيل',
                              _regNumber,
                              kb: TextInputType.number,
                            ),
                            _dropdownCollege(),
                            if (_role == 'student') ...[
                              _radioType(),
                              _ddSupervisor(),
                            ],
                            _field(
                              'البريد الإلكترونى',
                              _email,
                              kb: TextInputType.emailAddress,
                            ),
                            _field(
                              'الهاتف',
                              _phone,
                              kb: TextInputType.phone,
                              req: false,
                            ),
                            _field('كلمة السر', _password, obscure: true),
                            const SizedBox(height: 20),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: _busy ? null : _submit,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xff27ae60),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 16,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: _busy
                                    ? const CircularProgressIndicator(
                                        color: Colors.white,
                                      )
                                    : const Text(
                                        'إرسال الطلب',
                                        style: TextStyle(fontSize: 18),
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
            ),
          );
        },
      ),
    );
  }

  Widget _radioRole() => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      _radio('student', 'طالب'),
      const SizedBox(width: 20),
      _radio('supervisor', 'مشرف'),
    ],
  );

  Widget _radio(String v, String lbl) => Row(
    children: [
      Radio<String>(
        value: v,
        groupValue: _role,
        onChanged: (s) => setState(() {
          _role = s!;
          if (_role != 'student') _supervisorId = null;
        }),
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

  Widget _field(
    String l,
    TextEditingController c, {
    TextInputType? kb,
    bool req = true,
    bool obscure = false,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: TextFormField(
      controller: c,
      obscureText: obscure,
      keyboardType: kb,
      validator: (v) =>
          !req || (v != null && v.trim().isNotEmpty) ? null : 'مطلوب',
      decoration: InputDecoration(
        labelText: l,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
        fillColor: Colors.white,
      ),
    ),
  );

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
      items: const [
        DropdownMenuItem(value: 'Engineering', child: Text('Engineering')),
        DropdownMenuItem(value: 'Medical', child: Text('Medical')),
        DropdownMenuItem(value: 'Sharia', child: Text('Sharia')),
      ],
      validator: (v) => v == null ? 'مطلوب' : null,
      onChanged: (v) async {
        setState(() {
          _college = v;
          _supervisorId = null;
        });
        await _loadSupers();
      },
    ),
  );

  Widget _ddSupervisor() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: DropdownButtonFormField<int>(
      value: _supervisorId,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: 'المشرف',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
        fillColor: Colors.white,
      ),
      items: _supers
          .map(
            (s) =>
                DropdownMenuItem(value: s['id'] as int, child: Text(s['name'])),
          )
          .toList(),
      onChanged: (v) => setState(() => _supervisorId = v),
      validator: (v) => v == null ? 'اختر مشرفًا' : null,
    ),
  );
}
