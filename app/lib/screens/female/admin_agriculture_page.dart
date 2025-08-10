// lib/screens/admin/admin_agriculture_page.dart
import 'package:flutter/material.dart';
import 'admin_girls_page.dart';

class AdminAgriculturePage extends StatelessWidget {
  final String userName;
  const AdminAgriculturePage({super.key, required this.userName});

  @override
  Widget build(BuildContext context) => AdminGirlsPage(
        collegeCode: 'Agriculture',
        title: 'مسؤولة الزراعة',
        // Sage green ناعم
        start: const Color(0xFF2E7D32),
        end: const Color(0xFFA5D6A7),
        bg: const Color(0xFFF1F8F2),
        userName: userName,
      );
}
