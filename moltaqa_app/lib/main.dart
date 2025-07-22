import 'package:flutter/material.dart';

// 1) استيراد Delegates الخاصة بالتوطين
import 'package:flutter_localizations/flutter_localizations.dart';

import 'screens/login_page.dart';

void main() {
  runApp(const MoltaqaApp());
}

class MoltaqaApp extends StatelessWidget {
  const MoltaqaApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ملتقى القرآن الكريم',

      // 2) اعدادات التوطين للتواريخ والنصوص في الـ DatePicker والـ Widgets الأخرى
      locale: const Locale('ar'), // يمكنك جعله null لاستخدام لغة الجهاز
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],

      home: const LoginPage(),
      debugShowCheckedModeBanner: false,
      theme: ThemeData(fontFamily: 'Cairo'),
    );
  }
}
