// lib/pages/admin_girls_dashboard_page.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/dio_client.dart';
import '../../services/auth_service.dart';

// الصفحات
import '../students_list_page.dart';
import '../users_and_supervisors_page.dart';
import '../HafadhListPage.dart';
import '../../features/admin/requests_list_page.dart';
import '../../features/admin/pending_scores_page.dart';
import '../all_exam_requests_page.dart';
import '../official_exam_report_page.dart';
import 'supervisor_change_requests_admin_page.dart';
import '../login_page.dart';

class AdminGirlsDashboardPage extends StatefulWidget {
  const AdminGirlsDashboardPage({super.key});

  static const _green = Color(0xff27ae60);
  static const _greenDark = Color(0xff219150);

  @override
  State<AdminGirlsDashboardPage> createState() =>
      _AdminGirlsDashboardPageState();
}

class _AdminGirlsDashboardPageState extends State<AdminGirlsDashboardPage> {
  // 🔒 هذه اللوحة خاصة بجهة الإناث
  static const String kGender = 'female';

  int _students = 0,
      _supervisors = 0,
      _regPending = 0,
      _examPending = 0,
      _scoresPending = 0,
      _hafidhCount = 0;

  bool _isDisabled = false;
  DateTime? _from, _until;

  @override
  void initState() {
    super.initState();
    AuthService.ensureValidOrLogout(context);
    _loadAllCounts();
    _loadExamRegStatus();
  }

  /// 🔹 جميع العدادات هنا «بنات فقط»
  Future<void> _loadAllCounts() async {
    try {
      final dio = DioClient().dio;
      const qp = {'gender': kGender}; // فلترة جهة الإناث

      final r1 = await dio.get('/students/count', queryParameters: qp);
      final r2 = await dio.get('/supervisors/count', queryParameters: qp);
      final r3 = await dio.get('/requests/count', queryParameters: qp);
      final r4 = await dio.get('/exam-requests/count', queryParameters: qp);
      final r5 = await dio.get('/scores/pending-count', queryParameters: qp);
      final r6 = await dio.get('/hafadh/count', queryParameters: qp);

      if (!mounted) return;
      setState(() {
        _students = (r1.data['count'] ?? 0) as int;
        _supervisors = (r2.data['count'] ?? 0) as int;
        _regPending = (r3.data['pending'] ?? 0) as int;
        _examPending = (r4.data['pending'] ?? 0) as int;
        _scoresPending = (r5.data['pending'] ?? 0) as int;
        _hafidhCount = (r6.data['count'] ?? 0) as int;
      });
    } catch (_) {
      // ممكن إضافة SnackBar عند الحاجة
    }
  }

  /// حالة تمكين/تعطيل تسجيل الامتحان الرسمي — «بنات فقط»
  Future<void> _loadExamRegStatus() async {
    try {
      final resp = await DioClient().dio.get(
        '/settings/exam-registration',
        queryParameters: {'gender': kGender},
      );
      final data = resp.data as Map<String, dynamic>;
      final now = DateTime.now();
      setState(() {
        _from = data['disabledFrom'] != null
            ? DateTime.parse(data['disabledFrom'])
            : null;
        _until = data['disabledUntil'] != null
            ? DateTime.parse(data['disabledUntil'])
            : null;
        _isDisabled = _from != null &&
            now.isAfter(_from!.subtract(const Duration(days: 1))) &&
            (_until == null ||
                now.isBefore(_until!.add(const Duration(days: 1))));
      });
    } catch (_) {
      // تجاهل بهدوء
    }
  }

