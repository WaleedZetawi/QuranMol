import 'dart:math';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';

import '../../services/api_config.dart';
import 'students_list_page.dart';
import 'users_and_supervisors_page.dart';
import 'HafadhListPage.dart';
import 'login_page.dart';
import 'all_exam_requests_page.dart';
import '../features/admin/requests_list_page.dart';
import '../features/admin/pending_scores_page.dart';

class AdminDashboardPage extends StatefulWidget {
  const AdminDashboardPage({super.key});
  static const _green = Color(0xff27ae60);
  static const _greenDark = Color(0xff219150);

  @override
  State<AdminDashboardPage> createState() => _AdminDashboardPageState();
}

class _AdminDashboardPageState extends State<AdminDashboardPage> {
  int _students = 0,
      _supervisors = 0,
      _regPending = 0,
      _examPending = 0,
      _scoresPending = 0,
      _hafidhCount = 0; // ← عدد الحفاظ

  @override
  void initState() {
    super.initState();
    _loadAllCounts();
  }

  Future<void> _loadAllCounts() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token') ?? '';
    final opts = Options(headers: {'Authorization': 'Bearer $token'});

    try {
      final r1 = await Dio().get(
        '${ApiConfig.baseUrl}/students/count',
        options: opts,
      );
      final r2 = await Dio().get(
        '${ApiConfig.baseUrl}/supervisors/count',
        options: opts,
      );
      final r3 = await Dio().get(
        '${ApiConfig.baseUrl}/requests/count',
        options: opts,
      );
      final r4 = await Dio().get(
        '${ApiConfig.baseUrl}/exam-requests/count',
        options: opts,
      );
      final r5 = await Dio().get(
        '${ApiConfig.baseUrl}/scores/pending-count',
        options: opts,
      );
      final r6 = await Dio().get(
        '${ApiConfig.baseUrl}/hafadh/count',
        options: opts,
      ); // ← جديد

      if (!mounted) return;
      setState(() {
        _students = r1.data['count'];
        _supervisors = r2.data['count'];
        _regPending = r3.data['pending'];
        _examPending = r4.data['pending'];
        _scoresPending = r5.data['pending'];
        _hafidhCount = r6.data['count']; // ← خزن الناتج
      });
    } catch (_) {
      // يمكن إضافة handling إذا أحببت
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

  late final List<_DashItem> _actions = [
    _DashItem(Icons.list_alt, 'قائمة الطلاب', (ctx) {
      Navigator.push(
        ctx,
        MaterialPageRoute(builder: (_) => const StudentsListPage()),
      );
    }),
    _DashItem(Icons.people_outline, 'المسؤولون والمشرفون', (ctx) {
      Navigator.push(
        ctx,
        MaterialPageRoute(builder: (_) => const UsersAndSupervisorsPage()),
      );
    }),
    _DashItem(Icons.verified_user, 'حُفّاظ الملتقى', (ctx) {
      Navigator.push(
        ctx,
        MaterialPageRoute(builder: (_) => const HafadhListPage()),
      );
    }),
    _DashItem(Icons.mark_email_unread, 'طلبات التسجيل', (ctx) async {
      await Navigator.push(
        ctx,
        MaterialPageRoute(builder: (_) => const RequestsListPage()),
      );
      _loadAllCounts();
    }, badge: () => _regPending),
    _DashItem(Icons.mail_outline, 'طلبات الامتحانات', (ctx) {
      Navigator.push(
        ctx,
        MaterialPageRoute(builder: (_) => const AllExamRequestsPage()),
      );
    }, badge: () => _examPending),
    _DashItem(Icons.grade, 'رصد العلامات', (ctx) {
      Navigator.push(
        ctx,
        MaterialPageRoute(
          builder: (_) => const PendingScoresPage(allColleges: true),
        ),
      );
    }, badge: () => _scoresPending),
  ];

  Widget _buildSummaryCard(IconData icon, String label, int value) {
    return Container(
      width: 140,
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xff27ae60), Color(0xff219150)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 4)),
        ],
      ),
      child: Column(
        children: [
          Icon(icon, size: 32, color: Colors.white),
          const SizedBox(height: 8),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: value.toDouble()),
            duration: const Duration(milliseconds: 800),
            builder: (_, val, __) => Text(
              val.toInt().toString(),
              style: GoogleFonts.cairo(
                textStyle: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: GoogleFonts.cairo(
              textStyle: const TextStyle(fontSize: 12, color: Colors.white70),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final isWide = w > 800;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xffe8f5e9), Color(0xfff0faf2)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            tileMode: TileMode.mirror,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // AppBar مخصّص
              Container(
                padding: const EdgeInsets.symmetric(
                  vertical: 16,
                  horizontal: 24,
                ),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xff27ae60), Color(0xff219150)],
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
                    'ملتقى القرآن الكريم',
                    style: GoogleFonts.cairo(
                      textStyle: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),

              Expanded(
                child: AnimationLimiter(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // الشعار
                        ClipOval(
                          child: Container(
                            color: Colors.white,
                            padding: const EdgeInsets.all(12),
                            child: Image.asset(
                              'assets/logo1.png',
                              width: 100,
                              height: 100,
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),

                        // ** ملخّص الإحصائيات **
                        Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 20,
                          runSpacing: 20,
                          children: AnimationConfiguration.toStaggeredList(
                            duration: const Duration(milliseconds: 600),
                            childAnimationBuilder: (widget) => SlideAnimation(
                              horizontalOffset: 50,
                              child: FadeInAnimation(child: widget),
                            ),
                            children: [
                              _buildSummaryCard(
                                Icons.school,
                                'طلاب',
                                _students,
                              ),
                              _buildSummaryCard(
                                Icons.supervisor_account,
                                'مشرفون',
                                _supervisors,
                              ),
                              _buildSummaryCard(
                                Icons.verified_user,
                                'حُفّاظ',
                                _hafidhCount,
                              ), // ← هذا
                              _buildSummaryCard(
                                Icons.mark_email_unread,
                                'تسجيلات معلّقة',
                                _regPending,
                              ),
                              _buildSummaryCard(
                                Icons.mail,
                                'امتحانات معلّقة',
                                _examPending,
                              ),
                              _buildSummaryCard(
                                Icons.star,
                                'علامات معلّقة',
                                _scoresPending,
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 32),

                        // ** أزرار الإجراءات **
                        Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 24,
                          runSpacing: 24,
                          children: AnimationConfiguration.toStaggeredList(
                            duration: const Duration(milliseconds: 800),
                            childAnimationBuilder: (widget) => SlideAnimation(
                              verticalOffset: 50,
                              child: FadeInAnimation(child: widget),
                            ),
                            children: _actions.map((item) {
                              final badgeVal = item.badge?.call() ?? 0;
                              return SizedBox(
                                width: isWide ? 280 : double.infinity,
                                child: _ActionButton(
                                  item: item,
                                  badgeVal: badgeVal,
                                ),
                              );
                            }).toList(),
                          ),
                        ),

                        const SizedBox(height: 40),

                        // زر تسجيل الخروج
                        SizedBox(
                          width: isWide ? 300 : double.infinity,
                          height: 52,
                          child: ElevatedButton.icon(
                            onPressed: _logout,
                            icon: const Icon(
                              Icons.logout,
                              size: 24,
                              color: Colors.white,
                            ),
                            label: Text(
                              'تسجيل الخروج',
                              style: GoogleFonts.cairo(
                                textStyle: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xffc62828),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(30),
                              ),
                              elevation: 8,
                              shadowColor: Colors.black38,
                            ),
                          ),
                        ),
                      ],
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
            colors: [Color(0xff27ae60), Color(0xff219150)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 6,
              offset: Offset(0, 4),
            ),
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
                Text(
                  item.title,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.cairo(
                    textStyle: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            if (badgeVal > 0)
              Positioned(
                right: 8,
                top: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.redAccent,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: 4,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Text(
                    badgeVal.toString(),
                    style: GoogleFonts.cairo(
                      textStyle: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
