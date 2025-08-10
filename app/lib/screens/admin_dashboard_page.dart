import 'dart:math';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';

import 'official_exam_report_page.dart';
import '../../services/api_config.dart';
import '../services/dio_client.dart';
import '../../services/auth_service.dart';
import 'students_list_page.dart';
import 'users_and_supervisors_page.dart';
import 'HafadhListPage.dart';
import 'login_page.dart';
import 'all_exam_requests_page.dart';
import '../features/admin/requests_list_page.dart';
import '../features/admin/pending_scores_page.dart';
import '../features/admin/supervisor_change_requests_male_page.dart';
import 'package:intl/intl.dart';

class AdminDashboardPage extends StatefulWidget {
  const AdminDashboardPage({super.key});
  static const _green = Color(0xff27ae60);
  static const _greenDark = Color(0xff219150);

  @override
  State<AdminDashboardPage> createState() => _AdminDashboardPageState();
}

class _AdminDashboardPageState extends State<AdminDashboardPage> {
  // 🔒 هذا اللوح خاص بجهة الذكور
  static const String kGender = 'male';

  // Counters
  int _students = 0,
      _supervisors = 0,
      _regPending = 0,
      _examPending = 0,
      _scoresPending = 0,
      _hafidhCount = 0,
      _supChangePending = 0;

  // null = لسه ما عرفنا، true = مسموح، false = غير مسموح
  bool? _canSeeSupChange;

  // Disable toggle state
  bool _isDisabled = false;
  DateTime? _from; // تاريخ بدء التعطيل
  DateTime? _until; // تاريخ انتهاء التعطيل

  @override
  void initState() {
    super.initState();
    AuthService.ensureValidOrLogout(context);
    _loadAllCounts();
    _loadExamRegStatus();
  }

  Future<void> _loadAllCounts() async {
    try {
      final dio = DioClient().dio;
      final qp = {'gender': kGender};

      final r1 = await dio.get('/students/count', queryParameters: qp);
      final r2 = await dio.get('/supervisors/count', queryParameters: qp);
      final r3 = await dio.get('/requests/count', queryParameters: qp);
      final r4 = await dio.get('/exam-requests/count', queryParameters: qp);
      final r5 = await dio.get('/scores/pending-count', queryParameters: qp);
      final r6 = await dio.get('/hafadh/count', queryParameters: qp);

      int supChange = 0;
      bool? canSee;
      try {
        final r7 = await dio.get('/supervisor-change-requests');
        final list = List<Map<String, dynamic>>.from(
          r7.data ?? const <Map<String, dynamic>>[],
        );
        supChange = list.length;
        canSee = true;
      } catch (_) {
        canSee = false;
        supChange = 0;
      }

      if (!mounted) return;
      setState(() {
        _students = (r1.data['count'] ?? 0) as int;
        _supervisors = (r2.data['count'] ?? 0) as int;
        _regPending = (r3.data['pending'] ?? 0) as int;
        _examPending = (r4.data['pending'] ?? 0) as int;
        _scoresPending = (r5.data['pending'] ?? 0) as int;
        _hafidhCount = (r6.data['count'] ?? 0) as int;
        _supChangePending = supChange;
        _canSeeSupChange = canSee; // <— ما منعيد أي موشن، بس منبدّل المحتوى
      });
    } catch (e) {
      debugPrint('loadCounts error: $e');
    }
  }

  Future<void> _loadExamRegStatus() async {
    try {
      final resp = await DioClient().dio.get(
        '/settings/exam-registration',
        queryParameters: {'gender': kGender},
      );
      final data = resp.data;
      setState(() {
        _from = data['disabledFrom'] != null
            ? DateTime.parse(data['disabledFrom'])
            : null;
        _until = data['disabledUntil'] != null
            ? DateTime.parse(data['disabledUntil'])
            : null;

        final now = DateTime.now();
        _isDisabled = _from != null &&
            now.isAfter(_from!.subtract(const Duration(days: 1))) &&
            (_until == null ||
                now.isBefore(_until!.add(const Duration(days: 1))));
      });
    } catch (e) {
      debugPrint('loadExamRegStatus error: $e');
    }
  }

