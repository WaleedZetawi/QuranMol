import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import '../services/auth_service.dart';
import 'login_page.dart';
import 'part_exam_request_page.dart';
import 'official_exam_request_page.dart';
import 'exam_status_page.dart';
import 'score_sheet_page.dart';

class StudentHomePage extends StatefulWidget {
  final int studentId;
  final String userName;
  final String college;
  final String studentType; // 'regular' أو 'intensive'

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

class _StudentHomePageState extends State<StudentHomePage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _logoController;

  @override
  void initState() {
    super.initState();
    // حركة bob بسيطة لشعار الملتقى
    _logoController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _logoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isIntensive = widget.studentType == 'intensive';

    // تعريف بيانات الأزرار بشكل مصنّف
    final actions = <Map<String, dynamic>>[
      {
        'icon': Icons.book_outlined,
        'label': 'تسجيل أجزاء',
        'page': PartExamRequestPage(),
        'color': Colors.teal,
      },
      {
        'icon': Icons.school_outlined,
        'label': 'الامتحانات الرسمية',
        'page': OfficialExamRequestPage(),
        'color': Colors.orange,
      },
      {
        'icon': Icons.notifications_outlined,
        'label': 'حالة امتحاناتي',
        'page': ExamStatusPage(),
        'color': Colors.blue,
      },
      {
        'icon': Icons.receipt_long_outlined,
        'label': 'كشف العلامات',
        'page': ScoreSheetPage(
          studentId: widget.studentId,
          studentName: widget.userName,
          studentCollege: widget.college,
          studentType: widget.studentType,
        ),
        'color': Colors.purple,
      },
      {
        'icon': Icons.playlist_add_check,
        'label': 'اختيار خطتي',
        'action': () => _showComingSoon(context),
        'color': Colors.tealAccent.shade700,
      },
      {
        'icon': Icons.download_outlined,
        'label': 'تصدير شهادات',
        'action': () => _showComingSoon(context),
        'color': Colors.green.shade700,
      },
    ];

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFE8F5E9), Color(0xFF66BB6A)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: 20.0,
                vertical: 30.0,
              ),
              child: Container(
                padding: const EdgeInsets.all(24.0),
                constraints: const BoxConstraints(maxWidth: 600),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20.0),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black12,
                      blurRadius: 16.0,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // شعار مع حركة bob
                    AnimatedBuilder(
                      animation: _logoController,
                      builder: (ctx, child) {
                        final dy = sin(_logoController.value * 2 * pi) * 8;
                        return Transform.translate(
                          offset: Offset(0, -dy),
                          child: child,
                        );
                      },
                      child: Image.asset(
                        'assets/logo1.png',
                        width: 100,
                        height: 100,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // عنوان الملتقى
                    const Text(
                      'ملتقى القرآن الكريم',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF2E7D32),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // الترحيب بالمستخدم
                    Text(
                      'أهلاً وسهلاً، ${widget.userName}',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'الكلية: ${widget.college}',
                      style: const TextStyle(
                        fontSize: 16,
                        color: Colors.black54,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'الخطة: ${isIntensive ? 'تثبيت (حافظ مسبقاً)' : 'عادي'}',
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.black45,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                    const SizedBox(height: 24),

                    // شبكة الأزرار مع Slow‑Motion Animation
                    AnimationLimiter(
                      child: GridView.count(
                        shrinkWrap: true,
                        crossAxisCount: 3,
                        mainAxisSpacing: 16,
                        crossAxisSpacing: 16,
                        childAspectRatio: 0.8,
                        physics: const NeverScrollableScrollPhysics(),
                        children: List.generate(actions.length, (i) {
                          final item = actions[i];
                          return AnimationConfiguration.staggeredGrid(
                            position: i,
                            duration: const Duration(milliseconds: 1200),
                            columnCount: 3,
                            child: SlideAnimation(
                              curve: Curves.easeInOut,
                              verticalOffset: 50,
                              child: FadeInAnimation(
                                child: _gridButton(
                                  icon: item['icon'] as IconData,
                                  label: item['label'] as String,
                                  onTap: () {
                                    if (item.containsKey('page')) {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              item['page'] as Widget,
                                        ),
                                      );
                                    } else if (item.containsKey('action')) {
                                      (item['action'] as VoidCallback)();
                                    }
                                  },
                                  color: item['color'] as Color,
                                ),
                              ),
                            ),
                          );
                        }),
                      ),
                    ),

                    const SizedBox(height: 24),
                    // زرّ تسجيل الخروج المعدّل
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          await AuthService.clearToken();
                          if (!context.mounted) return;
                          Navigator.pushAndRemoveUntil(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const LoginPage(),
                            ),
                            (r) => false,
                          );
                        },
                        icon: const Icon(
                          Icons.logout,
                          color: Color(0xFFD32F2F),
                        ),
                        label: const Text(
                          "تسجيل الخروج",
                          style: TextStyle(color: Color(0xFFD32F2F)),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          side: const BorderSide(
                            color: Color(0xFFD32F2F),
                            width: 1.5,
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
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
    );
  }

  Widget _gridButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required Color color,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: color,
              child: Icon(icon, color: Colors.white, size: 28),
            ),
            const SizedBox(height: 8),
            // <-- هنا استخدم Flexible وخلي النص يلتف أو يقص
            Flexible(
              child: Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: color.darken(0.2),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showComingSoon(BuildContext ctx) {
    ScaffoldMessenger.of(
      ctx,
    ).showSnackBar(const SnackBar(content: Text('هذه الميزة قيد الإضافة')));
  }
}

// إضافة امتداد لتغميق اللون
extension ColorUtils on Color {
  Color darken([double amt = .1]) {
    final f = 1 - amt;
    return Color.fromARGB(
      alpha,
      (red * f).round(),
      (green * f).round(),
      (blue * f).round(),
    );
  }
}
