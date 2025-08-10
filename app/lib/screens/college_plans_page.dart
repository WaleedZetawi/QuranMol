import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:google_fonts/google_fonts.dart';

// ما عاد نحتاج ApiConfig/AuthService هنا، لأن DioClient يضيف الـ Authorization تلقائيًا
import '../../services/dio_client.dart';

/// دالة مساعدة عامة لعرض أخطاء Dio (متاحة للصفحتين)
void _showDioError(BuildContext context, DioException e, {String? fallback}) {
  final sc = e.response?.statusCode;
  final uri = e.requestOptions.uri;
  final msg = e.response?.data is Map
      ? (e.response?.data['message']?.toString())
      : e.message;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        'خطأ (${sc ?? '-'}) عند $uri\n${msg ?? fallback ?? 'تعذّر التنفيذ'}',
        style: GoogleFonts.cairo(),
      ),
    ),
  );
}

/// أسماء الامتحانات الرسمية بالعربي (للاستخدام المشترك في الصفحة كلها)
const Map<String, String> kArabicExamNames = {
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

/* ═════════════════════ صفحة متابعة خطط الكلية (محدّثة) ═════════════════════ */

class CollegePlansPage extends StatefulWidget {
  final String college;
  final Color themeStart;
  final Color themeEnd;
  final Color bgLight;

  const CollegePlansPage({
    Key? key,
    required this.college,
    required this.themeStart,
    required this.themeEnd,
    this.bgLight = const Color(0xfff7f8fc),
  }) : super(key: key);

  @override
  State<CollegePlansPage> createState() => _CollegePlansPageState();
}

class _CollegePlansPageState extends State<CollegePlansPage> {
  bool _busy = true;
  List<Map<String, dynamic>> _plans = [];
  List<Map<String, dynamic>> _students = [];

  String _search = '';
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadAll();
    _searchCtrl.addListener(() {
      setState(() => _search = _searchCtrl.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  /* ───────── تحميل البيانات ───────── */
  Future<void> _loadAll() async {
    setState(() => _busy = true);
    try {
      final dio = DioClient().dio;

      // بما أن baseUrl ينتهي بـ /api، لا نضع /api في بداية المسار
      final rpF = dio.get('college-plans');
      final rsF = dio.get('students');

      final results = await Future.wait([rpF, rsF]);
      final rp = results[0] as Response;
      final rs = results[1] as Response;

      final allStudents = List<Map<String, dynamic>>.from(rs.data);
      if (!mounted) return;
      setState(() {
        _plans = List<Map<String, dynamic>>.from(rp.data);
        _students =
            allStudents.where((s) => s['college'] == widget.college).toList();
      });
    } on DioException catch (e) {
      if (!mounted) return;
      _showDioError(context, e, fallback: 'فشل التحميل');
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('فشل التحميل: $err', style: GoogleFonts.cairo())),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /* ───────── عمليات المسؤول ───────── */

  Future<void> _addPlan() async {
    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => _AddPlanPage(
          students: _students,
          themeStart: widget.themeStart,
          themeEnd: widget.themeEnd,
        ),
      ),
    );
    if (created == true) _loadAll();
  }

  Future<void> _decide(int id, bool approved) async {
    setState(() => _busy = true);
    try {
      final dio = DioClient().dio;
      await dio.patch('plans/$id', data: {'approved': approved});
      await _loadAll();
    } on DioException catch (e) {
      if (!mounted) return;
      _showDioError(context, e, fallback: 'خطأ أثناء التحديث');
      setState(() => _busy = false);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('خطأ أثناء التحديث', style: GoogleFonts.cairo())),
      );
      setState(() => _busy = false);
    }
  }

  Future<void> _deletePlanAdmin(int id) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('تأكيد الحذف', style: GoogleFonts.cairo()),
        content:
            Text('هل تريد حذف هذه الخطة نهائيًا؟', style: GoogleFonts.cairo()),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('إلغاء', style: GoogleFonts.cairo())),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text('حذف', style: GoogleFonts.cairo())),
        ],
      ),
    );
    if (sure != true) return;

    setState(() => _busy = true);
    try {
      final dio = DioClient().dio;
      await dio.delete('admin/plans/$id');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم حذف الخطة', style: GoogleFonts.cairo())),
      );
      await _loadAll();
    } on DioException catch (e) {
      if (!mounted) return;
      _showDioError(context, e, fallback: 'خطأ في الحذف');
      setState(() => _busy = false);
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('خطأ في الحذف: $err', style: GoogleFonts.cairo())),
      );
      setState(() => _busy = false);
    }
  }

  /* ───────── ديزاين: Cards + Chips ───────── */

  Color get _chipBg => widget.themeEnd.withOpacity(.12);
  TextStyle get _chipTs =>
      GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.w600);

  Widget _statusChip(String text, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: c.withOpacity(.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.withOpacity(.35)),
        ),
        child: Text(text, style: _chipTs.copyWith(color: c)),
      );

  @override
  Widget build(BuildContext context) {
    final filtered = _plans.where((e) {
      if (_search.isEmpty) return true;
      final name = (e['student_name'] ?? '').toString().toLowerCase();
      final cur = (e['current_part'] ?? '').toString().toLowerCase();
      return name.contains(_search) || cur.contains(_search);
    }).toList();

    return Scaffold(
      backgroundColor: widget.bgLight,
      appBar: AppBar(
        elevation: 0,
        centerTitle: true,
        title: Text('متابعة الخطط',
            style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [widget.themeStart, widget.themeEnd],
              begin: Alignment.centerRight,
              end: Alignment.centerLeft,
            ),
          ),
        ),
      ),
      body: _busy
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadAll,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                children: [
                  // search
                  TextField(
                    controller: _searchCtrl,
                    decoration: InputDecoration(
                      hintText: 'ابحث باسم الطالب أو الجزء الحالي…',
                      prefixIcon: const Icon(Icons.search),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                    ),
                  ),
                  const SizedBox(height: 12),

                  if (filtered.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: const [
                          BoxShadow(
                              color: Colors.black12,
                              blurRadius: 6,
                              offset: Offset(0, 2))
                        ],
                      ),
                      child: Center(
                        child: Text('لا توجد خطط مطابقة',
                            style: GoogleFonts.cairo()),
                      ),
                    ),

                  ...filtered.map((p) {
                    final bool paused = p['paused_for_official'] == true;
                    final int? currentPart = p['current_part'] as int?;
                    final bool? approved = p['approved'] as bool?;
                    final bool overdue = p['is_overdue'] == true ||
                        (p['on_time'] == false && (p['late_days'] ?? 0) > 0);
                    final int lateDays = (p['late_days'] is int)
                        ? p['late_days'] as int
                        : (overdue ? 1 : 0);

                    final String partsInfo = (p['parts_attended'] == true)
                        ? (p['continuation_mode'] == 'specific'
                            ? 'جزء محدد: جزء ${p['specific_part'] ?? '—'}'
                            : 'أجزاء: من ${p['parts_range_start'] ?? '—'} إلى ${p['parts_range_end'] ?? '—'}')
                        : '';

                    String? officialInfo;
                    if (p['official_attended'] == true) {
                      final exams =
                          List<String>.from(p['official_exams'] ?? []);
                      final named =
                          exams.map((c) => kArabicExamNames[c] ?? c).join(', ');
                      officialInfo = 'امتحانات رسمية: ' +
                          (exams.isEmpty ? 'غير محدد' : named);
                    }

                    return Container(
                      margin: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: const [
                          BoxShadow(
                              color: Colors.black12,
                              blurRadius: 6,
                              offset: Offset(0, 2))
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          ListTile(
                            leading: CircleAvatar(
                              backgroundColor: _chipBg,
                              child: Text(
                                  p['student_name']
                                          ?.toString()
                                          .substring(0, 1) ??
                                      '؟',
                                  style: GoogleFonts.cairo(
                                      color: widget.themeStart,
                                      fontWeight: FontWeight.w700)),
                            ),
                            title: Text(p['student_name'] ?? '—',
                                style: GoogleFonts.cairo(
                                    fontWeight: FontWeight.bold, fontSize: 16)),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (partsInfo.isNotEmpty)
                                  Text(partsInfo, style: GoogleFonts.cairo()),
                                if (officialInfo != null)
                                  Text(officialInfo,
                                      style: GoogleFonts.cairo()),
                                const SizedBox(height: 4),
                                Text('الجزء الحالي: ${currentPart ?? '—'}',
                                    style: GoogleFonts.cairo(
                                        fontStyle: FontStyle.italic)),
                                Text(
                                    'من ${p['start'] ?? '—'} إلى ${p['due'] ?? '—'}',
                                    style: GoogleFonts.cairo()),
                              ],
                            ),
                            trailing: Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                if (approved == null)
                                  _statusChip('بانتظار', Colors.amber.shade800)
                                else if (approved == true)
                                  _statusChip('موافق', Colors.green.shade700)
                                else
                                  _statusChip('مرفوض', Colors.red.shade600),
                                if (paused)
                                  _statusChip('موقوف لرسمي', Colors.indigo),
                                if (overdue)
                                  _statusChip('متأخر ${lateDays.abs()} يوم',
                                      Colors.red),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline),
                                  color: Colors.red.shade600,
                                  tooltip: 'حذف الخطة',
                                  onPressed: () =>
                                      _deletePlanAdmin(p['id'] as int),
                                ),
                              ],
                            ),
                          ),

                          // أزرار الموافقة/الرفض
                          if (approved == null)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      icon: const Icon(Icons.check),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.green.shade700,
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(12)),
                                      ),
                                      label: Text('قبول',
                                          style: GoogleFonts.cairo(
                                              color: Colors.white)),
                                      onPressed: () =>
                                          _decide(p['id'] as int, true),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      icon: const Icon(Icons.close),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.red.shade600,
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(12)),
                                      ),
                                      label: Text('رفض',
                                          style: GoogleFonts.cairo(
                                              color: Colors.white)),
                                      onPressed: () =>
                                          _decide(p['id'] as int, false),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          const SizedBox(height: 8),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addPlan,
        icon: const Icon(Icons.add),
        label: Text('إضافة خطة', style: GoogleFonts.cairo()),
        backgroundColor: widget.themeStart,
        foregroundColor: Colors.white,
      ),
    );
  }
}

