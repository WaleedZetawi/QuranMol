import 'package:flutter/material.dart';

enum College { engineering, medical, sharia }

class CollegeTheme {
  final Color bgLight;
  final Color start;
  final Color end;
  const CollegeTheme(this.start, this.end, this.bgLight);

  static const engineering =
      CollegeTheme(Color(0xFF1565C0), Color(0xFF42A5F5), Color(0xFFE3F2FD));
  static const medical =
      CollegeTheme(Color(0xFF00796B), Color(0xFF26A69A), Color(0xFFE0F2F1));
  static const sharia =
      CollegeTheme(Color(0xFF8E6C46), Color(0xFFB07B4F), Color(0xFFFFF8E1));

  static CollegeTheme byName(String college) {
    switch (college) {
      case 'Engineering':
        return engineering;
      case 'Medical':
        return medical;
      case 'Sharia':
        return sharia;
      default:
        return engineering;
    }
  }
}
