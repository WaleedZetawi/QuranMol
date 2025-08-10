// lib/pages/official_exam_report_page.dart
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:io' show File, SocketException;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:html' as html;

import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';

import '../../services/api_config.dart';
import '../../services/auth_service.dart';
import '../cert_downloader_web.dart'
    if (dart.library.io) 'cert_downloader_stub.dart' as downloader;

/// helper: احسب gender من الدور أو الكلية
Future<Map<String, String>?> _genderQP() async {
  final role = await AuthService.role; // أضِف getter إن مش موجود
  final col = await AuthService.college; // قد تكون null

  // أدوار لوحات الملتقى:
  // - admin_dash_f  => مسؤولة الملتقى (بنات فقط)
  // - admin_dashboard => مسؤول الملتقى (ذكور فقط)
  if (role == 'admin_dash_f') return const {'gender': 'female'};
  if (role == 'admin_dashboard') return const {'gender': 'male'};

  // لو كان مسؤول كلية معيّن
  const femaleCols = {'NewCampus', 'OldCampus', 'Agriculture'};
  const maleCols = {'Engineering', 'Medical', 'Sharia'};
  if (col == null) return null; // super admin عام (لو موجود)
  if (femaleCols.contains(col)) return const {'gender': 'female'};
  if (maleCols.contains(col)) return const {'gender': 'male'};
  return null;
}

class OfficialExamReportPage extends StatefulWidget {
  const OfficialExamReportPage({Key? key}) : super(key: key);

  @override
  State<OfficialExamReportPage> createState() => _OfficialExamReportPageState();
}

class _OfficialExamReportPageState extends State<OfficialExamReportPage> {
  bool _loading = true;
  List<Map<String, dynamic>> _exams = [];
  DateTime? _startDate;
  DateTime? _endDate;

  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  // Auxiliary: now auto-success is indicated by null score
  bool _isAutoSuccess(Map<String, dynamic> e) => e['score'] == null;

  final Map<String, String> _examNames = const {
    'F1': 'خمسة أجزاء الأولى',
    'F2': 'خمسة أجزاء الثانية',
    'F3': 'خمسة أجزاء الثالثة',
    'F4': 'خمسة أجزاء الرابعة',
    'F5': 'خمسة أجزاء الخامسة',
    'F6': 'خمسة أجزاء السادسة',
    'T1': 'عشرة أجزاء الأولى',
    'T2': 'عشرة أجزاء الثانية',
    'T3': 'عشرة أجزاء الثالثة',
    'H1': 'خمسة عشر الأولى',
    'H2': 'خمسة عشر الثانية',
    'Q': 'القرآن كامل',
  };

  // Statistics
  int get total => _exams.length;
  int get above98 => _exams.where((e) {
        final sc = e['score'] as num?;
        return sc != null && sc > 98;
      }).length;
  int get between95and98 => _exams.where((e) {
        final sc = e['score'] as num?;
        return sc != null && sc >= 95 && sc <= 98;
      }).length;
  // Exclude auto-successes (null) from failures
  int get failed => _exams.where((e) {
        final sc = e['score'] as num?;
        return sc != null && sc < 60;
      }).length;

