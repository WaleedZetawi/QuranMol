import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../services/auth_service.dart';
import '../services/dio_client.dart';

class OfficialExamRequestPage extends StatefulWidget {
  const OfficialExamRequestPage({Key? key}) : super(key: key);

  @override
  State<OfficialExamRequestPage> createState() =>
      _OfficialExamRequestPageState();
}

class _OfficialExamRequestPageState extends State<OfficialExamRequestPage>
    with TickerProviderStateMixin {
  /* ───── المتغيّرات ───── */
  final _formKey = GlobalKey<FormState>();
  String? _code;
  DateTime _trialDate = DateTime.now();
  bool _busy = false;

  String _studentType = 'regular'; // يُجلب من /students/me
  late List<String> _allowedCodes; // الأكواد بعد التصفية
  bool _loading = true; // أثناء التحميل

  bool _regDisabled = false; // إيقاف التسجيل الرسمى؟
  DateTime? _disabledFrom;
  DateTime? _disabledUntil;

  late final AnimationController _fadeCtrl;
  late final Animation<double> _fadeAnim;

  static const Color _bgStart = Color(0xFFE8F5E9);
  static const Color _bgEnd = Color(0xFF66BB6A);
  static const Color _cardColor = Colors.white;
  static const Color _fieldFill = Color(0xFFF1F8E9);
  static const Color _primary = Color(0xFF2E7D32);

  @override
  void initState() {
    super.initState();
    AuthService.ensureValidOrLogout(context);

    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..forward();
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeIn);

    _checkRegStatus();
    _prepareAllowedCodes();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  /* ═════════════════ 1) فحص حالة التسجيل الرسمى ═════════════════ */
  Future<void> _checkRegStatus() async {
    try {
      final resp = await DioClient().dio.get('/settings/exam-registration');
      final data = resp.data;
      final now = DateTime.now();

      setState(() {
        _disabledFrom = data['disabledFrom'] != null
            ? DateTime.parse(data['disabledFrom'])
            : null;
        _disabledUntil = data['disabledUntil'] != null
            ? DateTime.parse(data['disabledUntil'])
            : null;
        _regDisabled = _disabledFrom != null &&
            now.isAfter(_disabledFrom!.subtract(const Duration(days: 1))) &&
            (_disabledUntil == null ||
                now.isBefore(_disabledUntil!.add(const Duration(days: 1))));
      });
    } catch (e) {
      debugPrint('[_checkRegStatus] error: $e');
    }
  }

  /* ═════════════════ 2) حساب الأكواد المتاحة ═════════════════ */
  Future<void> _prepareAllowedCodes() async {
    try {
      // نوع الطالب
      final stu = await DioClient().dio.get('/students/me');
      _studentType = stu.data['student_type'] as String? ?? 'regular';

      // الأكواد النظرية لكل نوع
      const regCodes = ['F1', 'F2', 'F3', 'F4', 'F5', 'F6'];
      const intCodes = ['T1', 'T2', 'T3', 'H1', 'H2', 'Q'];
      List<String> base = _studentType == 'regular' ? regCodes : intCodes;

      // الخطة (قد توقفت لامتحانات رسمية محددة)
      final planResp = await DioClient().dio.get('/plans/me');
      final plan = planResp.data as Map<String, dynamic>? ?? {};
      if (plan['paused_for_official'] == true &&
          (plan['official_exams'] as List?)?.isNotEmpty == true) {
        base = List<String>.from(plan['official_exams']);
      } else if (plan['paused_for_official'] == true &&
          (plan['official_exams'] as List?)?.isEmpty == true) {
        base = _studentType == 'regular' ? regCodes : intCodes;
      }

      // استبعاد ما تم اجتيازه رسميًا
      final passed = await DioClient().dio.get(
        '/exams/me',
        queryParameters: {'official': 1, 'passed': 1},
      );
      final passedCodes =
          (passed.data as List).map((e) => e['exam_code'].toString()).toSet();

      _allowedCodes = base.where((c) => !passedCodes.contains(c)).toList();
    } catch (e) {
      debugPrint('[_prepareAllowedCodes] $e');
      _allowedCodes = <String>[];
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /* ═════════════════ 3) أدوات مساعدة ═════════════════ */
  String arabicNameOf(String c) {
    switch (c) {
      case 'H1':
        return 'خمسة عشر الأولى';
      case 'H2':
        return 'خمسة عشر الثانية';
      case 'Q':
        return 'القرآن كامل';
      default:
        if (c.startsWith('F')) return 'خمسة أجزاء ${c.substring(1)}';
        if (c.startsWith('T')) return 'عشرة أجزاء ${c.substring(1)}';
        return c;
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _trialDate,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      locale: const Locale('ar'),
      builder: (_, child) => Theme(
        data: ThemeData.light().copyWith(
          colorScheme: const ColorScheme.light(primary: _primary),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _trialDate = picked);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final resp = await DioClient().dio.post(
        '/exam-requests',
        data: {
          'kind': 'official',
          'exam_code': _code!,
          'trial_date': DateFormat('yyyy-MM-dd').format(_trialDate),
        },
      );
      if (resp.statusCode == 201) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text('تم إرسال الطلب بنجاح', style: GoogleFonts.cairo())),
        );
        Navigator.pop(context, true);
      }
    } on DioError catch (e) {
      final msg = e.response?.data['message'] ?? 'فشل الإرسال';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg, style: GoogleFonts.cairo())),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /* ═════════════════ 4) الـ UI (بدون نافبار) ═════════════════ */
  @override
  Widget build(BuildContext context) {
    // حالات التحميل/الإيقاف مع نفس الخلفية الجميلة
    if (_loading || _regDisabled) {
      return Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [_bgStart, _bgEnd],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: SafeArea(
            child: Stack(
              children: [
                // زر الرجوع العائم
                _BackFloating(onTap: () => Navigator.pop(context)),
                Center(
                  child: _loading
                      ? const CircularProgressIndicator()
                      : Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            _disabledUntil != null
                                ? 'تم تعطيل التسجيل حتى ${DateFormat('yyyy-MM-dd').format(_disabledUntil!)}'
                                : 'التسجيل الرسمي مغلق حالياً',
                            style: GoogleFonts.cairo(
                                fontSize: 18, color: Colors.redAccent),
                            textAlign: TextAlign.center,
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      // ❌ لا AppBar
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [_bgStart, _bgEnd],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: FadeTransition(
            opacity: _fadeAnim,
            child: Stack(
              children: [
                // زر رجوع عائم أعلى اليمين (كما بالصورة)
                _BackFloating(onTap: () => Navigator.pop(context)),

                // المحتوى
                Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Image.asset(
                        'assets/logo1.png',
                        width: 140,
                        height: 140,
                      ),
                    ),
                    Expanded(
                      child: Center(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 24),
                          child: Container(
                            padding: const EdgeInsets.all(24),
                            constraints: const BoxConstraints(maxWidth: 520),
                            decoration: BoxDecoration(
                              color: _cardColor,
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: const [
                                BoxShadow(
                                  color: Colors.black12,
                                  blurRadius: 16,
                                  offset: Offset(0, 8),
                                ),
                              ],
                            ),
                            child: Form(
                              key: _formKey,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    'طلب امتحان رسمي',
                                    textAlign: TextAlign.center,
                                    style: GoogleFonts.cairo(
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold,
                                      color: _primary,
                                    ),
                                  ),
                                  const SizedBox(height: 24),
                                  DropdownButtonFormField<String>(
                                    value: _code,
                                    iconEnabledColor: _primary,
                                    decoration: InputDecoration(
                                      labelText: 'اختر نوع الامتحان',
                                      labelStyle:
                                          GoogleFonts.cairo(color: _primary),
                                      filled: true,
                                      fillColor: _fieldFill,
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide.none,
                                      ),
                                    ),
                                    items: _allowedCodes
                                        .map(
                                          (c) => DropdownMenuItem(
                                            value: c,
                                            child: Text(
                                              arabicNameOf(c),
                                              style: GoogleFonts.cairo(),
                                            ),
                                          ),
                                        )
                                        .toList(),
                                    validator: (v) =>
                                        v == null ? 'مطلوب' : null,
                                    onChanged: (v) => setState(() => _code = v),
                                  ),
                                  const SizedBox(height: 20),
                                  InkWell(
                                    onTap: _pickDate,
                                    borderRadius: BorderRadius.circular(12),
                                    child: InputDecorator(
                                      decoration: InputDecoration(
                                        labelText: 'موعد الاختبار التجريبي',
                                        labelStyle:
                                            GoogleFonts.cairo(color: _primary),
                                        filled: true,
                                        fillColor: _fieldFill,
                                        border: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          borderSide: BorderSide.none,
                                        ),
                                      ),
                                      child: Text(
                                        DateFormat('yyyy-MM-dd')
                                            .format(_trialDate),
                                        style: GoogleFonts.cairo(
                                          color: Colors.black87,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 28),
                                  ElevatedButton(
                                    onPressed: _busy ? null : _submit,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: _primary,
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 14),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                    child: _busy
                                        ? const SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(
                                              color: Colors.white,
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : Text(
                                            'إرسال الطلب',
                                            style: GoogleFonts.cairo(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/* زر رجوع عائم صغير (بدون نافبار) */
class _BackFloating extends StatelessWidget {
  final VoidCallback onTap;
  const _BackFloating({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 8,
      right: 12, // أعلى اليمين لواجهة عربية
      child: Material(
        color: Colors.white,
        elevation: 1.5,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: const Padding(
            padding: EdgeInsets.all(8.0),
            // سهم للأمام يناسب الرجوع في RTL (كما في لقطة الشاشة)
            child: Icon(Icons.arrow_forward,
                color: _OfficialExamRequestPageState._primary),
          ),
        ),
      ),
    );
  }
}
