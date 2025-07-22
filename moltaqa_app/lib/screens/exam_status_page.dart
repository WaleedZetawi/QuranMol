// lib/pages/exam_status_page.dart

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../services/api_config.dart';
import '../../services/auth_service.dart';

class ExamStatusPage extends StatefulWidget {
  const ExamStatusPage({Key? key}) : super(key: key);
  @override
  State<ExamStatusPage> createState() => _ExamStatusPageState();
}

class _ExamStatusPageState extends State<ExamStatusPage>
    with TickerProviderStateMixin {
  bool _busy = true;
  List _rows = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _busy = true);
    final token = await AuthService.token ?? '';
    try {
      final r = await Dio().get(
        '${ApiConfig.baseUrl}/my-exam-requests',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      if (mounted) setState(() => _rows = r.data as List);
    } catch (_) {}
    if (mounted) setState(() => _busy = false);
  }

  static const Color _bgStart = Color(0xFFE8F5E9);
  static const Color _bgEnd = Color(0xFF66BB6A);
  static const Color _cardColor = Colors.white;
  static const Color _primary = Color(0xFF2E7D32);

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
          child: NestedScrollView(
            headerSliverBuilder: (ctx, innerScrolled) => [
              SliverAppBar(
                backgroundColor: Colors.transparent,
                elevation: 0,
                expandedHeight: 200,
                floating: false,
                pinned: false,
                automaticallyImplyLeading: false, // نحذف الـ leading الافتراضي
                flexibleSpace: FlexibleSpaceBar(
                  collapseMode: CollapseMode.pin,
                  background: Stack(
                    children: [
                      // زر الرجوع باليمين
                      Positioned(
                        top: 8,
                        right: 8,
                        child: IconButton(
                          icon: const Icon(Icons.arrow_back, color: _primary),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ),
                      // اللوجو والعنوان في الوسط
                      Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Image.asset(
                              'assets/logo1.png',
                              width: 120,
                              height: 120,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'حالة الطلبات / الامتحانات',
                              style: GoogleFonts.cairo(
                                color: _primary,
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            body: _busy
                ? const Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(_primary),
                    ),
                  )
                : _rows.isEmpty
                ? Center(
                    child: Text(
                      'لا توجد طلبات حتى الآن',
                      style: GoogleFonts.cairo(
                        color: _primary.withOpacity(0.7),
                        fontSize: 16,
                      ),
                    ),
                  )
                : AnimationLimiter(
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      itemCount: _rows.length,
                      itemBuilder: (ctx, i) {
                        final e = _rows[i] as Map;

                        // تنسيق التاريخ
                        String dateText = '-';
                        if (e['exam_date'] != null) {
                          final dt = DateTime.parse(e['exam_date']);
                          dateText = DateFormat('yyyy‑MM‑dd').format(dt);
                        }

                        // الحالة
                        final bool? ok = e['approved'];
                        final icon = ok == null
                            ? Icons.hourglass_top
                            : ok
                            ? Icons.check_circle
                            : Icons.cancel;
                        final color = ok == null
                            ? Colors.orange
                            : ok
                            ? Colors.green
                            : Colors.red;
                        final status = ok == null
                            ? 'قيد المراجعة'
                            : ok
                            ? 'مقبول'
                            : 'مرفوض';

                        // بيانات إضافية
                        final isOfficial = e['kind'] == 'official';
                        final supName = e['supervisor_name'];
                        final trialSup = e['trial_supervisor'];
                        final doctorSup = e['doctor_supervisor'];

                        return AnimationConfiguration.staggeredList(
                          position: i,
                          duration: const Duration(milliseconds: 700),
                          child: SlideAnimation(
                            verticalOffset: 50,
                            curve: Curves.easeOutCubic,
                            child: FadeInAnimation(
                              child: Card(
                                color: _cardColor,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                margin: const EdgeInsets.symmetric(vertical: 8),
                                elevation: 6,
                                child: ListTile(
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 12,
                                  ),
                                  leading: CircleAvatar(
                                    backgroundColor: color.withOpacity(0.2),
                                    child: Icon(icon, color: color),
                                  ),
                                  title: Text(
                                    e['display'],
                                    style: GoogleFonts.cairo(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: _primary,
                                    ),
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const SizedBox(height: 4),
                                      Text(
                                        'التاريخ: $dateText',
                                        style: GoogleFonts.cairo(fontSize: 14),
                                      ),
                                      if (supName != null)
                                        Text(
                                          'المشرف: $supName',
                                          style: GoogleFonts.cairo(
                                            fontSize: 14,
                                          ),
                                        ),
                                      if (isOfficial && trialSup != null)
                                        Text(
                                          'مشرف تجريبي: $trialSup',
                                          style: GoogleFonts.cairo(
                                            fontSize: 14,
                                          ),
                                        ),
                                      if (isOfficial && doctorSup != null)
                                        Text(
                                          'الدكتور: $doctorSup',
                                          style: GoogleFonts.cairo(
                                            fontSize: 14,
                                          ),
                                        ),
                                    ],
                                  ),
                                  trailing: Text(
                                    status,
                                    style: GoogleFonts.cairo(
                                      fontWeight: FontWeight.w600,
                                      color: color,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
