// lib/pages/reports/college_parts_report_page.dart
import 'dart:async';
import 'dart:typed_data';
import 'dart:io' show File, SocketException;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// Web only
import 'dart:html' as html;

// Mobile/Desktop only
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';

import '../../services/api_config.dart';
import '../../services/auth_service.dart';

class CollegePartsReportPage extends StatefulWidget {
  final String college; // 'Engineering' | 'Medical' | 'Sharia' | ...
  final Color themeStart;
  final Color themeEnd;
  final Color bgLight;
  const CollegePartsReportPage({
    Key? key,
    required this.college,
    required this.themeStart,
    required this.themeEnd,
    this.bgLight = const Color(0xfff5f5f5),
  }) : super(key: key);

  @override
  State<CollegePartsReportPage> createState() => _CollegePartsReportPageState();
}

class _CollegePartsReportPageState extends State<CollegePartsReportPage> {
  bool _loading = true;
  List<Map<String, dynamic>> _rows = [];

  DateTime? _startDate;
  DateTime? _endDate;

  String _searchQuery = '';
  final _searchCtrl = TextEditingController();

  final Map<String, String> _jNames = {
    for (int i = 1; i <= 30; i++) 'J${i.toString().padLeft(2, '0')}': 'جزء $i',
  };

  @override
  void initState() {
    super.initState();
    _load();
    _searchCtrl.addListener(() {
      setState(() => _searchQuery = _searchCtrl.text.trim());
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // Helpers
  bool _isOfficial(Map<String, dynamic> e) => e['official'] == true;
  num? _scoreOf(Map<String, dynamic> e) =>
      e['score'] is num ? e['score'] as num : null;

  // ===== الإحصاءات (من الرسمية فقط وتجاهل score == null) =====
  int get total => _rows.where(_isOfficial).length;

  int get above98 => _rows.where((e) {
        final sc = _scoreOf(e);
        return _isOfficial(e) && sc != null && sc > 98;
      }).length;

  int get between95and98 => _rows.where((e) {
        final sc = _scoreOf(e);
        return _isOfficial(e) && sc != null && sc >= 95 && sc <= 98;
      }).length;

  int get failed => _rows.where((e) {
        final sc = _scoreOf(e);
        return _isOfficial(e) && sc != null && sc < 60;
      }).length;

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final token = await AuthService.token ?? '';
      final resp = await Dio().get<List>(
        '${ApiConfig.baseUrl}/exams/parts-report',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
        queryParameters: {
          'college': widget.college,
          if (_startDate != null)
            'start': _startDate!.toIso8601String().split('T').first,
          if (_endDate != null)
            'end': _endDate!.toIso8601String().split('T').first,
        },
      );
      _rows = List<Map<String, dynamic>>.from(resp.data!);
    } on SocketException {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('فشل الاتصال')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('خطأ: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _editScore(int idx) async {
    final exam = _rows[idx];

    // منع تعديل إدخالات الخطة (official == false)
    if (!_isOfficial(exam)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا يمكن تعديل إدخال تم إضافته من الخطة')),
      );
      return;
    }

    final controller =
        TextEditingController(text: _scoreOf(exam)?.toString() ?? '');
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

    try {
      final token = await AuthService.token ?? '';
      await Dio().post(
        '${ApiConfig.baseUrl}/grade',
        options: Options(
          headers: {'Authorization': 'Bearer $token'},
          contentType: Headers.jsonContentType,
        ),
        data: {
          'exam_id': exam['exam_id'], // parts-report يرجع exam_id
          'score': num.parse(controller.text),
        },
      );
      await _load();
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
    final exam = _rows[idx];
    final sure = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: Text(
          'حذف علامة الطالب:\n'
          '${exam['student_name']} - ${_jNames[exam['exam_code']] ?? exam['exam_code']} ؟',
          style: GoogleFonts.cairo(),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('حذف', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (sure != true) return;

    try {
      final token = await AuthService.token ?? '';
      await Dio().delete(
        '${ApiConfig.baseUrl}/exams/${exam['exam_id']}',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      setState(() => _rows.removeAt(idx));
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
    // نجمع الأسابيع من الرسمية فقط
    final weeksSet = <int>{};
    for (var e in _rows.where(_isOfficial)) {
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

    final uri = Uri.parse(
      '${ApiConfig.baseUrl}/reports/parts-excel'
      '?college=${widget.college}'
      '&weeks=${selected.join(',')}',
    );

    final token = await AuthService.token;
    if (token == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('لم يتم تسجيل الدخول')));
      return;
    }

    if (kIsWeb) {
      try {
        setState(() => _loading = true);
        final resp = await Dio().get<Uint8List>(
          uri.toString(),
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
          ..setAttribute('download', 'parts_report.xlsx')
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

    try {
      setState(() => _loading = true);
      final response = await Dio().getUri(
        uri,
        options: Options(
          responseType: ResponseType.bytes,
          headers: {'Authorization': 'Bearer $token'},
        ),
      );
      final bytes = response.data as List<int>;
      final dir = await getTemporaryDirectory();
      final filePath =
          '${dir.path}/parts_report_${DateTime.now().millisecondsSinceEpoch}.xlsx';
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

  Widget _summaryCard(String label, int value, IconData icon, List<Color> g) {
    return Container(
      width: 120,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
            colors: g, begin: Alignment.topLeft, end: Alignment.bottomRight),
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
    final greenGrad = [widget.themeStart, widget.themeEnd];

    final filtered = _rows.where((e) {
      final q = _searchQuery.toLowerCase();
      return e['reg_number'].toString().toLowerCase().contains(q) ||
          (e['student_name'] as String).toLowerCase().contains(q);
    }).toList();

    return Scaffold(
      backgroundColor: widget.bgLight,
      appBar: AppBar(
        elevation: 2,
        centerTitle: true,
        title: Text(
          'كشف علامات الأجزاء - ${widget.college}',
          style: GoogleFonts.cairo(
              textStyle: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold)),
        ),
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
                begin: Alignment.centerRight,
                end: Alignment.centerLeft,
                colors: greenGrad),
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
                  // search
                  TextField(
                    controller: _searchCtrl,
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

                  // export
                  ElevatedButton.icon(
                    icon: const Icon(Icons.file_upload),
                    label: const Text('تصدير Excel'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: greenGrad.last,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: _exportExcel,
                  ),
                  const SizedBox(height: 16),

                  // summary
                  Center(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _summaryCard('إجمالي', total, Icons.list, greenGrad),
                          const SizedBox(width: 12),
                          _summaryCard('أعلى من 98', above98, Icons.star,
                              const [Color(0xffffb300), Color(0xffffca28)]),
                          const SizedBox(width: 12),
                          _summaryCard(
                              '95–98',
                              between95and98,
                              Icons.emoji_events,
                              const [Color(0xff1976d2), Color(0xff42a5f5)]),
                          const SizedBox(width: 12),
                          _summaryCard('رسوب', failed, Icons.clear,
                              const [Color(0xffc62828), Color(0xffe53935)]),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // date filter
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: widget.themeEnd),
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
                            style: GoogleFonts.cairo(color: widget.themeStart),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: widget.themeEnd),
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
                            style: GoogleFonts.cairo(color: widget.themeStart),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: widget.themeStart,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: _load,
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
                          _load();
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // table
                  Center(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        columnSpacing: 12,
                        headingRowColor:
                            MaterialStateProperty.all(widget.themeStart),
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
                          DataColumn(label: Text('الجزء')),
                          DataColumn(label: Text('العلامة')),
                          DataColumn(label: Text('التاريخ')),
                          DataColumn(label: Text('إجراء')),
                        ],
                        rows: List.generate(filtered.length, (idx) {
                          final e = filtered[idx];
                          final original = _rows.indexOf(e);
                          final isOfficial = _isOfficial(e);
                          final score = _scoreOf(e);

                          return DataRow(cells: [
                            DataCell(Text(e['reg_number'] ?? '-')),
                            DataCell(Text(e['student_name'] ?? '-')),
                            DataCell(Text(e['email'] ?? '-')),
                            DataCell(Text(_jNames[e['exam_code']] ??
                                e['exam_code'] ??
                                '-')),
                            // العلامة: لو ما في قيمة → "ناجح"
                            DataCell(Text(
                                score == null ? 'ناجح' : score.toString())),
                            DataCell(Text(
                                (e['created_at'] as String).split('T').first)),
                            DataCell(Row(
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit,
                                      color: Colors.blueAccent),
                                  onPressed: isOfficial
                                      ? () => _editScore(original)
                                      : null,
                                  tooltip: isOfficial
                                      ? 'تعديل'
                                      : 'لا يمكن تعديل إدخال من الخطة',
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete,
                                      color: Colors.red),
                                  onPressed: () => _deleteExam(original),
                                ),
                              ],
                            )),
                          ]);
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
