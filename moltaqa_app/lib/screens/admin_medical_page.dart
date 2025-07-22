import 'package:flutter/material.dart';

import 'college_exam_requests_page.dart';
import '../../services/auth_service.dart';
import 'login_page.dart';
import '../features/admin/pending_scores_page.dart';

class AdminMedicalPage extends StatelessWidget {
  final String userName;
  const AdminMedicalPage({super.key, required this.userName});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F8), // خلفية فاتحة وناعمة
      appBar: AppBar(
        title: const Text("مسؤول مجمع الطب"),
        backgroundColor: const Color(0xFF2A9D8F), // أخضر مزرق رسمي
        centerTitle: true,
        elevation: 8,
        shadowColor: Colors.black45,
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final double maxWidth = constraints.maxWidth > 800
              ? 800.0
              : constraints.maxWidth * 0.95;

          return Center(
            child: Container(
              width: maxWidth,
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black12.withOpacity(0.08),
                    blurRadius: 24,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Image.asset(
                    "assets/logo1.png",
                    width: constraints.maxWidth > 400 ? 140 : 110,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    "أهلاً وسهلاً بك، $userName",
                    style: TextStyle(
                      fontSize: constraints.maxWidth > 400 ? 28 : 22,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF264653),
                      letterSpacing: 0.7,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  Expanded(
                    child: GridView.count(
                      crossAxisCount: constraints.maxWidth > 600 ? 3 : 2,
                      crossAxisSpacing: 22,
                      mainAxisSpacing: 22,
                      childAspectRatio: 3.8,
                      physics: const BouncingScrollPhysics(),
                      children: _buildMainButtons(context),
                    ),
                  ),

                  // زر تصدير الشهادات - في الوسط أسفل الشبكة
                  const SizedBox(height: 24),
                  SizedBox(
                    width: maxWidth > 400 ? 300 : maxWidth * 0.8,
                    child: ElevatedButton.icon(
                      icon: const Icon(
                        Icons.file_download,
                        color: Colors.white,
                        size: 22,
                      ),
                      label: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 14),
                        child: Text(
                          "📤 تصدير الشهادات",
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                            letterSpacing: 0.7,
                          ),
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF27AE60), // أخضر رسمي
                        elevation: 10,
                        shadowColor: Colors.black45,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text("جاري تنفيذ تصدير الشهادات..."),
                          ),
                        );
                      },
                    ),
                  ),

                  const SizedBox(height: 28),

                  // زر تسجيل الخروج - كبير، بارز في الأسفل
                  SizedBox(
                    width: maxWidth > 400 ? 300 : maxWidth * 0.8,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.logout, color: Colors.white),
                      label: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Text(
                          "تسجيل الخروج",
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            letterSpacing: 0.7,
                          ),
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFE63946), // أحمر رسمي
                        elevation: 14,
                        shadowColor: Colors.black54,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                      onPressed: () async {
                        await AuthService.clearToken();
                        if (!context.mounted) return;
                        Navigator.pushAndRemoveUntil(
                          context,
                          MaterialPageRoute(builder: (_) => const LoginPage()),
                          (route) => false,
                        );
                      },
                    ),
                  ),

                  const SizedBox(height: 18),
                  const Text(
                    "الطب علم، والقرآن شفاء... اجمع بين العلم والشفاء",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontStyle: FontStyle.italic,
                      color: Color(0xFF7A8A99),
                      fontSize: 16,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  List<Widget> _buildMainButtons(BuildContext context) {
    final buttonsData = [
      {
        "title": "📋 قائمة الطلاب",
        "action": () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("تم الضغط على قائمة الطلاب")),
          );
        },
      },
      {
        "title": "📝 رصد العلامات",
        "action": () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PendingScoresPage(college: "Medical"),
            ),
          );
        },
      },
      {
        "title": "📊 التقرير الأسبوعي",
        "action": () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("جاري تنفيذ التقرير الأسبوعي...")),
          );
        },
      },
      {
        "title": "👨‍🎓 متابعة الطلبة",
        "action": () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("تم الضغط على متابعة الطلبة")),
          );
        },
      },
      {
        "title": "📨 طلبات الامتحانات",
        "action": () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const CollegeExamRequestsPage(college: "Medical"),
            ),
          );
        },
      },
      {
        "title": "🗑 سحب العلامة",
        "action": () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("تم الضغط على سحب العلامة")),
          );
        },
      },
    ];

    return buttonsData.map((btn) {
      return ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF27AE60), // أخضر رسمي موحد للأزرار
          elevation: 8,
          shadowColor: Colors.black45,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 14),
        ),
        onPressed: btn["action"] as void Function()?,
        child: Text(
          btn["title"] as String,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Colors.white,
            shadows: [
              Shadow(
                color: Colors.black26,
                offset: Offset(1, 1),
                blurRadius: 3,
              ),
            ],
          ),
          textAlign: TextAlign.center,
        ),
      );
    }).toList();
  }
}
