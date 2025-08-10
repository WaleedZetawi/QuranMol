import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/api_config.dart';
import '../../services/dio_client.dart';

class PartExamRequestPage extends StatefulWidget {
  const PartExamRequestPage({Key? key}) : super(key: key);

  @override
  State<PartExamRequestPage> createState() => _PartExamRequestPageState();
}

/* ═══════════════════════════════════════════════════════════════ */

class _PartExamRequestPageState extends State<PartExamRequestPage>
    with TickerProviderStateMixin {
/* ─────── الحالة ─────── */
  final _formKey = GlobalKey<FormState>();
  int? _juz; // الجزء المختار
  int? _planCurrentPart; // الجزء الحالى فى الخطة
  late Set<int> _passedParts; // الأجزاء المجتازة رسميًّا
  DateTime? _date; // تاريخ الامتحان
  bool _busy = false; // دوّار الإرسال
  bool _isRedo = false; // وضع الإعادة

/* ─────── أنيميشن ─────── */
  late final AnimationController _fadeCtrl;
  late final Animation<double> _fadeAnim;

/* ─────── ألوان ثابتة ─────── */
  static const _bgStart = Color(0xFFE8F5E9);
  static const _bgEnd = Color(0xFF66BB6A);
  static const _cardColor = Colors.white;
  static const _fieldFill = Color(0xFFF1F8E9);
  static const _primary = Color(0xFF2E7D32);

/* ───────────────────── Lifecycle ───────────────────── */

  @override
  void initState() {
    super.initState();
    _passedParts = {};
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeIn);
    _fadeCtrl.forward();

    _loadPlanAndPassedParts();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

/* ─────────────────── Helpers ─────────────────── */

  Future<String> _getToken() async =>
      (await SharedPreferences.getInstance()).getString('token') ?? '';

  /// جلب current_part من الخطة + جميع الأجزاء المجتازة رسميًّا
  Future<void> _loadPlanAndPassedParts() async {
    try {
      final dio = DioClient().dio;

      /* 1) الخطة */
      final plan = await dio.get('/plans/me');
      final cp = plan.data['current_part'] as int?;
      /* 2) الامتحانات الرسمية الناجحة */
      final ex = await dio.get(
        '/exams/me',
        queryParameters: {'official': '1', 'passed': '1'},
      );

      final passed = <int>{};
      for (final row in ex.data as List) {
        final code = row['exam_code'] as String;
        if (code.startsWith('J')) {
          passed.add(int.parse(code.substring(1)));
        }
      }

      if (mounted) {
        setState(() {
          _planCurrentPart = cp;
          _juz = cp;
          _passedParts = passed;
          _isRedo = passed.contains(cp); // الجزء الحالى قد يكون أُعيد
        });
      }
    } catch (e) {
      debugPrint('[_loadPlanAndPassedParts] $e');
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(days: 1)),
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
    if (d != null) setState(() => _date = d);
  }

/* ───────── إرسال الطلب ───────── */
  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() || _date == null) return;

    /* ❶ تأكيد تغيير المسار */
    if (!_isRedo && _planCurrentPart != null && _juz != _planCurrentPart) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text('تأكيد', style: GoogleFonts.cairo()),
          content: Text(
            'الجزء الذى اخترته يختلف عن الجزء الحالى فى خطتك.\n'
            'متابعة الإرسال سيعدّل مسار الخطة إلى هذا الجزء.\n'
            'هل تريد المتابعة؟',
            style: GoogleFonts.cairo(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('إلغاء', style: GoogleFonts.cairo()),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text('متابعة', style: GoogleFonts.cairo()),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }

    /* ❷ إذا كان الجزء مجتازاً رسمياً ويُرسَل بدون إعادة → منع */
    if (_passedParts.contains(_juz) && !_isRedo) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'لقد اجتزت هذا الجزء رسميًّا – فعِّل خانة "إعادة هذا الجزء".',
            style: GoogleFonts.cairo(),
          ),
        ),
      );
      return;
    }

    setState(() => _busy = true);

    final token = await _getToken();
    try {
      await Dio(
        BaseOptions(headers: {'Authorization': 'Bearer $token'}),
      ).post(
        '${ApiConfig.baseUrl}/exam-requests',
        data: {
          'kind': 'part',
          'part': _juz,
          'date': DateFormat('yyyy-MM-dd').format(_date!),
          'run_mode': _isRedo ? 'redo' : 'normal',
        },
      );
      if (mounted) Navigator.pop(context, true);
    } on DioException catch (e) {
      final msg = e.response?.data['message'] ?? 'فشل الإرسال';
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg, style: GoogleFonts.cairo())),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

