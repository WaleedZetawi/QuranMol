import 'package:flutter/material.dart';

// 1) استيراد Delegates الخاصة بالتوطين
import 'package:flutter_localizations/flutter_localizations.dart';

import 'screens/login_page.dart';
import 'screens/student_home_page.dart';

import 'package:google_fonts/google_fonts.dart';

// هذا الـ observer سنتشاركه مع كل الصفحات التي تريد رصدها
final RouteObserver<ModalRoute<void>> routeObserver =
    RouteObserver<ModalRoute<void>>();

void main() {
  runApp(const MoltaqaApp());
}

class MoltaqaApp extends StatelessWidget {
  const MoltaqaApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ملتقى القرآن الكريم',

      // إضافة الـ routeObserver لكي تستطيع رصد العودة إلى الصفحات
      navigatorObservers: [routeObserver],

      // إعدادات التوطين للتواريخ والنصوص في الـ DatePicker والـ Widgets الأخرى
      locale: const Locale('ar'), // يمكنك جعله null لاستخدام لغة الجهاز
      supportedLocales: const [
        Locale('ar'),
        Locale('en'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],

      // الصفحة الرئيسية عند الإقلاع
      home: const LoginPage(),

      debugShowCheckedModeBanner: false,

      // استخدام خط Google Cairo لجميع النصوص
      theme: ThemeData(
        primarySwatch: Colors.green,
        // هنا نطبّق Cairo على كل TextTheme
        textTheme: GoogleFonts.cairoTextTheme(
          Theme.of(context).textTheme,
        ),
      ),
    );
  }
}
