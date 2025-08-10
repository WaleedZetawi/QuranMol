import 'package:intl/intl.dart';

// NEW
String fmtYMD(dynamic v) {
  if (v == null) return '-';
  final s = v.toString();
  // إذا كان أصلاً "yyyy-MM-dd"
  if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(s)) return s;
  try {
    return DateFormat('yyyy-MM-dd').format(DateTime.parse(s).toLocal());
  } catch (_) {
    return s;
  }
}
