import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/dio_client.dart';
import '../../services/auth_service.dart';

import '../login_page.dart';
import '../college_students_page.dart';
import '../college_supervisors_page.dart';
import '../college_parts_report_page.dart';
import '../college_exam_requests_page.dart';
import '../college_plans_page.dart'; // ✅ زر الخطط
import '../../features/admin/pending_scores_page.dart';

class AdminGirlsPage extends StatelessWidget {
  final String collegeCode; // NewCampus | OldCampus | Agriculture
  final String title; // مثال: "مسؤولة الحرم الجديد"
  final Color start; // لون التدرّج (غامق)
  final Color end; // لون التدرّج (فاتح)
  final Color bg; // خلفية الصفحة الفاتحة
  final String userName; // اسم المسؤولة لرسالة الترحيب

  const AdminGirlsPage({
    super.key,
    required this.collegeCode,
    required this.title,
    required this.start,
    required this.end,
    required this.bg,
    required this.userName,
  });

  Future<void> _togglePartReg(BuildContext context) async {
    final dio = DioClient().dio;
    try {
      final r = await dio.get('/settings/part-exam-registration',
          queryParameters: {'college': collegeCode});
      final data = r.data as Map<String, dynamic>;
      final disabledFrom = data['disabledFrom'];
      final disabledUntil = data['disabledUntil'];
      final now = DateTime.now();
      final isDisabled = disabledFrom != null &&
          now.isAfter(
              DateTime.parse(disabledFrom).subtract(const Duration(days: 1))) &&
          (disabledUntil == null ||
              now.isBefore(
                  DateTime.parse(disabledUntil).add(const Duration(days: 1))));

      if (isDisabled) {
        await dio.patch('/settings/part-exam-registration',
            data: {'college': collegeCode, 'from': null, 'until': null});
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('تم تفعيل تسجيل الأجزاء لـ $title',
                    style: GoogleFonts.cairo())),
          );
        }
      } else {
        final range = await showDateRangePicker(
          context: context,
          firstDate: DateTime.now(),
          lastDate: DateTime.now().add(const Duration(days: 365)),
          locale: const Locale('ar'),
        );
        if (range == null) return;
        final adjustedEnd = range.end.add(const Duration(days: 1));
        await dio.patch('/settings/part-exam-registration', data: {
          'college': collegeCode,
          'from': range.start.toIso8601String().split('T').first,
          'until': adjustedEnd.toIso8601String().split('T').first,
        });
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('تم تعطيل تسجيل الأجزاء للفترة المحددة',
                    style: GoogleFonts.cairo())),
          );
        }
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text('تعذر تغيير حالة التسجيل', style: GoogleFonts.cairo())),
        );
      }
    }
  }

  Future<void> _logout(BuildContext ctx) async {
    await AuthService.clearToken();
    if (!ctx.mounted) return;
    Navigator.pushAndRemoveUntil(
      ctx,
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    // نفس حسابات الأبعاد في صفحة الهندسة
    final w = MediaQuery.of(context).size.width;
    final isWide = w > 600;
    const logoutGradient = <Color>[Color(0xFFD32F2F), Color(0xFFE57373)];

    final actions = <_DashItem>[
      _DashItem('📋 قائمة الطالبات', () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => CollegeStudentsPage(
              college: collegeCode,
              title: 'طالبات $title',
              themeStart: start,
              themeEnd: end,
            ),
          ),
        );
      }),
      _DashItem('👩‍🏫 المشرفات', () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => CollegeSupervisorsPage(
              college: collegeCode,
              title: 'مشرفات $title',
              themeStart: start,
              themeEnd: end,
            ),
          ),
        );
      }),
      _DashItem('📝 رصد العلامات', () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PendingScoresPage(
              college: collegeCode,
              themeStart: start,
              themeEnd: end,
              bgLight: bg,
            ),
          ),
        );
      }),
      _DashItem('📑 كشف علامات الأجزاء', () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => CollegePartsReportPage(
              college: collegeCode,
              themeStart: start,
              themeEnd: end,
              bgLight: bg,
            ),
          ),
        );
      }),
      // ✅ الزر اللي كان ناقص
      _DashItem('🗺️ الخطط', () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => CollegePlansPage(
              college: collegeCode,
              themeStart: start,
              themeEnd: end,
              bgLight: bg,
            ),
          ),
        );
      }),
      _DashItem('📨 طلبات الامتحانات', () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => CollegeExamRequestsPage(
              college: collegeCode,
              themeStart: start,
              themeEnd: end,
              bgLight: bg,
            ),
          ),
        );
      }),
      _DashItem(
          '🔒 تعطيل/تفعيل تسجيل أجزاء الكلية', () => _togglePartReg(context)),
    ];

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: MediaQuery.of(context).size.height,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [bg, Colors.white],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
            child: Column(
              children: [
                // العنوان (نفس ستايل الهندسة)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [start, end],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ),
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(24),
                      bottomRight: Radius.circular(24),
                    ),
                  ),
                  child: Center(
                    child: Text(
                      title,
                      style: GoogleFonts.cairo(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // الشعار + الترحيب
                CircleAvatar(
                  radius: 50,
                  backgroundColor: Colors.white,
                  child: Image.asset('assets/logo1.png', width: 80, height: 80),
                ),
                const SizedBox(height: 16),
                Text(
                  'أهلًا وسهلًا بكِ، $userName',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.cairo(
                    fontSize: isWide ? 26 : 20,
                    fontWeight: FontWeight.w600,
                    color: start,
                  ),
                ),

                const SizedBox(height: 24),

                // شبكة الأزرار بنفس الأبعاد
                Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  alignment: WrapAlignment.center,
                  children: actions.map((a) {
                    return SizedBox(
                      width: isWide ? (w - 96) / 3 : double.infinity,
                      child: _ActionButton(
                        label: a.title,
                        onTap: a.onTap,
                        gradient: [start, end],
                      ),
                    );
                  }).toList(),
                ),

                const SizedBox(height: 24),

                // (اختياري) تصدير الشهادات – إذا بدك نفس زر الهندسة بالضبط خلّيه
                _ActionButton(
                  label: '📤 تصدير الشهادات',
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('سيتم لاحقًا إن شاء الله')),
                    );
                  },
                  gradient: [start, end],
                  icon: Icons.file_download,
                ),

                const SizedBox(height: 24),

                // تسجيل الخروج بنفس شكل الهندسة (أحمر متدرّج)
                _ActionButton(
                  label: 'تسجيل الخروج',
                  onTap: () => _logout(context),
                  gradient: logoutGradient,
                  icon: Icons.logout,
                ),

                const SizedBox(height: 32),

                Text(
                  'بالقرآن نسمو، وبخدمتكن نزداد أثرًا.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.cairo(
                    fontStyle: FontStyle.italic,
                    color: start.withOpacity(0.8),
                    fontSize: 16,
                  ),
                ),

                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DashItem {
  final String title;
  final VoidCallback onTap;
  const _DashItem(this.title, this.onTap);
}

class _ActionButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final List<Color> gradient;
  final IconData? icon;
  const _ActionButton({
    super.key,
    required this.label,
    required this.onTap,
    required this.gradient,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: gradient,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [
            BoxShadow(
                color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, color: Colors.white),
              const SizedBox(width: 8),
            ],
            Text(
              label,
              style: GoogleFonts.cairo(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
