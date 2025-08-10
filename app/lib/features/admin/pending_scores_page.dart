// lib/pages/pending_scores_page.dart
//
// صفحة «رصد العلامات» بعد تضمين منع الضغط المكرر مع مؤشّر تحميل صغير
// ---------------------------------------------------------------

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../college_theme.dart';
import '../../date_utils.dart';
import '../../services/dio_client.dart';

class PendingScoresPage extends StatefulWidget {
  /// إذا كان المدير العام يرسل allColleges=true
  final bool allColleges;
  final String? college;

  /// تمكين تمرير الألوان يدوياً إن أحببت
  final Color? themeStart;
  final Color? themeEnd;
  final Color? bgLight;

  const PendingScoresPage({
    super.key,
    this.allColleges = false,
    this.college,
    this.themeStart,
    this.themeEnd,
    this.bgLight,
  });

  @override
  State<PendingScoresPage> createState() => _PendingScoresPageState();
}

class _PendingScoresPageState extends State<PendingScoresPage> {
  late final CollegeTheme _th;
  bool _busy = true;

  final List<Map<String, dynamic>> _rows = [];
  final Map<int, TextEditingController> _ctrls = {};

  /// ➊ المعرفات الجاري حفظها لمنع النقر المتكرر على نفس الطلب
  final Set<int> _saving = {};