/* ═════════════════════ صفحة إضافة خطة جديدة (محدّثة) ═════════════════════ */

class _AddPlanPage extends StatefulWidget {
  final List<Map<String, dynamic>> students;
  final Color themeStart;
  final Color themeEnd;
  const _AddPlanPage({
    Key? key,
    required this.students,
    required this.themeStart,
    required this.themeEnd,
  }) : super(key: key);

  @override
  State<_AddPlanPage> createState() => _AddPlanPageState();
}

class _AddPlanPageState extends State<_AddPlanPage> {
  int _currentStep = 0;
  bool _busy = false;

  int? _studentId;
  String _studentType = 'regular'; // regular | intensive

  bool _heardOfficial = false;
  final List<String> _officialExams = [];

  bool _heardParts = false;
  int _partsRangeStart = 1;
  int _partsRangeEnd = 1;

  String _continuationMode =
      'from_start'; // from_start | specific | from_end(اختياري لو حبيت)
  int? _specificPart;

  int _durationWeeks = 1;
  final _weekOptions = [1, 2, 3, 4, 5, 6];

  List<String> get _allowedOfficial {
    return _studentType == 'intensive'
        ? const ['T1', 'T2', 'T3', 'H1', 'H2', 'Q']
        : const ['F1', 'F2', 'F3', 'F4', 'F5', 'F6'];
  }

