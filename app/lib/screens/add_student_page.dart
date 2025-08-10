import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/services.dart';

import '../../services/api_config.dart';

class AddStudentPage extends StatefulWidget {
  /// إذا أُرسلت → نستخدمها ونخفي/نقفل Dropdown الكلية
  final String? fixedCollege;

  /// true = ممنوع تغيير الكلية (حتى لو أظهرنا الـ dropdown)
  final bool lockCollege;

  /// ألوان الثيم القادمة من الصفحة السابقة
  final Color themeStart;
  final Color themeEnd;
  final Color bgLight;

  /// قائمة الكليات المسموح عرضها للمستخدم الحالي (اختياري)
  final List<String>? allowedColleges;

  /// الجنس القادم من الصفحة الأم: 'male' أو 'female' (إن توفر)
  final String? gender;

  const AddStudentPage({
    Key? key,
    this.fixedCollege,
    this.lockCollege = false,
    required this.themeStart,
    required this.themeEnd,
    required this.bgLight,
    this.allowedColleges, // ← كان موجود بالكونستركتر، الآن صار له حقل
    this.gender,
  }) : super(key: key);

  @override
  State<AddStudentPage> createState() => _AddStudentPageState();
}

class _AddStudentPageState extends State<AddStudentPage> {
  final _form = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _regNoCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _passCtrl = TextEditingController(text: '123456');

  String? _college;
  int? _supervisorId;
  List<Map<String, dynamic>> _supers = [];
  final ValueNotifier<String> _type = ValueNotifier('regular');
  bool _busy = false;

  bool get _isFemale => (widget.gender ?? '').toLowerCase() == 'female';
  String get _nounStudent => _isFemale ? 'طالبة' : 'طالب';
  String get _nounSupervisor => _isFemale ? 'مشرفة' : 'مشرف';
  String get _pickSupervisorMsg => _isFemale ? 'اختر مشرفةً' : 'اختر مشرفًا';

  @override
  void initState() {
    super.initState();

    // الأولوية: fixedCollege → أول عنصر من allowedColleges → null
    _college = widget.fixedCollege ??
        ((widget.allowedColleges != null && widget.allowedColleges!.isNotEmpty)
            ? widget.allowedColleges!.first
            : null);

    _fetchSupers(_college);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _regNoCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _passCtrl.dispose();
    _type.dispose();
    super.dispose();
  }

  Future<void> _fetchSupers(String? coll) async {
    setState(() => _supers = []);
    _supervisorId = null;
    if (coll == null) return;
    try {
      final qp = {
        'college': coll,
        if (widget.gender != null) 'gender': widget.gender,
      };
      final r = await Dio().get(
        '${ApiConfig.baseUrl}/public/regular-supervisors',
        queryParameters: qp,
      );
      if (!mounted) return;
      setState(() => _supers = List<Map<String, dynamic>>.from(r.data));
    } catch (_) {
      // تجاهل بهدوء
    }
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
          'name': _nameCtrl.text.trim(),
          'reg_number': _regNoCtrl.text.trim(),
          'email':
              _emailCtrl.text.trim().isEmpty ? null : _emailCtrl.text.trim(),
          'phone': _phoneCtrl.text.trim(),
          'college': _college,
          'password': _passCtrl.text.trim(),
          'student_type': _type.value,
          'supervisor_id': _supervisorId,
          // لا نرسل gender → الباك إند يستنتج تلقائيًا حسب الكلية ما لم يُرسل صراحة
        },
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } on DioException catch (e) {
      final m = e.response?.data?['message'] ?? 'فشل الحفظ';
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(m, style: GoogleFonts.cairo())),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _field(String label, TextEditingController ctrl,
      {TextInputType? kb,
      bool obscure = false,
      bool req = true,
      List<TextInputFormatter>? fmts}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: TextFormField(
        controller: ctrl,
        keyboardType: kb,
        obscureText: obscure,
        inputFormatters: fmts,
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
    final colleges = widget.allowedColleges ??
        const [
          'Engineering',
          'Medical',
          'Sharia',
          'NewCampus',
          'OldCampus',
          'Agriculture'
        ];

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
        items: colleges
            .map((c) => DropdownMenuItem(value: c, child: Text(c)))
            .toList(),
        validator: (v) => v == null ? 'مطلوب' : null,
        // لا تقفل الاختيار إلا إذا فعلاً عندك قيمة ثابتة
        onChanged: (widget.lockCollege && widget.fixedCollege != null)
            ? null
            : (v) {
                setState(() => _college = v);
                _fetchSupers(v);
              },
      ),
    );
  }

  Widget _radioType() {
    return ValueListenableBuilder<String>(
      valueListenable: _type,
      builder: (_, v, __) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(children: [
            Radio<String>(
                value: 'regular',
                groupValue: v,
                onChanged: (s) => _type.value = s!),
            Text('عادي', style: GoogleFonts.cairo()),
          ]),
          const SizedBox(width: 24),
          Row(children: [
            Radio<String>(
                value: 'intensive',
                groupValue: v,
                onChanged: (s) => _type.value = s!),
            Text('تثبيت', style: GoogleFonts.cairo()),
          ]),
        ],
      ),
    );
  }

  Widget _ddSupervisor() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: DropdownButtonFormField<int>(
        value: _supervisorId,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: _nounSupervisor, // مشرف/مشرفة
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
        items: _supers
            .map((s) => DropdownMenuItem<int>(
                  value: s['id'] as int,
                  child: Text(s['name'], style: GoogleFonts.cairo()),
                ))
            .toList(),
        validator: (v) => v == null ? _pickSupervisorMsg : null,
        onChanged: (v) => setState(() => _supervisorId = v),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = 'إضافة $_nounStudent';

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [widget.themeStart, widget.themeEnd],
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
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [widget.themeStart, widget.themeEnd],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                  borderRadius: const BorderRadius.only(
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
                          title,
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

              // FORM
              Expanded(
                child: Container(
                  color: widget.bgLight,
                  padding: const EdgeInsets.all(16),
                  child: AnimationLimiter(
                    child: Form(
                      key: _form,
                      child: ListView(
                        physics: const BouncingScrollPhysics(),
                        children: AnimationConfiguration.toStaggeredList(
                          duration: const Duration(milliseconds: 600),
                          childAnimationBuilder: (w) => SlideAnimation(
                            verticalOffset: 50,
                            child: FadeInAnimation(child: w),
                          ),
                          children: [
                            _field('الاسم الكامل', _nameCtrl),
                            _field('رقم التسجيل', _regNoCtrl,
                                kb: TextInputType.number,
                                fmts: [FilteringTextInputFormatter.digitsOnly]),
                            _field('البريد الإلكتروني', _emailCtrl,
                                kb: TextInputType.emailAddress, req: false),
                            _field('الهاتف', _phoneCtrl,
                                kb: TextInputType.phone,
                                req: false,
                                fmts: [FilteringTextInputFormatter.digitsOnly]),
                            if (widget.fixedCollege == null) _ddCollege(),
                            _radioType(),
                            _ddSupervisor(),
                            _field('كلمة المرور (افتراضية 123456)', _passCtrl,
                                obscure: true),
                            const SizedBox(height: 24),
                            SizedBox(
                              height: 48,
                              child: ElevatedButton(
                                onPressed: _busy ? null : _save,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: widget.themeStart,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: _busy
                                    ? const CircularProgressIndicator(
                                        color: Colors.white)
                                    : Text('حفظ',
                                        style: GoogleFonts.cairo(
                                            color: Colors.white)),
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