  @override
  void initState() {
    super.initState();
    _fetchExams();
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchExams() async {
    setState(() => _loading = true);
    try {
      final token = await AuthService.token ?? '';
      final qp = await _genderQP(); // ✅ فلترة حسب جهة المسؤول

      final resp = await Dio().get<List>(
        '${ApiConfig.baseUrl}/exams/official',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
        queryParameters: {
          if (qp != null) ...qp, // ← gender ديناميكي
          if (_startDate != null)
            'start': _startDate!.toIso8601String().split('T').first,
          if (_endDate != null)
            'end': _endDate!.toIso8601String().split('T').first,
        },
      );

      _exams = List<Map<String, dynamic>>.from(resp.data!);
    } on SocketException {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('فشل الاتصال')));
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('خطأ: $e')));
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _editScore(int idx) async {
    final exam = _exams[idx];
    final controller =
        TextEditingController(text: (exam['score'] as num).toString());
    final formKey = GlobalKey<FormState>();

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('تعديل العلامة'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'العلامة الجديدة'),
            validator: (v) {
              if (v == null || v.isEmpty) return 'أدخل قيمة';
              final n = num.tryParse(v);
              if (n == null || n < 0 || n > 100) {
                return 'يجب أن تكون بين 0 و100';
              }
              return null;
            },
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء')),
          TextButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(context, true);
              }
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final payload = {
      'exam_id': exam['exam_id'],
      'score': num.parse(controller.text),
    };

    try {
      final token = await AuthService.token ?? '';
      await Dio().post(
        '${ApiConfig.baseUrl}/grade',
        options: Options(
          headers: {'Authorization': 'Bearer $token'},
          contentType: Headers.jsonContentType,
        ),
        data: payload,
      );
      await _fetchExams();
    } on DioError catch (err) {
      final msg = err.response?.data is Map
          ? err.response!.data['message'] ?? err.response!.statusMessage
          : err.response?.statusMessage ?? err.message;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('خطأ عند حفظ العلامة: $msg')));
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('خطأ غير متوقع: $e')));
    }
  }

  Future<void> _deleteExam(int idx) async {
    final exam = _exams[idx];

    final sure = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: Text(
          'هل أنت متأكد من حذف علامة الطالب:\n'
          '${exam['student_name']} - '
          '${_examNames[exam['exam_code']] ?? exam['exam_code']} ؟',
          style: GoogleFonts.cairo(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حذف', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (sure != true) return;

    try {
      final token = await AuthService.token ?? '';
      final uri = '${ApiConfig.baseUrl}/exams/${exam['exam_id']}';
      await Dio().delete(
        uri,
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      setState(() => _exams.removeAt(idx));
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('تم الحذف')));
    } on DioError catch (err) {
      final msg = err.response?.data is Map
          ? err.response!.data['message'] ?? err.response!.statusMessage
          : err.response?.statusMessage ?? err.message;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('فشل الحذف: $msg')));
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('خطأ غير متوقع: $e')));
    }
  }

  int _weekOfYear(DateTime date) {
    final first = DateTime(date.year, 1, 1);
    final dayOfYear = date.difference(first).inDays + 1;
    return ((dayOfYear + first.weekday - 1) ~/ 7) + 1;
  }

  Future<void> _exportExcel() async {
    final type = await showDialog<String>(
      context: context,
      builder: (_) => SimpleDialog(
        title: const Text('اختر نوع الطلاب'),
        children: [
          SimpleDialogOption(
            child: const Text('طلاب الحفظ العادي'),
            onPressed: () => Navigator.pop(context, 'regular'),
          ),
          SimpleDialogOption(
            child: const Text('طلاب التثبيت'),
            onPressed: () => Navigator.pop(context, 'intensive'),
          ),
        ],
      ),
    );
    if (type == null) return;

    final weeksSet = <int>{};
    for (var e in _exams) {
      weeksSet.add(_weekOfYear(DateTime.parse(e['created_at'])));
    }
    final weeksList = weeksSet.toList()..sort();

    final selected = <int>{};
    await showDialog<void>(
      context: context,
      builder: (_) {
        return StatefulBuilder(builder: (ctx, setSt) {
          return AlertDialog(
            title: const Text('اختر الأسابيع'),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView(
                shrinkWrap: true,
                children: weeksList.map((w) {
                  return CheckboxListTile(
                    title: Text('أسبوع $w'),
                    value: selected.contains(w),
                    onChanged: (v) {
                      setSt(() {
                        if (v == true) {
                          selected.add(w);
                        } else {
                          selected.remove(w);
                        }
                      });
                    },
                  );
                }).toList(),
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('إلغاء')),
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('موافق')),
            ],
          );
        });
      },
    );
    if (selected.isEmpty) return;

    // ⬅️ تمرير الجنس تلقائياً
    final qp = await _genderQP();
    final excelUri = Uri.parse('${ApiConfig.baseUrl}/reports/excel')
        .replace(queryParameters: {
      'student_type': type,
      'weeks': selected.join(','),
      if (qp != null) 'gender': qp['gender']!,
    });

    if (kIsWeb) {
      final token = await AuthService.token;
      if (token == null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('لم يتم تسجيل الدخول')));
        return;
      }
      try {
        setState(() => _loading = true);
        final resp = await Dio().get<Uint8List>(
          excelUri.toString(),
          options: Options(
            responseType: ResponseType.bytes,
            headers: {'Authorization': 'Bearer $token'},
          ),
        );
        final blob = html.Blob(
          [resp.data!],
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        );
        final url = html.Url.createObjectUrlFromBlob(blob);
        html.AnchorElement(href: url)
          ..setAttribute('download', 'report.xlsx')
          ..click();
        html.Url.revokeObjectUrl(url);
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('خطأ عند تنزيل التقرير على الويب: $e')));
      } finally {
        setState(() => _loading = false);
      }
      return;
    }

    final token = await AuthService.token;
    if (token == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('لم يتم تسجيل الدخول')));
      return;
    }
    try {
      setState(() => _loading = true);
      final response = await Dio().getUri(
        excelUri,
        options: Options(
          responseType: ResponseType.bytes,
          headers: {'Authorization': 'Bearer $token'},
        ),
      );
      final bytes = response.data as List<int>;
      final dir = await getTemporaryDirectory();
      final filePath =
          '${dir.path}/report_${DateTime.now().millisecondsSinceEpoch}.xlsx';
      final file = File(filePath);
      await file.writeAsBytes(bytes, flush: true);
      await OpenFile.open(filePath);
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('خطأ عند تنزيل التقرير: $e')));
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _exportCertificates() async {
    // ⬅️ تمرير الجنس تلقائياً
    final qp = await _genderQP();
    final certsUri = Uri.parse('${ApiConfig.baseUrl}/reports/bulk-certificates')
        .replace(queryParameters: {
      'start': _startDate?.toIso8601String().split('T').first ?? '',
      'end': _endDate?.toIso8601String().split('T').first ?? '',
      if (qp != null) 'gender': qp['gender']!,
    });

    final tok = await AuthService.token;
    if (tok == null) return;

    setState(() => _loading = true);
    try {
      final r = await Dio().get<Uint8List>(
        certsUri.toString(),
        options: Options(
          responseType: ResponseType.bytes,
          headers: {'Authorization': 'Bearer $tok'},
        ),
      );
      await downloader.saveAndOpen(
          bytes: r.data!, fileName: 'certificates.zip');
    } finally {
      setState(() => _loading = false);
    }
  }

  DataRow _buildDataRow(Map<String, dynamic> e, int originalIndex) {
    final scoreDisplay =
        _isAutoSuccess(e) ? 'ناجح' : (e['score'] as num).toString();

    return DataRow(cells: [
      DataCell(Text(e['reg_number']?.toString() ?? '-')),
      DataCell(Text(e['student_name'] ?? '-')),
      DataCell(Text(e['email'] ?? '-')),
      DataCell(Text(_examNames[e['exam_code']] ?? e['exam_code'] ?? '-')),
      DataCell(Text(scoreDisplay)),
      DataCell(Text((e['created_at'] as String).split('T').first)),
      DataCell(Row(
        children: [
          IconButton(
            icon: const Icon(Icons.edit, color: Colors.blueAccent),
            onPressed: () => _editScore(originalIndex),
          ),
          IconButton(
            icon: const Icon(Icons.delete, color: Colors.red),
            onPressed: () => _deleteExam(originalIndex),
          ),
        ],
      )),
    ]);
  }

  Widget _buildSummaryCard(
      String label, int value, IconData icon, List<Color> gradient) {
    return Container(
      width: 120,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
            colors: gradient,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 28),
          const SizedBox(height: 8),
          Text(
            value.toString(),
            style: GoogleFonts.cairo(
                textStyle: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white)),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            style: GoogleFonts.cairo(
                textStyle:
                    const TextStyle(fontSize: 12, color: Colors.white70)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const greenGradient = [
      Color(0xff1b5e20),
      Color(0xff43a047),
      Color(0xff66bb6a)
    ];

    final displayedExams = _exams.where((e) {
      final q = _searchQuery.toLowerCase();
      return e['reg_number'].toString().toLowerCase().contains(q) ||
          (e['student_name'] as String).toLowerCase().contains(q);
    }).toList();

    return Scaffold(
      backgroundColor: const Color(0xffe8f5e9),
      appBar: AppBar(
        elevation: 2,
        centerTitle: true,
        title: Text(
          'كشف العلامات الرسمية',
          style: GoogleFonts.cairo(
            textStyle: const TextStyle(
                color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
          ),
        ),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
                begin: Alignment.centerRight,
                end: Alignment.centerLeft,
                colors: greenGradient),
          ),
        ),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                children: [
                  // Search field
                  TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'ابحث بالاسم أو رقم الطالب',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8)),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Export buttons
                  ElevatedButton.icon(
                    icon: const Icon(Icons.file_upload),
                    label: const Text('تصدير تقارير Excel'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: greenGradient.last,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: _exportExcel,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.picture_as_pdf),
                    label: const Text('تصدير جميع الشهادات PDF'),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xff219150),
                        padding: const EdgeInsets.symmetric(vertical: 12)),
                    onPressed: _exportCertificates,
                  ),
                  const SizedBox(height: 16),

                  // Summary cards
                  Center(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _buildSummaryCard(
                              'إجمالي', total, Icons.list, greenGradient),
                          const SizedBox(width: 12),
                          _buildSummaryCard('أعلى من 98', above98, Icons.star, [
                            const Color(0xffffb300),
                            const Color(0xffffca28)
                          ]),
                          const SizedBox(width: 12),
                          _buildSummaryCard(
                              '95–98', between95and98, Icons.emoji_events, [
                            const Color(0xff1976d2),
                            const Color(0xff42a5f5)
                          ]),
                          const SizedBox(width: 12),
                          _buildSummaryCard('رسوب', failed, Icons.clear, [
                            const Color(0xffc62828),
                            const Color(0xffe53935)
                          ]),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Date filters
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Color(0xff43a047)),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8)),
                          ),
                          onPressed: () async {
                            final now = DateTime.now();
                            final d = await showDatePicker(
                              context: context,
                              initialDate: _startDate ?? now,
                              firstDate: DateTime(now.year - 5),
                              lastDate: DateTime(now.year + 1),
                              locale: const Locale('ar'),
                            );
                            if (d != null) setState(() => _startDate = d);
                          },
                          child: Text(
                            _startDate == null
                                ? 'من تاريخ'
                                : _startDate!
                                    .toIso8601String()
                                    .split('T')
                                    .first,
                            style: GoogleFonts.cairo(
                                color: const Color(0xff43a047)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Color(0xff43a047)),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8)),
                          ),
                          onPressed: () async {
                            final now = DateTime.now();
                            final d = await showDatePicker(
                              context: context,
                              initialDate: _endDate ?? now,
                              firstDate: DateTime(now.year - 5),
                              lastDate: DateTime(now.year + 1),
                              locale: const Locale('ar'),
                            );
                            if (d != null) setState(() => _endDate = d);
                          },
                          child: Text(
                            _endDate == null
                                ? 'إلى تاريخ'
                                : _endDate!.toIso8601String().split('T').first,
                            style: GoogleFonts.cairo(
                                color: const Color(0xff43a047)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xff43a047),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: _fetchExams,
                        child: Text('عرض', style: GoogleFonts.cairo()),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.clear, color: Colors.redAccent),
                        onPressed: () {
                          setState(() {
                            _startDate = null;
                            _endDate = null;
                          });
                          _fetchExams();
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Data table
                  Center(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        columnSpacing: 12,
                        headingRowColor:
                            MaterialStateProperty.all(const Color(0xff43a047)),
                        headingTextStyle: GoogleFonts.cairo(
                          textStyle: const TextStyle(
                              color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                        dataTextStyle: GoogleFonts.cairo(
                          textStyle: const TextStyle(color: Colors.black87),
                        ),
                        columns: const [
                          DataColumn(label: Text('رقم الطالب')),
                          DataColumn(label: Text('اسم الطالب')),
                          DataColumn(label: Text('البريد الإلكتروني')),
                          DataColumn(label: Text('الامتحان')),
                          DataColumn(label: Text('العلامة')),
                          DataColumn(label: Text('التاريخ')),
                          DataColumn(label: Text('إجراء')),
                        ],
                        rows: List.generate(displayedExams.length, (idx) {
                          final e = displayedExams[idx];
                          final originalIndex = _exams.indexOf(e);
                          return _buildDataRow(e, originalIndex);
                        }),
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),
                ],
              ),
      ),
    );
  }
}
