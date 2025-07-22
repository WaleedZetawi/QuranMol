import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/api_config.dart';

class PendingScoresPage extends StatefulWidget {
  final bool allColleges;
  final String? college;
  const PendingScoresPage({super.key, this.allColleges = false, this.college});

  @override
  State<PendingScoresPage> createState() => _PendingScoresPageState();
}

class _PendingScoresPageState extends State<PendingScoresPage> {
  static const _greenStart = Color(0xff27ae60);
  static const _greenEnd = Color(0xff219150);
  static const _bgLight = Color(0xfff0faf2);

  bool _busy = true;
  final List<Map<String, dynamic>> _rows = [];
  final Map<int, TextEditingController> _ctrls = {};

  Future<String> _token() async =>
      (await SharedPreferences.getInstance()).getString('token') ?? '';

  Future<void> _load() async {
    setState(() => _busy = true);
    final t = await _token();
    try {
      final r = await Dio().get(
        '${ApiConfig.baseUrl}/pending-scores',
        options: Options(headers: {'Authorization': 'Bearer $t'}),
      );
      if (!mounted) return;
      final data = List<Map<String, dynamic>>.from(r.data);
      final filtered = widget.allColleges
          ? data.where((e) => e['kind'] != 'part')
          : data.where(
              (e) => e['kind'] == 'part' && e['college'] == widget.college,
            );
      _rows
        ..clear()
        ..addAll(filtered);
      for (var e in _rows) {
        final id = e['req_id'] as int;
        _ctrls.putIfAbsent(id, () => TextEditingController());
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveMark(int reqId, double score) async {
    final t = await _token();
    await Dio().post(
      '${ApiConfig.baseUrl}/grade',
      options: Options(headers: {'Authorization': 'Bearer $t'}),
      data: {'request_id': reqId, 'score': score},
    );
    if (!mounted) return;
    setState(() {
      _rows.removeWhere((e) => e['req_id'] == reqId);
      _ctrls.remove(reqId)?.dispose();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('✔︎ تم رصد العلامة', style: GoogleFonts.cairo())),
    );
  }

  Future<void> _deleteRequest(int reqId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: const Text('هل أنت متأكد من حذف هذا الطلب نهائيًا؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('نعم'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      final t = await _token();
      await Dio().delete(
        '${ApiConfig.baseUrl}/exam-requests/$reqId',
        options: Options(headers: {'Authorization': 'Bearer $t'}),
      );
      if (!mounted) return;
      setState(() {
        _rows.removeWhere((e) => e['req_id'] == reqId);
        _ctrls.remove(reqId)?.dispose();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ تم حذف الطلب', style: GoogleFonts.cairo())),
      );
    }
  }

  String _arabicExamName(Map e) {
    if (e['kind'] == 'part' || e['stage'] == 'part') {
      final code = (e['exam_code'] as String?) ?? '';
      final num = int.tryParse(code.replaceAll(RegExp(r'[^\d]'), '')) ?? 0;
      return 'جزء $num';
    }
    final code = (e['exam_code'] as String?) ?? '';
    if (code == 'Q') return 'القرآن كامل';
    if (code == 'H1') return 'خمسة عشر الأولى';
    if (code == 'H2') return 'خمسة عشر الثانية';
    if (code.startsWith('F')) return 'خمسة أجزاء ${code[1]}';
    if (code.startsWith('T')) return 'عشرة أجزاء ${code[1]}';
    return code;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
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
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Image.asset('assets/logo1.png', width: 60, height: 60),
                      const SizedBox(height: 4),
                      Text(
                        'رصد العلامات',
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
              child: Container(
                color: _bgLight,
                child: _busy
                    ? const Center(child: CircularProgressIndicator())
                    : _rows.isEmpty
                    ? Center(
                        child: Text(
                          'لا يوجد امتحانات بانتظار الرصد',
                          style: GoogleFonts.cairo(fontSize: 16),
                        ),
                      )
                    : AnimationLimiter(
                        child: ListView.separated(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemCount: _rows.length,
                          itemBuilder: (_, i) {
                            final e = _rows[i];
                            final reqId = e['req_id'] as int;
                            final ctrl = _ctrls[reqId]!;

                            final dateRaw =
                                e['exam_date'] ??
                                e['date'] ??
                                e['official_date'] ??
                                e['trial_date'];
                            final dateStr = dateRaw == null
                                ? '-'
                                : DateFormat(
                                    'yyyy-MM-dd',
                                  ).format(DateTime.parse(dateRaw.toString()));

                            final stage = (e['stage'] ?? 'part') as String;
                            final stageTxt =
                                {
                                  'trial': 'تجريبي',
                                  'official': 'رسمي',
                                }[stage] ??
                                'جزء';

                            return AnimationConfiguration.staggeredList(
                              position: i,
                              duration: const Duration(milliseconds: 400),
                              child: SlideAnimation(
                                verticalOffset: 50,
                                child: FadeInAnimation(
                                  child: Card(
                                    margin: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    elevation: 4,
                                    child: Padding(
                                      padding: const EdgeInsets.all(16),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            e['student_name'],
                                            style: GoogleFonts.cairo(
                                              textStyle: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 16,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            'الامتحان : ${_arabicExamName(e)}',
                                            style: GoogleFonts.cairo(),
                                          ),
                                          Text(
                                            'المرحلة   : $stageTxt',
                                            style: GoogleFonts.cairo(),
                                          ),
                                          Text(
                                            'التاريخ    : $dateStr',
                                            style: GoogleFonts.cairo(),
                                          ),
                                          if (widget.allColleges)
                                            Text(
                                              'المجمع     : ${e['college']}',
                                              style: GoogleFonts.cairo(),
                                            ),
                                          const SizedBox(height: 12),

                                          Row(
                                            children: [
                                              Expanded(
                                                child: TextField(
                                                  controller: ctrl,
                                                  keyboardType:
                                                      const TextInputType.numberWithOptions(
                                                        decimal: true,
                                                      ),
                                                  inputFormatters: [
                                                    FilteringTextInputFormatter.allow(
                                                      RegExp(
                                                        r'^\d{0,3}([.,]\d{0,2})?$',
                                                      ),
                                                    ),
                                                  ],
                                                  decoration: InputDecoration(
                                                    hintText: 'من 100',
                                                    filled: true,
                                                    fillColor: Colors.white,
                                                    border: OutlineInputBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            12,
                                                          ),
                                                      borderSide:
                                                          BorderSide.none,
                                                    ),
                                                    contentPadding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 12,
                                                          vertical: 8,
                                                        ),
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              ElevatedButton(
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: _greenStart,
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          12,
                                                        ),
                                                  ),
                                                ),
                                                onPressed: () {
                                                  final raw = ctrl.text
                                                      .replaceAll(',', '.');
                                                  final s = double.tryParse(
                                                    raw,
                                                  );
                                                  if (s == null ||
                                                      s < 0 ||
                                                      s > 100) {
                                                    ScaffoldMessenger.of(
                                                      context,
                                                    ).showSnackBar(
                                                      SnackBar(
                                                        content: Text(
                                                          'أدخل رقمًا من 0 إلى 100',
                                                          style:
                                                              GoogleFonts.cairo(),
                                                        ),
                                                      ),
                                                    );
                                                    return;
                                                  }
                                                  _saveMark(reqId, s);
                                                },
                                                child: Text(
                                                  'رَصد',
                                                  style: GoogleFonts.cairo(
                                                    color: Colors.white,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              IconButton(
                                                icon: const Icon(
                                                  Icons.delete,
                                                  color: Colors.red,
                                                ),
                                                tooltip: 'حذف الطلب',
                                                onPressed: () =>
                                                    _deleteRequest(reqId),
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
                      ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
