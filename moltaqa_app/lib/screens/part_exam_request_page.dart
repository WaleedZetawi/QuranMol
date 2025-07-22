import 'dart:math';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/api_config.dart';

class PartExamRequestPage extends StatefulWidget {
  const PartExamRequestPage({Key? key}) : super(key: key);
  @override
  State<PartExamRequestPage> createState() => _PartExamRequestPageState();
}

class _PartExamRequestPageState extends State<PartExamRequestPage>
    with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  int? _juz;
  DateTime? _date;
  bool _busy = false;

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
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeIn);
    _fadeCtrl.forward();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  Future<String> _getToken() async =>
      (await SharedPreferences.getInstance()).getString('token') ?? '';

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

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() || _date == null) return;
    setState(() => _busy = true);
    final token = await _getToken();
    try {
      await Dio(BaseOptions(headers: {'Authorization': 'Bearer $token'})).post(
        '${ApiConfig.baseUrl}/exam-requests',
        data: {
          'kind': 'part',
          'part': _juz,
          // استعمال التنسيق ASCII hyphen
          'date': DateFormat('yyyy-MM-dd').format(_date!),
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
                // زر رجوع في الأعلى يمين
                Align(
                  alignment: Alignment.topRight,
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back, color: _primary),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),

                // لوجو أكبر ومركّز
                Padding(
                  padding: const EdgeInsets.only(top: 16.0, bottom: 8.0),
                  child: Center(
                    child: Image.asset(
                      'assets/logo1.png',
                      width: 140,
                      height: 140,
                    ),
                  ),
                ),

                // النموذج داخل البطاقة
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

                              // Dropdown اختيار الجزء
                              DropdownButtonFormField<int>(
                                value: _juz,
                                iconEnabledColor: _primary,
                                decoration: InputDecoration(
                                  labelText: 'اختر الجزء',
                                  labelStyle: GoogleFonts.cairo(
                                    color: _primary,
                                  ),
                                  filled: true,
                                  fillColor: _fieldFill,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide.none,
                                  ),
                                ),
                                items: List.generate(
                                  30,
                                  (i) => DropdownMenuItem(
                                    value: i + 1,
                                    child: Text(
                                      'الجزء ${i + 1}',
                                      style: GoogleFonts.cairo(),
                                    ),
                                  ),
                                ),
                                validator: (v) => v == null ? 'مطلوب' : null,
                                onChanged: (v) => setState(() => _juz = v),
                              ),
                              const SizedBox(height: 20),

                              // اختيار التاريخ
                              InkWell(
                                onTap: _pickDate,
                                borderRadius: BorderRadius.circular(12),
                                child: InputDecorator(
                                  decoration: InputDecoration(
                                    labelText: 'اختر التاريخ',
                                    labelStyle: GoogleFonts.cairo(
                                      color: _primary,
                                    ),
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
                                            : DateFormat(
                                                'yyyy-MM-dd',
                                              ).format(_date!),
                                        style: GoogleFonts.cairo(
                                          color: Colors.black87,
                                        ),
                                      ),
                                      Icon(
                                        Icons.calendar_today,
                                        color: _primary,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              if (_date == null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Row(
                                    children: const [
                                      Icon(
                                        Icons.error,
                                        size: 16,
                                        color: Colors.red,
                                      ),
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
                              const SizedBox(height: 28),

                              // زرّ الإرسال
                              ElevatedButton(
                                onPressed: _busy ? null : _submit,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _primary,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
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
