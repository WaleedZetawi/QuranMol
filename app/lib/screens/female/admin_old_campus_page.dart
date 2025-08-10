// lib/screens/admin/admin_old_campus_page.dart
import 'package:flutter/material.dart';
import 'admin_girls_page.dart';

class AdminOldCampusPage extends StatelessWidget {
  final String userName;
  const AdminOldCampusPage({super.key, required this.userName});

  @override
  Widget build(BuildContext context) => AdminGirlsPage(
        collegeCode: 'OldCampus',
        title: 'مسؤولة الحرم القديم',
        // Plum -> Dusty Rose
        start: const Color(0xFF7B1FA2),
        end: const Color(0xFFCFA1D3),
        bg: const Color(0xFFFAF3FB),
        userName: userName,
      );
}