  Future<void> _toggleExamReg() async {
    try {
      final dio = DioClient().dio;
      if (_isDisabled) {
        await dio.patch(
          '/settings/exam-registration',
          queryParameters: {'gender': kGender},
          data: {'from': null, 'until': null},
        );
      } else {
        final range = await showDateRangePicker(
          context: context,
          firstDate: DateTime.now(),
          lastDate: DateTime.now().add(const Duration(days: 365)),
          locale: const Locale('ar'),
        );
        if (range == null) return;

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
    } catch (e) {
      debugPrint('toggleExamReg error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('حصل خطأ أثناء تغيير حالة التسجيل')),
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

  // أزرار ثابتة الطول (بدون كبسة تغيير المشرف)
  late final List<_DashItem> _baseActions = [
    _DashItem(Icons.list_alt, 'قائمة الطلاب', (ctx) {
      Navigator.push(
          ctx, MaterialPageRoute(builder: (_) => const StudentsListPage()));
    }),
    _DashItem(Icons.people_outline, 'المسؤولون والمشرفون', (ctx) {
      Navigator.push(ctx,
          MaterialPageRoute(builder: (_) => const UsersAndSupervisorsPage()));
    }),
    _DashItem(Icons.verified_user, 'حُفّاظ الملتقى', (ctx) {
      Navigator.push(
          ctx, MaterialPageRoute(builder: (_) => const HafadhListPage()));
    }),
    _DashItem(Icons.mark_email_unread, 'طلبات التسجيل', (ctx) async {
      await Navigator.push(
          ctx, MaterialPageRoute(builder: (_) => const RequestsListPage()));
      _loadAllCounts();
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
    _DashItem(Icons.bar_chart, 'كشف العلامات الرسمية', (ctx) {
      Navigator.push(ctx,
          MaterialPageRoute(builder: (_) => const OfficialExamReportPage()));
    }),
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
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 4))
        ],
      ),
      child: Column(
        children: [
          Icon(icon, size: 32, color: Colors.white),
          const SizedBox(height: 8),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: value.toDouble()),
            duration: const Duration(milliseconds: 800),
            curve: Curves.easeOutCubic,
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
    final tileWidth = isWide ? 280.0 : double.infinity;

    // نضيف كبسة "طلبات تغيير المشرف" كعنصر ثابت بالمكان الأخير
    final supChangeTile = SizedBox(
      width: tileWidth,
      child: _ActionButton(
        item: _DashItem(
          Icons.swap_horiz,
          'طلبات تغيير المشرف',
          (ctx) async {
            await Navigator.push(
              ctx,
              MaterialPageRoute(
                  builder: (_) => const SupervisorChangeRequestsMalePage()),
            );
            _loadAllCounts();
          },
          badge: () => _supChangePending,
        ),
        badgeVal: _supChangePending,
      ),
    );

    // الحالة المرئية للكبسـة (حتى تظل القائمة ثابتة الطول ولا تعيد موشن)
    Widget supChangeVisibilityWrapper(Widget child) {
      // أثناء التحميل: Placeholder بنفس الحجم
      if (_canSeeSupChange == null) {
        return SizedBox(
            width: tileWidth, child: const _ActionButtonPlaceholder());
      }
      // إذا غير مسموح: نخلي مكانها محجوز بدون تفاعل ولا ظهور (لا تغيّر تخطيط الشبكة)
      if (_canSeeSupChange == false) {
        return IgnorePointer(
          ignoring: true,
          child: Opacity(
              opacity: 0,
              child: SizedBox(
                  width: tileWidth, child: _ActionButtonPlaceholder())),
        );
      }
      // مسموح: نعرض الكبسة الحقيقية
      return child;
    }

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
              // AppBar
              Container(
                padding:
                    const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
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
                    'ملتقى القرآن الكريم — مسؤول (ذكور)',
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
                // ✅ AnimationLimiter واحد فقط لكل المحتوى حتى ما تتكرر الحركة
                child: AnimationLimiter(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Logo
                        ClipOval(
                          child: Container(
                            color: Colors.white,
                            padding: const EdgeInsets.all(12),
                            child: Image.asset('assets/logo1.png',
                                width: 100, height: 100),
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Statistics Summary
                        Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 20,
                          runSpacing: 20,
                          children: AnimationConfiguration.toStaggeredList(
                            duration: const Duration(milliseconds: 600),
                            childAnimationBuilder: (w) => SlideAnimation(
                              horizontalOffset: 50,
                              child: FadeInAnimation(child: w),
                            ),
                            children: [
                              _buildSummaryCard(
                                  Icons.school, 'طلاب', _students),
                              _buildSummaryCard(Icons.supervisor_account,
                                  'مشرفون', _supervisors),
                              _buildSummaryCard(
                                  Icons.verified_user, 'حُفّاظ', _hafidhCount),
                              _buildSummaryCard(Icons.mark_email_unread,
                                  'تسجيلات معلّقة', _regPending),
                              _buildSummaryCard(
                                  Icons.mail, 'امتحانات معلّقة', _examPending),
                              _buildSummaryCard(
                                  Icons.star, 'علامات معلّقة', _scoresPending),
                            ],
                          ),
                        ),

                        const SizedBox(height: 32),

                        // Action Buttons (كلهم بنفس الموشن وبلا إعادة)
                        Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 24,
                          runSpacing: 24,
                          children: AnimationConfiguration.toStaggeredList(
                            duration: const Duration(milliseconds: 800),
                            childAnimationBuilder: (w) => SlideAnimation(
                              verticalOffset: 50,
                              child: FadeInAnimation(child: w),
                            ),
                            children: [
                              ..._baseActions.map((item) {
                                final badgeVal = item.badge?.call() ?? 0;
                                return SizedBox(
                                  width: tileWidth,
                                  child: _ActionButton(
                                      item: item, badgeVal: badgeVal),
                                );
                              }),
                              // زر طلبات تغيير المشرف دائمًا بنفس المكان
                              supChangeVisibilityWrapper(supChangeTile),
                            ],
                          ),
                        ),

                        const SizedBox(height: 40),

                        // Toggle Exam Registration Button
                        SizedBox(
                          child: ElevatedButton.icon(
                            onPressed: _toggleExamReg,
                            icon: Icon(
                                _isDisabled ? Icons.lock_open : Icons.lock),
                            label: Text(
                              _isDisabled
                                  ? 'تفعيل تسجيل الامتحان الرسمي'
                                  : (_from != null && _until != null
                                      ? 'تعطيل من ${DateFormat('yyyy-MM-dd').format(_from!)} إلى ${DateFormat('yyyy-MM-dd').format(_until!)}'
                                      : 'تعطيل تسجيل الامتحان الرسمي'),
                              style: GoogleFonts.cairo(
                                  fontWeight: FontWeight.bold),
                            ),
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

                        // Logout Button
                        SizedBox(
                          width: isWide ? 300 : double.infinity,
                          height: 52,
                          child: ElevatedButton.icon(
                            onPressed: _logout,
                            icon: const Icon(Icons.logout,
                                size: 24, color: Colors.white),
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
                                  borderRadius: BorderRadius.circular(30)),
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.redAccent,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: const [
                      BoxShadow(
                          color: Colors.black26,
                          blurRadius: 4,
                          offset: Offset(0, 2))
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

// Placeholder خفيف بنفس حجم الكرت (بدون شيمر لتجنّب أي لاغ)
class _ActionButtonPlaceholder extends StatelessWidget {
  const _ActionButtonPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xffc8e6c9), Color(0xffdcedc8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      height: 90,
      child: Align(
        alignment: Alignment.center,
        child: Text(
          '—',
          style: GoogleFonts.cairo(
            textStyle: const TextStyle(
              fontSize: 16,
              color: Colors.white70,
            ),
          ),
        ),
      ),
    );
  }
}
