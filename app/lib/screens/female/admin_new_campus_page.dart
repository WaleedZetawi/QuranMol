// lib/screens/admin/admin_new_campus_page.dart
import 'package:flutter/material.dart';
import 'admin_girls_page.dart';

class AdminNewCampusPage extends StatelessWidget {
  final String userName;
  const AdminNewCampusPage({super.key, required this.userName});

  @override
  Widget build(BuildContext context) => AdminGirlsPage(
        collegeCode: 'NewCampus',
        title: 'مسؤولة الحرم الجديد',
        // Royal Purple -> Muted Lavender
        start: const Color(0xFF6A1B9A),
        end: const Color(0xFFB39DDB),
        bg: const Color(0xFFF6F2FA),
        userName: userName,
      );
}
