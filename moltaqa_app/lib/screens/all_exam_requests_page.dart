import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/api_config.dart';

class AllExamRequestsPage extends StatefulWidget {
  const AllExamRequestsPage({super.key});
  @override
  State<AllExamRequestsPage> createState() => _AllExamRequestsPageState();
}

class _AllExamRequestsPageState extends State<AllExamRequestsPage> {
  static const _greenStart = Color(0xff27ae60);
  static const _greenEnd = Color(0xff219150);
  static const _bgLight = Color(0xfff0faf2);

  bool _busy = true;
  List<Map<String, dynamic>> _rows = [];
  List<Map<String, dynamic>> _sup = [];

  Future<String> _token() async =>
      (await SharedPreferences.getInstance()).getString('token') ?? '';

  Future<void> _load() async {
    setState(() => _busy = true);
    final t = await _token();
    final dio = Dio(BaseOptions(headers: {'Authorization': 'Bearer $t'}));
    try {
      final r1 = await dio.get('${ApiConfig.baseUrl}/exam-requests');
      final r2 = await dio.get('${ApiConfig.baseUrl}/supervisors');
      if (!mounted) return;
      _rows = List<Map<String, dynamic>>.from(r1.data);
      _sup = List<Map<String, dynamic>>.from(r2.data);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _update(
    int id,
    int? trial,
    int? doc,
    bool ok, {
    String? date,
  }) async {
    final t = await _token();
    final dio = Dio(BaseOptions(headers: {'Authorization': 'Bearer $t'}));
    await dio.patch(
      '${ApiConfig.baseUrl}/exam-requests/$id',
      data: {
        'approved': ok,
        'supervisor_trial_id': trial,
        'supervisor_official_id': doc,
        'official_date': date,
      },
    );
    _load();
  }

  Future<void> _delete(int id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: const Text('هل أنت متأكد من حذف هذا الطلب نهائيًا؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      final t = await _token();
      final dio = Dio(BaseOptions(headers: {'Authorization': 'Bearer $t'}));
      await dio.delete('${ApiConfig.baseUrl}/exam-requests/$id');
      _load();
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Widget build(BuildContext ctx) {
    // هنا نفصل منطق العرض لتجنّب الـ “dead code”
    Widget content;
    if (_busy) {
      content = const Center(child: CircularProgressIndicator());
    } else if (_rows.isEmpty) {
      content = Center(
        child: Text('لا توجد طلبات', style: GoogleFonts.cairo(fontSize: 16)),
      );
    } else {
      content = AnimationLimiter(
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 12),
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemCount: _rows.length,
          itemBuilder: (_, i) {
            final e = _rows[i];
            final trial = _sup.where((s) => s['is_trial'] == true).toList();
            final doctor = _sup.where((s) => s['is_doctor'] == true).toList();

            final trialDt = e['trial_date'] == null
                ? '-'
                : DateFormat(
                    'yyyy-MM-dd',
                  ).format(DateTime.parse(e['trial_date']));
            final offDt = e['official_date'] == null
                ? '-'
                : DateFormat(
                    'yyyy-MM-dd',
                  ).format(DateTime.parse(e['official_date']));

            String nameAR(String? code) {
              if (code == null) return '—';
              if (code.startsWith('F')) return 'خمسة أجزاء ${code[1]}';
              if (code.startsWith('T')) return 'عشرة أجزاء ${code[1]}';
              if (code == 'H1') return 'خمسة عشر الأولى';
              if (code == 'H2') return 'خمسة عشر الثانية';
              if (code == 'Q') return 'القرآن كامل';
              return code;
            }

            return AnimationConfiguration.staggeredList(
              position: i,
              duration: const Duration(milliseconds: 400),
              child: SlideAnimation(
                verticalOffset: 50,
                child: FadeInAnimation(
                  child: Card(
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${e['student_name']} • ${e['college']}',
                            style: GoogleFonts.cairo(
                              textStyle: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'نوع الطلب: ${nameAR(e['exam_code'] as String?)}',
                            style: GoogleFonts.cairo(),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'التجريبي: $trialDt',
                            style: GoogleFonts.cairo(),
                          ),
                          Text('رسمي  : $offDt', style: GoogleFonts.cairo()),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: _dd(
                                  trial,
                                  e['supervisor_trial_id'],
                                  (v) => setState(
                                    () => e['supervisor_trial_id'] = v,
                                  ),
                                  'مشرف التجريبي',
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _dd(
                                  doctor,
                                  e['supervisor_official_id'],
                                  (v) => setState(
                                    () => e['supervisor_official_id'] = v,
                                  ),
                                  'مشرف رسمي',
                                ),
                              ),
                            ],
                          ),
                          if (e['official_date'] == null) ...[
                            const SizedBox(height: 8),
                            InkWell(
                              onTap: () async {
                                final now = DateTime.now();
                                final d = await showDatePicker(
                                  context: ctx,
                                  initialDate: now,
                                  firstDate: now,
                                  lastDate: now.add(const Duration(days: 365)),
                                  locale: const Locale('ar'),
                                );
                                if (d != null) {
                                  setState(
                                    () => e['official_date'] = d
                                        .toIso8601String(),
                                  );
                                }
                              },
                              child: InputDecorator(
                                decoration: InputDecoration(
                                  labelText: 'حدد موعد الرسمي',
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: Text(
                                  'اضغط للاختيار',
                                  style: GoogleFonts.cairo(),
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: _bigBtn(
                                  'قبول',
                                  _greenStart,
                                  Icons.check,
                                  () => _update(
                                    e['id'],
                                    e['supervisor_trial_id'],
                                    e['supervisor_official_id'],
                                    true,
                                    date: e['official_date'],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.red,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  onPressed: () async {
                                    final confirm = await showDialog<bool>(
                                      context: ctx,
                                      builder: (dialogCtx) => AlertDialog(
                                        title: const Text('تأكيد الرفض'),
                                        content: const Text(
                                          'هل أنت متأكد من رفض هذا الطلب؟',
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () => Navigator.of(
                                              dialogCtx,
                                            ).pop(false),
                                            child: const Text('إلغاء'),
                                          ),
                                          TextButton(
                                            onPressed: () => Navigator.of(
                                              dialogCtx,
                                            ).pop(true),
                                            child: const Text('رفض'),
                                          ),
                                        ],
                                      ),
                                    );
                                    if (confirm == true) {
                                      _update(e['id'], null, null, false);
                                    }
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        const Icon(
                                          Icons.close,
                                          color: Colors.white,
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          'رفض',
                                          style: GoogleFonts.cairo(
                                            color: Colors.white,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                icon: const Icon(
                                  Icons.delete,
                                  color: Colors.red,
                                ),
                                onPressed: () => _delete(e['id']),
                                tooltip: 'حذف الطلب',
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      );
    }

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [_greenStart, _greenEnd],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // HEADER
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [_greenStart, _greenEnd],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(24),
                    bottomRight: Radius.circular(24),
                  ),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Positioned(
                      right: 8,
                      child: IconButton(
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Image.asset('assets/logo1.png', width: 60, height: 60),
                        const SizedBox(height: 4),
                        Text(
                          'طلبات الامتحانات',
                          style: GoogleFonts.cairo(
                            textStyle: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // BODY
              Expanded(
                child: Container(color: _bgLight, child: content),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dd(List src, int? val, Function(int?) set, String hint) =>
      DropdownButtonFormField<int>(
        value: val,
        hint: Text(hint, style: GoogleFonts.cairo()),
        decoration: InputDecoration(
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 4,
          ),
        ),
        items: src
            .map(
              (s) => DropdownMenuItem<int>(
                value: s['id'] as int,
                child: Text(s['name'], style: GoogleFonts.cairo()),
              ),
            )
            .toList(),
        onChanged: set,
      );

  Widget _bigBtn(String txt, Color c, IconData icn, VoidCallback f) =>
      ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: c,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        onPressed: f,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icn, color: Colors.white),
              const SizedBox(width: 6),
              Text(txt, style: GoogleFonts.cairo(color: Colors.white)),
            ],
          ),
        ),
      );
}
