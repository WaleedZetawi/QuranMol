// widget_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// يستورد MoltaqaApp من main.dart
import 'package:moltaqa_app/main.dart';

void main() {
  testWidgets('Counter increments smoke test', (WidgetTester tester) async {
    // بدل MyApp() نستخدم MoltaqaApp()
    await tester.pumpWidget(const MoltaqaApp());

    // تحقق إن العداد يبدأ من الصفر
    expect(find.text('0'), findsOneWidget);
    expect(find.text('1'), findsNothing);

    // اضغط على أيقونة '+' وحمّل إطار جديد
    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();

    // تأكد أن العداد صار 1
    expect(find.text('0'), findsNothing);
    expect(find.text('1'), findsOneWidget);
  });
}