/* ─────────────────── UI ─────────────────── */

  @override
  Widget build(BuildContext context) {
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
          child: FadeTransition(
            opacity: _fadeAnim,
            child: Column(
              children: [
                Align(
                  alignment: Alignment.topRight,
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back, color: _primary),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 16, bottom: 8),
                  child: Center(
                    child: Image.asset(
                      'assets/logo1.png',
                      width: 140,
                      height: 140,
                    ),
                  ),
                ),
                Expanded(
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 24,
                      ),
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
                                'طلب امتحان جزء',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.cairo(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  color: _primary,
                                ),
                              ),
                              const SizedBox(height: 24),

                              /* اختيار الجزء */
                              DropdownButtonFormField<int>(
                                value: _juz ?? _planCurrentPart,
                                iconEnabledColor: _primary,
                                decoration: InputDecoration(
                                  labelText: 'اختر الجزء',
                                  labelStyle:
                                      GoogleFonts.cairo(color: _primary),
                                  filled: true,
                                  fillColor: _fieldFill,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide.none,
                                  ),
                                ),
                                items: [
                                  for (var i = 1; i <= 30; i++)
                                    DropdownMenuItem(
                                      value: i,
                                      child: Text(
                                        'الجزء $i',
                                        style: GoogleFonts.cairo(),
                                      ),
                                    ),
                                ],
                                validator: (v) => v == null ? 'مطلوب' : null,
                                onChanged: (v) => setState(() {
                                  _juz = v;
                                  _isRedo = _passedParts.contains(v);
                                }),
                              ),
                              const SizedBox(height: 20),

                              /* اختيار التاريخ */
                              InkWell(
                                onTap: _pickDate,
                                borderRadius: BorderRadius.circular(12),
                                child: InputDecorator(
                                  decoration: InputDecoration(
                                    labelText: 'اختر التاريخ',
                                    labelStyle:
                                        GoogleFonts.cairo(color: _primary),
                                    filled: true,
                                    fillColor: _fieldFill,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide.none,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        _date == null
                                            ? 'اضغط للاختيار'
                                            : DateFormat('yyyy-MM-dd')
                                                .format(_date!),
                                        style: GoogleFonts.cairo(
                                            color: Colors.black87),
                                      ),
                                      const Icon(Icons.calendar_today,
                                          color: _primary),
                                    ],
                                  ),
                                ),
                              ),
                              if (_date == null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Row(
                                    children: const [
                                      Icon(Icons.error,
                                          size: 16, color: Colors.red),
                                      SizedBox(width: 4),
                                      Text(
                                        'مطلوب',
                                        style: TextStyle(
                                          color: Colors.red,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              const SizedBox(height: 20),

                              /* وضع إعادة الامتحان */
                              CheckboxListTile(
                                value: _isRedo,
                                onChanged: (v) =>
                                    setState(() => _isRedo = v ?? false),
                                controlAffinity:
                                    ListTileControlAffinity.leading,
                                activeColor: _primary,
                                title: Text(
                                  'إعادة هذا الجزء (لا يؤثِّر على الخطة)',
                                  style: GoogleFonts.cairo(),
                                ),
                              ),
                              const SizedBox(height: 12),

                              /* زر الإرسال */
                              ElevatedButton(
                                onPressed: _busy ? null : _submit,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _primary,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 14),
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
          ),
        ),
      ),
    );
  }
}
