import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/auth_service.dart';
import 'login_page.dart';
import 'college_exam_requests_page.dart';
import '../features/admin/pending_scores_page.dart';
import 'college_students_page.dart';
import 'college_supervisors_page.dart';
import '../../college_theme.dart';
import 'college_parts_report_page.dart';
import '../services/dio_client.dart';
import 'college_plans_page.dart';

class AdminMedicalPage extends StatelessWidget {
  final String userName;
  const AdminMedicalPage({Key? key, required this.userName}) : super(key: key);

  void _logout(BuildContext ctx) async {
    await AuthService.clearToken();
    if (!ctx.mounted) return;
    Navigator.pushAndRemoveUntil(
      ctx,
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (r) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    const Color bgStart = Color(0xFFE0F2F1);
    const Color bgEnd = Color(0xFFB2DFDB);
    const Color btnStart = Color(0xFF00796B);
    const Color btnEnd = Color(0xFF26A69A);
    const List<Color> logoutGradient = [
      Color(0xFFD32F2F),
      Color(0xFFE57373),
    ];

    final w = MediaQuery.of(context).size.width;
    final isWide = w > 600;

    final actions = [
      _DashItem('📋 قائمة الطلاب', () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const CollegeStudentsPage(
              college: 'Medical',
              title: 'طلاب الطب',
              themeStart: Color(0xFF00796B),
              themeEnd: Color(0xFF26A69A),
            ),
          ),
        );
      }),
      _DashItem('👨‍🏫 المشرفون', () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const CollegeSupervisorsPage(
              college: 'Medical',
              title: 'مشرفو الطب',
              themeStart: Color(0xFF00796B),
              themeEnd: Color(0xFF26A69A),
            ),
          ),
        );
      }),
      _DashItem('📝 رصد العلامات', () {
        final th = CollegeTheme.medical;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PendingScoresPage(
              college: 'Medical',
              themeStart: th.start,
              themeEnd: th.end,
              bgLight: th.bgLight,
            ),
          ),
        );
      }),
      _DashItem('📑 كشف علامات الأجزاء', () {
        final th = CollegeTheme.medical;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => CollegePartsReportPage(
              college: 'Medical',
              themeStart: th.start,
              themeEnd: th.end,
              bgLight: th.bgLight,
            ),
          ),
        );
      }),
      _DashItem('🗺️ الخطط', () {
        final th = CollegeTheme.medical;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => CollegePlansPage(
              college: 'Medical',
              themeStart: th.start,
              themeEnd: th.end,
              bgLight: th.bgLight,
            ),
          ),
        );
      }),
      _DashItem('📨 طلبات الامتحانات', () {
        final th = CollegeTheme.medical;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => CollegeExamRequestsPage(
              college: 'Medical',
              themeStart: th.start,
              themeEnd: th.end,
              bgLight: th.bgLight,
            ),
          ),
        );
      }),
      _DashItem(
        '🔒 تعطيل/تفعيل تسجيل أجزاء الطب',
        () async {
          final college = 'Medical';
          final dio = DioClient().dio;
          final resp = await dio
              .get('/settings/part-exam-registration?college=$college');
          final data = resp.data;
          final bool isDisabled = data['disabledFrom'] != null &&
              DateTime.now().isAfter(DateTime.parse(data['disabledFrom'])
                  .subtract(const Duration(days: 1))) &&
              (data['disabledUntil'] == null ||
                  DateTime.now().isBefore(DateTime.parse(data['disabledUntil'])
                      .add(const Duration(days: 1))));

          if (isDisabled) {
            await dio.patch('/settings/part-exam-registration', data: {
              'college': college,
              'from': null,
              'until': null,
            });
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('تم تفعيل تسجيل الأجزاء للكلية'),
            ));
          } else {
            DateTimeRange? range = await showDateRangePicker(
              context: context,
              firstDate: DateTime.now(),
              lastDate: DateTime.now().add(const Duration(days: 365)),
              locale: const Locale('ar'),
            );
            if (range != null) {
              final adjustedEnd = range.end.add(const Duration(days: 1));
              await dio.patch('/settings/part-exam-registration', data: {
                'college': college,
                'from': range.start.toIso8601String().split('T').first,
                'until': adjustedEnd.toIso8601String().split('T').first,
              });
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('تم تعطيل تسجيل الأجزاء للفترة المحددة'),
              ));
            }
          }
        },
      ),
    ];

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: MediaQuery.of(context).size.height,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [bgStart, bgEnd],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
            child: Column(
              children: [
                // Top bar
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [btnStart, btnEnd],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ),
                    borderRadius: BorderRadius.only(
                      bottomLeft: Radius.circular(24),
                      bottomRight: Radius.circular(24),
                    ),
                  ),
                  child: Center(
                    child: Text(
                      'مسؤول مجمع الطب',
                      style: GoogleFonts.cairo(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                CircleAvatar(
                  radius: 50,
                  backgroundColor: Colors.white,
                  child: ClipOval(
                    child:
                        Image.asset('assets/logo1.png', width: 80, height: 80),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'أهلاً وسهلاً بك، $userName',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.cairo(
                    fontSize: isWide ? 26 : 20,
                    fontWeight: FontWeight.w600,
                    color: btnStart,
                  ),
                ),

                const SizedBox(height: 24),

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
                        gradient: const [btnStart, btnEnd],
                      ),
                    );
                  }).toList(),
                ),

                const SizedBox(height: 24),

                _ActionButton(
                  label: '📤 تصدير الشهادات',
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('جاري تنفيذ تصدير الشهادات...')),
                    );
                  },
                  gradient: const [btnStart, btnEnd],
                  icon: Icons.file_download,
                ),

                const SizedBox(height: 24),

                _ActionButton(
                  label: 'تسجيل الخروج',
                  onTap: () => _logout(context),
                  gradient: logoutGradient,
                  icon: Icons.logout,
                ),

                const SizedBox(height: 32),

                Text(
                  'الطب علم، والقرآن شفاء... اجمع بين العلم والشفاء',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.cairo(
                    fontStyle: FontStyle.italic,
                    color: btnStart.withOpacity(0.8),
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
