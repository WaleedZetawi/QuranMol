import 'package:flutter/material.dart';

class AdminBasePage extends StatelessWidget {
  final String userName;
  final String title;
  final Color primaryColor;
  final Color backgroundColor;
  final List<String> buttons;

  const AdminBasePage({
    super.key,
    required this.userName,
    required this.title,
    required this.primaryColor,
    required this.backgroundColor,
    required this.buttons,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(backgroundColor: primaryColor, title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Image.asset("assets/logo1.png", width: 120),
          const SizedBox(height: 20),
          Center(
            child: Text(
              "أهلاً وسهلاً، $userName",
              style: const TextStyle(fontSize: 22),
            ),
          ),
          const SizedBox(height: 20),
          for (var title in buttons) _buildButton(context, title),
        ],
      ),
    );
  }

  Widget _buildButton(BuildContext context, String title) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: ElevatedButton(
        onPressed: () {},
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Text(title, style: const TextStyle(fontSize: 18)),
      ),
    );
  }
}