  @override
  void initState() {
    super.initState();
    if (widget.allColleges) {
      _th = CollegeTheme(
        widget.themeStart ?? const Color(0xff27ae60),
        widget.themeEnd ?? const Color(0xff219150),
        widget.bgLight ?? const Color(0xfff0faf2),
      );
    } else {
      final base = CollegeTheme.byName(widget.college ?? '');
      _th = CollegeTheme(
        widget.themeStart ?? base.start,
        widget.themeEnd ?? base.end,
        widget.bgLight ?? base.bgLight,
      );
    }
    _load();
  }

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    _ctrls.clear();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _busy = true);
    try {
      final dio = DioClient().dio;

      // ✅ لا نرسل gender هنا
      final r = await dio.get('/pending-scores');

      if (!mounted) return;

      final data = List<Map<String, dynamic>>.from(r.data as List);

      // فلترة البيانات حسب النوع والكلية مع التأكد من وجود req_id
      final iterable = widget.allColleges
          // المدير العام: أظهر الامتحانات غير الأجزاء (تجريبي/رسمي)
          ? data.where((e) => e['kind'] != 'part' && e['req_id'] != null)
          // مسؤولو المجمع: أظهر الأجزاء فقط وضمن نفس الكلية
          : data.where((e) =>
              e['kind'] == 'part' &&
              e['college'] == widget.college &&
              e['req_id'] != null);

      _rows
        ..clear()
        ..addAll(iterable);

      for (var e in _rows) {
        final id = e['req_id'] as int;
        _ctrls.putIfAbsent(id, () => TextEditingController());
      }
    } catch (e) {
      debugPrint('load pending-scores error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('فشل تحميل قائمة الرصد', style: GoogleFonts.cairo()),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// يأخذ `stage` مع `request_id`
  Future<void> _saveMark(int reqId, double score, String stage) async {
    // منع الضغط المزدوج بسرعة على نفس الطلب
    if (_saving.contains(reqId)) return;
    setState(() => _saving.add(reqId)); // ➋ تعطيل الزر

    try {
      final dio = DioClient().dio;
      await dio.post(
        '/grade',
        data: {
          'request_id': reqId,
          'score': score,
          'stage': stage,
        },
      );
      if (!mounted) return;
      _ctrls.remove(reqId)?.dispose();
      await _load();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('✔︎ تم رصد العلامة', style: GoogleFonts.cairo())),
      );
    } catch (e) {
      debugPrint('saveMark error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('❌ فشل رصد العلامة', style: GoogleFonts.cairo())),
      );
    } finally {
      if (mounted) {
        setState(() => _saving.remove(reqId)); // ➌ إعادة التمكين
      }
    }
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
              child: const Text('إلغاء')),
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('نعم')),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        final dio = DioClient().dio;
        await dio.delete('/exam-requests/$reqId');
        if (!mounted) return;
        setState(() {
          _rows.removeWhere((e) => e['req_id'] == reqId);
          _ctrls.remove(reqId)?.dispose();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ تم حذف الطلب', style: GoogleFonts.cairo())),
        );
      } catch (e) {
        debugPrint('deleteRequest error: $e');
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('❌ فشل حذف الطلب', style: GoogleFonts.cairo())),
        );
      }
    }
  }

  String _arabicExamName(Map<String, dynamic> e) {
    final stage = (e['stage'] as String?) ?? 'part';
    if (stage == 'part') {
      final code = e['exam_code'] as String? ?? '';
      final num = int.tryParse(code.replaceAll(RegExp(r'[^\d]'), '')) ?? 0;
      return 'جزء $num';
    }
    final code = e['exam_code'] as String? ?? '';
    switch (code) {
      case 'Q':
        return 'القرآن كامل';
      case 'H1':
        return 'خمسة عشر الأولى';
      case 'H2':
        return 'خمسة عشر الثانية';
      default:
        if (code.startsWith('F')) return 'خمسة أجزاء ${code[1]}';
        if (code.startsWith('T')) return 'عشرة أجزاء ${code[1]}';
        return code;
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [_th.start, _th.end],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: SafeArea(
            child: Column(
              children: [
                /* ---------------- HEADER ---------------- */
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [_th.start, _th.end],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ),
                    borderRadius: const BorderRadius.only(
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
                          icon:
                              const Icon(Icons.arrow_back, color: Colors.white),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Image.asset('assets/logo1.png',
                              width: 60, height: 60),
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

                /* ---------------- BODY ---------------- */
                Expanded(
                  child: Container(
                    color: _th.bgLight,
                    child: _busy
                        ? const Center(child: CircularProgressIndicator())
                        : _rows.isEmpty
                            ? Center(
                                child: Text(
                                  'لا يوجد امتحانات بانتظار الرصد',
                                  style: GoogleFonts.cairo(fontSize: 16),
                                ),
                              )
                            : RefreshIndicator(
                                onRefresh: _load,
                                child: AnimationLimiter(
                                  child: ListView.separated(
                                    physics:
                                        const AlwaysScrollableScrollPhysics(),
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 12),
                                    separatorBuilder: (_, __) =>
                                        const SizedBox(height: 8),
                                    itemCount: _rows.length,
                                    itemBuilder: (_, i) {
                                      final e = _rows[i];
                                      final reqId = e['req_id'] as int;
                                      final ctrl = _ctrls[reqId]!;
                                      final stage =
                                          (e['stage'] as String?) ?? 'part';
                                      final stageTxt = {
                                        'part': 'جزء',
                                        'trial': 'تجريبي',
                                        'official': 'رسمي',
                                      }[stage]!;

                                      final dateRaw = e['exam_date'] ??
                                          e['trial_date'] ??
                                          e['official_date'] ??
                                          e['date'];
                                      final dateStr = fmtYMD(dateRaw);

                                      return AnimationConfiguration
                                          .staggeredList(
                                        position: i,
                                        duration:
                                            const Duration(milliseconds: 400),
                                        child: SlideAnimation(
                                          verticalOffset: 50,
                                          child: FadeInAnimation(
                                            child: Card(
                                              margin:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 16),
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                              ),
                                              elevation: 4,
                                              child: Padding(
                                                padding:
                                                    const EdgeInsets.all(16),
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(e['student_name'],
                                                        style:
                                                            GoogleFonts.cairo(
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                                fontSize: 16)),
                                                    const SizedBox(height: 4),
                                                    Text(
                                                        'الامتحان : ${_arabicExamName(e)}',
                                                        style: GoogleFonts
                                                            .cairo()),
                                                    Text(
                                                        'المرحلة   : $stageTxt',
                                                        style: GoogleFonts
                                                            .cairo()),
                                                    Text(
                                                        'التاريخ    : $dateStr',
                                                        style: GoogleFonts
                                                            .cairo()),
                                                    if (widget.allColleges)
                                                      Text(
                                                          'المجمع     : ${e['college']}',
                                                          style: GoogleFonts
                                                              .cairo()),
                                                    const SizedBox(height: 12),
                                                    Row(
                                                      children: [
                                                        Expanded(
                                                          child: TextField(
                                                            controller: ctrl,
                                                            keyboardType:
                                                                const TextInputType
                                                                    .numberWithOptions(
                                                                    decimal:
                                                                        true),
                                                            inputFormatters: [
                                                              FilteringTextInputFormatter
                                                                  .allow(RegExp(
                                                                      r'^\d{0,3}([.,]\d{0,2})?$')),
                                                            ],
                                                            decoration:
                                                                InputDecoration(
                                                              hintText:
                                                                  'من 100',
                                                              filled: true,
                                                              fillColor:
                                                                  Colors.white,
                                                              border:
                                                                  OutlineInputBorder(
                                                                borderRadius:
                                                                    BorderRadius
                                                                        .circular(
                                                                            12),
                                                                borderSide:
                                                                    BorderSide
                                                                        .none,
                                                              ),
                                                              contentPadding:
                                                                  const EdgeInsets
                                                                      .symmetric(
                                                                      horizontal:
                                                                          12,
                                                                      vertical:
                                                                          8),
                                                            ),
                                                          ),
                                                        ),
                                                        const SizedBox(
                                                            width: 8),
                                                        ElevatedButton(
                                                          style: ElevatedButton
                                                              .styleFrom(
                                                            backgroundColor:
                                                                _th.start,
                                                            shape: RoundedRectangleBorder(
                                                                borderRadius:
                                                                    BorderRadius
                                                                        .circular(
                                                                            12)),
                                                          ),
                                                          onPressed:
                                                              _saving.contains(
                                                                      reqId)
                                                                  ? null
                                                                  : () {
                                                                      final raw = ctrl
                                                                          .text
                                                                          .replaceAll(
                                                                              ',',
                                                                              '.');
                                                                      final s =
                                                                          double.tryParse(
                                                                              raw);
                                                                      if (s ==
                                                                              null ||
                                                                          s < 0 ||
                                                                          s > 100) {
                                                                        ScaffoldMessenger.of(context)
                                                                            .showSnackBar(
                                                                          SnackBar(
                                                                            content:
                                                                                Text('أدخل رقمًا من 0 إلى 100', style: GoogleFonts.cairo()),
                                                                          ),
                                                                        );
                                                                        return;
                                                                      }
                                                                      _saveMark(
                                                                          reqId,
                                                                          s,
                                                                          stage);
                                                                    },
                                                          child: _saving
                                                                  .contains(
                                                                      reqId)
                                                              ? const SizedBox(
                                                                  width: 20,
                                                                  height: 20,
                                                                  child: CircularProgressIndicator(
                                                                      strokeWidth:
                                                                          2),
                                                                )
                                                              : Text('رَصد',
                                                                  style: GoogleFonts.cairo(
                                                                      color: Colors
                                                                          .white)),
                                                        ),
                                                        const SizedBox(
                                                            width: 8),
                                                        IconButton(
                                                          icon: const Icon(
                                                              Icons.delete,
                                                              color:
                                                                  Colors.red),
                                                          tooltip: 'حذف الطلب',
                                                          onPressed: () =>
                                                              _deleteRequest(
                                                                  reqId),
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
                ),
              ],
            ),
          ),
        ),
      );
}
