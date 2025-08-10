import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/dio_client.dart';
import '../services/auth_service.dart';
import '../main.dart';

import 'login_page.dart';
import 'part_exam_request_page.dart';
import 'official_exam_request_page.dart';
import 'exam_status_page.dart';
import 'score_sheet_page.dart';
import 'student_certificates_page.dart';
import 'student_plans_page.dart';

// 👇 غيّر المسار حسب مكان الملف عندك
import '../screens/female/request_supervisor_change_page.dart';

/*  الصفحة الرئيسيّة لطالب  */
class StudentHomePage extends StatefulWidget {
  final int studentId;
  final String userName;
  final String college;
  final String studentType; // القيمة الابتدائية فقط ('regular' | 'intensive')

  const StudentHomePage({
    Key? key,
    required this.studentId,
    required this.userName,
    required this.college,
    required this.studentType,
  }) : super(key: key);

  @override
  State<StudentHomePage> createState() => _StudentHomePageState();
}

/* ═════════════════════════════════════════════════════════════ */

class _StudentHomePageState extends State<StudentHomePage>
    with SingleTickerProviderStateMixin, RouteAware {
  late final AnimationController _logoCtl;
  late String _studentType; // يُحدَّث دورياً من الخادم
  bool _planReady = false;
  Map<String, dynamic>? _plan;
  bool _isOverdue = false;

  // 👇 مساعد: كليات البنات (لا تغيّرها إن منطقك يعتمد عليها)
  bool get _isFemaleCollege =>
      const {'NewCampus', 'OldCampus', 'Agriculture'}.contains(widget.college);

  @override
  void initState() {
    super.initState();
    _studentType = widget.studentType;
    _logoCtl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _storeStudentName();
    _refreshStudentInfo();
    _fetchPlan();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    routeObserver.subscribe(this, ModalRoute.of(context)!);
  }

  @override
  void didPopNext() {
    _refreshStudentInfo();
    _fetchPlan();
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    _logoCtl.dispose();
    super.dispose();
  }

  /// يجلب بيانات الطالب (خصوصًا student_type) ويحدِّث الحالة
  Future<void> _refreshStudentInfo() async {
    try {
      // ⚠️ بدون شرطة أولى عشان baseUrl ينتهي بـ /api
      final resp = await DioClient().dio.get('students/me');
      final data = resp.data as Map<String, dynamic>? ?? {};
      if (!mounted || data.isEmpty) return;
      setState(() {
        _studentType = data['student_type'] as String? ?? _studentType;
      });
    } catch (e) {
      debugPrint('[refreshStudentInfo] $e');
    }
  }

  Future<void> _storeStudentName() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('student_name', widget.userName);
  }

  Future<void> _fetchPlan() async {
    try {
      // ⚠️ برضو بدون شرطة أولى
      final resp = await DioClient().dio.get('plans/me');
      final data = resp.data as Map<String, dynamic>? ?? {};
      if (!mounted) return;
      setState(() {
        _planReady = data.isNotEmpty && data['approved'] == true;
        _plan = _planReady ? data : null;
        _isOverdue = data['is_overdue'] as bool? ?? false;
      });
    } catch (e) {
      debugPrint('[_fetchPlan] error: $e');
      if (!mounted) return;
      setState(() {
        _planReady = false;
        _plan = null;
        _isOverdue = false;
      });
    }
  }

  /* ───── أزرار تسجيل الامتحانات ───── */

  void _onTapPart() async {
    if (!_planReady) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('خطتك لم تُعتمد بعد', style: GoogleFonts.cairo())),
      );
      return;
    }
    try {
      // ❌ كانت '/api/settings/...' → ✅ 'settings/...'
      final resp = await DioClient().dio.get(
        'settings/part-exam-registration',
        queryParameters: {'college': widget.college},
      );
      final data = resp.data;
      final now = DateTime.now();
      final from = data['disabledFrom'] != null
          ? DateTime.parse(data['disabledFrom'])
          : null;
      final until = data['disabledUntil'] != null
          ? DateTime.parse(data['disabledUntil'])
          : null;

      final closed = (from != null &&
              (now.isAfter(from) || now.isAtSameMomentAs(from))) &&
          (until == null || now.isBefore(until) || now.isAtSameMomentAs(until));

      if (closed) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('التسجيل لامتحانات الأجزاء مغلق حاليًا',
                  style: GoogleFonts.cairo())),
        );
        return;
      }

      Navigator.push(context,
          MaterialPageRoute(builder: (_) => const PartExamRequestPage()));
    } catch (e) {
      debugPrint('check part exam error: $e');
    }
  }

  void _onTapOfficial() async {
    if (!_planReady) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('خطتك لم تُعتمد بعد', style: GoogleFonts.cairo())),
      );
      return;
    }
    try {
      // ❌ كانت '/api/settings/...' → ✅ 'settings/...'
      final resp = await DioClient().dio.get(
        'settings/exam-registration',
        queryParameters: {'gender': _isFemaleCollege ? 'female' : 'male'},
      );
      final data = resp.data;
      final now = DateTime.now();
      final from = data['disabledFrom'] != null
          ? DateTime.parse(data['disabledFrom'])
          : null;
      final until = data['disabledUntil'] != null
          ? DateTime.parse(data['disabledUntil'])
          : null;

      final closed = (from != null &&
              (now.isAfter(from) || now.isAtSameMomentAs(from))) &&
          (until == null || now.isBefore(until) || now.isAtSameMomentAs(until));

      if (closed) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('التسجيل للامتحانات الرسمية مُعطَّل حاليًا',
                  style: GoogleFonts.cairo())),
        );
        return;
      }

      Navigator.push(context,
          MaterialPageRoute(builder: (_) => const OfficialExamRequestPage()));
    } catch (e) {
      debugPrint('check official exam error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isIntensive = _studentType == 'intensive';
    final isFemale = _isFemaleCollege; // 👈 نعتمد الكلية لتحديد الجهة

    /* شبكة الأزرار الرئيسة */
    final actions = <_Action>[
      _Action(Icons.book_outlined, 'تسجيل أجزاء',
          onTap: _onTapPart, color: Colors.teal),
      _Action(Icons.school_outlined, 'الامتحانات الرسمية',
          onTap: _onTapOfficial, color: Colors.orange),
      _Action(Icons.notifications_outlined, 'حالة امتحاناتي',
          page: const ExamStatusPage(), color: Colors.blue),
      _Action(
        Icons.receipt_long_outlined,
        'كشف العلامات',
        page: ScoreSheetPage(
          studentId: widget.studentId,
          studentName: widget.userName,
          studentCollege: widget.college,
          studentType: _studentType,
        ),
        color: Colors.purple,
      ),
      _Action(
        Icons.playlist_add_check,
        'اختيار خطتي',
        onTap: () async {
          final ok = await Navigator.push<bool>(
            context,
            MaterialPageRoute(
                builder: (_) => StudentPlansPage(studentType: _studentType)),
          );
          if (ok == true) _fetchPlan();
        },
        color: Colors.tealAccent.shade700,
      ),
      _Action(
        Icons.download_outlined,
        'شهاداتي',
        page: const CertificatesPage(),
        color: Colors.green.shade700,
      ),

      // ✅ هنا النصّ يتغير حسب الجهة
      _Action(
        Icons.swap_horiz,
        isFemale ? 'اختاري/تغيير المشرفة' : 'اختيار/تغيير المشرف',
        page: RequestSupervisorChangePage(isFemale: isFemale),
        color: Colors.pinkAccent,
      ),
    ];

    return Scaffold(
      // بدون AppBar
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xffe8f5e9), Color(0xff66bb6a)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 30),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 600),
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black12,
                      blurRadius: 16,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    /* شعار متحرّك */
                    AnimatedBuilder(
                      animation: _logoCtl,
                      builder: (_, child) => Transform.translate(
                        offset: Offset(0, -sin(_logoCtl.value * 2 * pi) * 8),
                        child: child,
                      ),
                      child: Image.asset('assets/logo1.png',
                          width: 100, height: 100),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'ملتقى القرآن الكريم',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Color(0xff2e7d32),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'أهلاً وسهلاً، ${widget.userName}',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                    Text(
                      'الكلية: ${widget.college}',
                      style: const TextStyle(
                        fontSize: 16,
                        color: Colors.black54,
                      ),
                    ),
                    Text(
                      'نوع الطالب: ${isIntensive ? 'تثبيت' : 'عادي'}',
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.black45,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                    const SizedBox(height: 24),

                    /* ـــ ملخص الخطة ـــ */
                    if (!_planReady)
                      Text(
                        'لم تُعتمد خطتك بعد. الرجاء اختيارها أولاً.',
                        style: GoogleFonts.cairo(
                          color: Colors.red,
                          fontSize: 16,
                        ),
                      )
                    else ...[
                      Text(
                        'خطة معتمدة من ${_plan!['start']} إلى ${_plan!['due']}\n'
                        'مدة: ${_plan!['duration_value']} أسابيع',
                        style: GoogleFonts.cairo(
                          color: Colors.green.shade700,
                          fontSize: 16,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'الجزء الحالى: ${_plan!['current_part']}',
                        style: GoogleFonts.cairo(
                          color: Colors.black87,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (_plan!['paused_for_official'] == true) ...[
                        const SizedBox(height: 4),
                        Text(
                          '⚠️ الخطة متوقفة بانتظار امتحان رسمى',
                          style: GoogleFonts.cairo(
                            color: Colors.orange.shade800,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                      if (_isOverdue) ...[
                        const SizedBox(height: 6),
                        Text(
                          'حالتك متأخّرة: سجِّل امتحان الجزء الحالي لتستمرّ الخطة',
                          style: GoogleFonts.cairo(
                            color: Colors.red,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ],
                    const SizedBox(height: 24),

                    /* شبكة الأزرار */
                    AnimationLimiter(
                      child: GridView.count(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisCount: 3,
                        mainAxisSpacing: 16,
                        crossAxisSpacing: 16,
                        childAspectRatio: 0.8,
                        children: List.generate(
                          actions.length,
                          (i) => AnimationConfiguration.staggeredGrid(
                            position: i,
                            duration: const Duration(milliseconds: 1200),
                            columnCount: 3,
                            child: SlideAnimation(
                              verticalOffset: 50,
                              child: FadeInAnimation(
                                  child: _GridButton(action: actions[i])),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    /* زر الخروج */
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          await AuthService.clearToken();
                          if (!context.mounted) return;
                          Navigator.pushAndRemoveUntil(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const LoginPage()),
                            (_) => false,
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xffd32f2f),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        icon: const Icon(Icons.logout),
                        label: Text('تسجيل الخروج', style: GoogleFonts.cairo()),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/* ───────────────────── عناصر مساعدة ───────────────────── */

class _Action {
  final IconData icon;
  final String label;
  final Color color;
  final Widget? page;
  final VoidCallback? onTap;

  const _Action(this.icon, this.label,
      {this.page, this.onTap, required this.color});
}

class _GridButton extends StatelessWidget {
  final _Action action;
  const _GridButton({required this.action});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: action.page != null
          ? () => Navigator.push(
              context, MaterialPageRoute(builder: (_) => action.page!))
          : action.onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: action.color.withOpacity(.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: action.color.withOpacity(.3)),
        ),
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: action.color,
              child: Icon(action.icon, color: Colors.white, size: 28),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: Text(
                action.label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: _darken(action.color, .2)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _darken(Color c, [double amt = .1]) => Color.fromARGB(
        c.alpha,
        (c.red * (1 - amt)).round(),
        (c.green * (1 - amt)).round(),
        (c.blue * (1 - amt)).round(),
      );
}