  Future<void> _toggleExamReg() async {
    try {
      final dio = DioClient().dio;
      if (_isDisabled) {
        // تفعيل التسجيل (إلغاء التعطيل)
        await dio.patch(
          '/settings/exam-registration',
          queryParameters: {'gender': kGender},
          data: {'from': null, 'until': null},
        );
      } else {
        // تعطيل التسجيل: اختيار فترة
        final range = await showDateRangePicker(
          context: context,
          firstDate: DateTime.now(),
          lastDate: DateTime.now().add(const Duration(days: 365)),
          locale: const Locale('ar'),
        );
        if (range == null) return;

        // نضيف يوم لنهاية النطاق حتى تشمل اليوم بالكامل
        final adjustedEnd = range.end.add(const Duration(days: 1));
        await dio.patch(
          '/settings/exam-registration',
          queryParameters: {'gender': kGender},
          data: {
            'from': range.start.toIso8601String().split('T').first,
            'until': adjustedEnd.toIso8601String().split('T').first,
          },
        );
      }
      await _loadExamRegStatus();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر تغيير حالة التسجيل')),
        );
      }
    }
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (_) => false,
    );
  }

  // الأزرار الرئيسية (نفس التي في الكود الجديد)
  late final List<_DashItem> _actions = [
    _DashItem(Icons.list_alt, 'قائمة الطالبات', (ctx) {
      Navigator.push(
          ctx, MaterialPageRoute(builder: (_) => const StudentsListPage()));
    }),
    _DashItem(Icons.people_outline, 'المسؤولات والمشرفات', (ctx) {
      Navigator.push(ctx,
          MaterialPageRoute(builder: (_) => const UsersAndSupervisorsPage()));
    }),
    _DashItem(Icons.verified_user, 'الحافظات', (ctx) {
      Navigator.push(
          ctx, MaterialPageRoute(builder: (_) => const HafadhListPage()));
    }),
    _DashItem(Icons.mark_email_unread, 'طلبات التسجيل', (ctx) async {
      await Navigator.push(
          ctx, MaterialPageRoute(builder: (_) => const RequestsListPage()));
      _loadAllCounts(); // تحدّث المربعات بعد الرجوع
    }, badge: () => _regPending),
    _DashItem(Icons.mail_outline, 'طلبات الامتحانات', (ctx) {
      Navigator.push(
          ctx, MaterialPageRoute(builder: (_) => const AllExamRequestsPage()));
    }, badge: () => _examPending),
    _DashItem(Icons.grade, 'رصد العلامات', (ctx) {
      Navigator.push(
          ctx,
          MaterialPageRoute(
              builder: (_) => const PendingScoresPage(allColleges: true)));
    }, badge: () => _scoresPending),
    _DashItem(Icons.swap_horiz, 'طلبات تغيير المشرفة', (ctx) {
      Navigator.push(
          ctx,
          MaterialPageRoute(
              builder: (_) => const SupervisorChangeRequestsAdminPage()));
    }),
    _DashItem(Icons.bar_chart, 'كشف العلامات الرسمية', (ctx) {
      Navigator.push(ctx,
          MaterialPageRoute(builder: (_) => const OfficialExamReportPage()));
    }),
  ];

  Widget _summaryCard(IconData icon, String label, int value) => Container(
        width: 140,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [
            AdminGirlsDashboardPage._green,
            AdminGirlsDashboardPage._greenDark
          ]),
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [
            BoxShadow(
                color: Colors.black26, blurRadius: 6, offset: Offset(0, 4))
          ],
        ),
        child: Column(
          children: [
            Icon(icon, color: Colors.white, size: 32),
            const SizedBox(height: 6),
            Text('$value',
                style: GoogleFonts.cairo(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(label,
                style: GoogleFonts.cairo(color: Colors.white70, fontSize: 12)),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final isWide = w > 800;

    final toggleText = _isDisabled
        ? 'تفعيل تسجيل الامتحان الرسمي'
        : (_from != null && _until != null
            ? 'تعطيل من ${DateFormat('yyyy-MM-dd').format(_from!)} إلى ${DateFormat('yyyy-MM-dd').format(_until!)}'
            : 'تعطيل تسجيل الامتحان الرسمي');

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
              colors: [Color(0xffe8f5e9), Color(0xfff0faf2)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Header (نفس شكل القديم، مع النص المطلوب)
              Container(
                padding:
                    const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(colors: [
                    AdminGirlsDashboardPage._green,
                    AdminGirlsDashboardPage._greenDark
                  ]),
                  borderRadius:
                      BorderRadius.vertical(bottom: Radius.circular(24)),
                ),
                child: Center(
                  child: Text('ملتقى القران الكريم',
                      style: GoogleFonts.cairo(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 24)),
                ),
              ),

              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      ClipOval(
                        child: Container(
                          color: Colors.white,
                          padding: const EdgeInsets.all(12),
                          child: Image.asset('assets/logo1.png',
                              width: 100, height: 100),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // ─── المربعات الستة (بنات فقط) ───
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 20,
                        runSpacing: 20,
                        children: [
                          _summaryCard(Icons.school, 'طالبات', _students),
                          _summaryCard(
                              Icons.supervisor_account, 'مشرفات', _supervisors),
                          _summaryCard(
                              Icons.verified_user, 'حافظات', _hafidhCount),
                          _summaryCard(Icons.mark_email_unread,
                              'تسجيلات معلّقة', _regPending),
                          _summaryCard(
                              Icons.mail, 'امتحانات معلّقة', _examPending),
                          _summaryCard(
                              Icons.star, 'علامات معلّقة', _scoresPending),
                        ],
                      ),
                      const SizedBox(height: 28),

                      // الأزرار (تصميم القديم)
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 24,
                        runSpacing: 24,
                        children: _actions.map((item) {
                          final badgeVal = item.badge?.call() ?? 0;
                          return SizedBox(
                            width: isWide ? 280 : double.infinity,
                            child:
                                _ActionButton(item: item, badgeVal: badgeVal),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 34),

                      // زر تعطيل/تفعيل تسجيل الرسمي (مثل القديم)
                      SizedBox(
                        width: isWide ? 360 : double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _toggleExamReg,
                          icon:
                              Icon(_isDisabled ? Icons.lock_open : Icons.lock),
                          label: Text(toggleText,
                              style: GoogleFonts.cairo(
                                  fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                _isDisabled ? Colors.green : Colors.redAccent,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // زر تسجيل الخروج (مثل القديم)
                      SizedBox(
                        width: isWide ? 300 : double.infinity,
                        height: 52,
                        child: ElevatedButton.icon(
                          onPressed: _logout,
                          icon: const Icon(Icons.logout, color: Colors.white),
                          label: Text('تسجيل الخروج',
                              style: GoogleFonts.cairo(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xffc62828),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(30)),
                            elevation: 8,
                          ),
                        ),
                      ),
                    ],
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

class _DashItem {
  final IconData icon;
  final String title;
  final void Function(BuildContext) onTap;
  final int Function()? badge;
  const _DashItem(this.icon, this.title, this.onTap, {this.badge});
}

class _ActionButton extends StatelessWidget {
  final _DashItem item;
  final int badgeVal;
  const _ActionButton({required this.item, required this.badgeVal});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => item.onTap(context),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [
              AdminGirlsDashboardPage._green,
              AdminGirlsDashboardPage._greenDark
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [
            BoxShadow(
                color: Colors.black26, blurRadius: 6, offset: Offset(0, 4))
          ],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(item.icon, size: 32, color: Colors.white),
                const SizedBox(height: 8),
                Text(item.title,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.cairo(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.white)),
              ],
            ),
            if (badgeVal > 0)
              Positioned(
                right: 8,
                top: 8,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                      color: Colors.redAccent,
                      borderRadius: BorderRadius.circular(12)),
                  child: Text('$badgeVal',
                      style: GoogleFonts.cairo(
                          color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