  Future<void> _submit() async {
    if (_studentId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('اختر الطالب أولاً', style: GoogleFonts.cairo())),
      );
      return;
    }
    if (_heardParts && _partsRangeEnd < _partsRangeStart) {
      _partsRangeEnd = _partsRangeStart;
    }
    if (_continuationMode == 'specific' && (_specificPart == null)) {
      _specificPart = _partsRangeStart;
    }

    setState(() => _busy = true);
    try {
      final dio = DioClient().dio;
      // ملاحظة: المسار بدون /api لأن baseUrl ينتهي بـ /api
      await dio.post('admin/plans', data: {
        'student_id': _studentId,
        'official_attended': _heardOfficial,
        'official_exams': _officialExams,
        'parts_attended': _heardParts,
        'parts_range_start': _heardParts ? _partsRangeStart : null,
        'parts_range_end': _heardParts ? _partsRangeEnd : null,
        'continuation_mode': _continuationMode,
        'specific_part': _continuationMode == 'specific' ? _specificPart : null,
        'duration_type': 'week',
        'duration_value': _durationWeeks,
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم إضافة الخطة', style: GoogleFonts.cairo())),
      );
      Navigator.pop(context, true);
    } on DioException catch (e) {
      if (!mounted) return;
      _showDioError(context, e, fallback: 'خطأ في الإضافة');
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('خطأ في الإضافة: $err', style: GoogleFonts.cairo())),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final steps = <Step>[
      Step(
        title: Text('اختر الطالب', style: GoogleFonts.cairo()),
        content: DropdownButtonFormField<int>(
          decoration: InputDecoration(
            labelText: 'طالب',
            labelStyle: GoogleFonts.cairo(),
          ),
          items: widget.students
              .map((s) => DropdownMenuItem(
                    value: s['id'] as int,
                    child: Text('${s['name']} (${s['reg_number']})',
                        style: GoogleFonts.cairo()),
                  ))
              .toList(),
          value: _studentId,
          onChanged: (v) => setState(() {
            _studentId = v;
            _studentType =
                widget.students.firstWhere((s) => s['id'] == v)['student_type']
                        as String? ??
                    'regular';
          }),
        ),
        isActive: _currentStep >= 0,
        state: _currentStep > 0 ? StepState.complete : StepState.indexed,
      ),
      Step(
        title: Text('الرسمي', style: GoogleFonts.cairo()),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SwitchListTile(
              title: Text(
                  _heardOfficial ? 'سمع عن الرسمي' : 'لم يسمع عن الرسمي',
                  style: GoogleFonts.cairo()),
              value: _heardOfficial,
              onChanged: (v) => setState(() => _heardOfficial = v),
            ),
            if (_heardOfficial)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _allowedOfficial.map((code) {
                  final sel = _officialExams.contains(code);
                  return FilterChip(
                    label: Text(kArabicExamNames[code] ?? code,
                        style: GoogleFonts.cairo()),
                    selected: sel,
                    onSelected: (s) => setState(() {
                      if (s) {
                        if (!_officialExams.contains(code)) {
                          _officialExams.add(code);
                        }
                      } else {
                        _officialExams.remove(code);
                      }
                    }),
                  );
                }).toList(),
              ),
          ],
        ),
        isActive: _currentStep >= 1,
        state: _currentStep > 1 ? StepState.complete : StepState.indexed,
      ),
      Step(
        title: Text('الأجزاء', style: GoogleFonts.cairo()),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SwitchListTile(
              title: Text(_heardParts ? 'سمع عن الأجزاء' : 'لم يسمع عن الأجزاء',
                  style: GoogleFonts.cairo()),
              value: _heardParts,
              onChanged: (v) => setState(() => _heardParts = v),
            ),
            if (_heardParts) ...[
              DropdownButtonFormField<int>(
                decoration: InputDecoration(
                    labelText: 'من جزء', labelStyle: GoogleFonts.cairo()),
                items: List.generate(30, (i) => i + 1)
                    .map((p) => DropdownMenuItem(
                        value: p,
                        child: Text('جزء $p', style: GoogleFonts.cairo())))
                    .toList(),
                value: _partsRangeStart,
                onChanged: (v) => setState(() {
                  _partsRangeStart = v!;
                  if (_partsRangeEnd < v) _partsRangeEnd = v;
                }),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                decoration: InputDecoration(
                    labelText: 'إلى جزء', labelStyle: GoogleFonts.cairo()),
                items: List.generate(30, (i) => i + 1)
                    .map((p) => DropdownMenuItem(
                        value: p,
                        child: Text('جزء $p', style: GoogleFonts.cairo())))
                    .toList(),
                value: _partsRangeEnd,
                onChanged: (v) => setState(() => _partsRangeEnd =
                    (v! < _partsRangeStart) ? _partsRangeStart : v),
              ),
            ],
          ],
        ),
        isActive: _currentStep >= 2,
        state: _currentStep > 2 ? StepState.complete : StepState.indexed,
      ),
      Step(
        title: Text('نقطة البداية', style: GoogleFonts.cairo()),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            RadioListTile<String>(
              title: Text('من البداية', style: GoogleFonts.cairo()),
              value: 'from_start',
              groupValue: _continuationMode,
              onChanged: (v) => setState(() {
                _continuationMode = v!;
                _specificPart = null;
              }),
            ),
            RadioListTile<String>(
              title: Text('جزء محدد', style: GoogleFonts.cairo()),
              value: 'specific',
              groupValue: _continuationMode,
              onChanged: (v) => setState(() => _continuationMode = v!),
            ),
            if (_continuationMode == 'specific')
              DropdownButtonFormField<int>(
                decoration: InputDecoration(
                    labelText: 'جزء البداية', labelStyle: GoogleFonts.cairo()),
                items: List.generate(30, (i) => i + 1)
                    .map((p) => DropdownMenuItem(
                        value: p,
                        child: Text('جزء $p', style: GoogleFonts.cairo())))
                    .toList(),
                value: _specificPart ?? _partsRangeStart,
                onChanged: (v) => setState(() => _specificPart = v),
              ),
          ],
        ),
        isActive: _currentStep >= 3,
        state: _currentStep > 3 ? StepState.complete : StepState.indexed,
      ),
      Step(
        title: Text('المدة', style: GoogleFonts.cairo()),
        content: DropdownButtonFormField<int>(
          decoration: InputDecoration(
              labelText: 'عدد الأسابيع', labelStyle: GoogleFonts.cairo()),
          items: _weekOptions
              .map((w) => DropdownMenuItem(
                  value: w,
                  child: Text('$w أسابيع', style: GoogleFonts.cairo())))
              .toList(),
          value: _durationWeeks,
          onChanged: (v) => setState(() => _durationWeeks = v!),
        ),
        isActive: _currentStep >= 4,
        state: _currentStep > 4 ? StepState.complete : StepState.indexed,
      ),
      Step(
        title: Text('مراجعة', style: GoogleFonts.cairo()),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'طالب: ${widget.students.firstWhere((s) => s['id'] == _studentId, orElse: () => {
                    'name': ''
                  })['name']}',
              style: GoogleFonts.cairo(),
            ),
            const SizedBox(height: 8),
            Text(
                'رسمي: ${_heardOfficial ? 'نعم (${_officialExams.join(', ')})' : 'لا'}',
                style: GoogleFonts.cairo()),
            const SizedBox(height: 8),
            Text(
                'أجزاء: ${_heardParts ? 'نعم من $_partsRangeStart إلى $_partsRangeEnd' : 'لا'}',
                style: GoogleFonts.cairo()),
            const SizedBox(height: 8),
            Text(
              'نقطة البداية: ${_continuationMode == 'from_start' ? 'من البداية' : 'جزء $_specificPart'}',
              style: GoogleFonts.cairo(),
            ),
            const SizedBox(height: 8),
            Text('مدة: $_durationWeeks أسابيع', style: GoogleFonts.cairo()),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _busy ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: widget.themeStart,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(_busy ? 'جاري الحفظ...' : 'حفظ الخطة',
                  style: GoogleFonts.cairo(color: Colors.white)),
            ),
          ],
        ),
        isActive: _currentStep >= 5,
        state: _currentStep == 5 ? StepState.editing : StepState.indexed,
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text('إضافة خطة طالب', style: GoogleFonts.cairo()),
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [widget.themeStart, widget.themeEnd],
              begin: Alignment.centerRight,
              end: Alignment.centerLeft,
            ),
          ),
        ),
      ),
      body: Stepper(
        type: StepperType.vertical,
        currentStep: _currentStep,
        onStepContinue: _busy
            ? null
            : () {
                if (_currentStep < steps.length - 1) {
                  setState(() => _currentStep++);
                } else {
                  _submit();
                }
              },
        onStepCancel: _busy || _currentStep == 0
            ? null
            : () => setState(() => _currentStep--),
        controlsBuilder: (ctx, details) {
          final isLast = _currentStep == steps.length - 1;
          return Row(
            children: [
              ElevatedButton(
                onPressed: details.onStepContinue,
                style: ElevatedButton.styleFrom(
                  backgroundColor: widget.themeStart,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                child: Text(isLast ? 'حفظ' : 'التالي',
                    style: GoogleFonts.cairo(color: Colors.white)),
              ),
              const SizedBox(width: 12),
              if (_currentStep > 0)
                TextButton(
                  onPressed: details.onStepCancel,
                  child: Text('رجوع',
                      style: GoogleFonts.cairo(color: widget.themeStart)),
                ),
            ],
          );
        },
        steps: steps,
      ),
    );
  }
}
