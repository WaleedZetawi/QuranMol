import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/dio_client.dart';

class StudentPlansPage extends StatefulWidget {
  final String studentType; // 'regular' | 'intensive'
  const StudentPlansPage({Key? key, required this.studentType})
      : super(key: key);

  @override
  State<StudentPlansPage> createState() => _StudentPlansPageState();
}

/* ────────────────────────────────────────────────────────── */

class _StudentPlansPageState extends State<StudentPlansPage> {
  // حالة
  bool _isEditing = false,
      _busy = false,
      _isOverdue = false,
      _pausedForOfficial = false;
  int? _planId;

  // بيانات
  bool _heardOfficial = false;
  List<String> _officialExams = [];
  bool _heardParts = false;
  int _partsRangeStart = 1, _partsRangeEnd = 1;
  String _continuationMode = 'from_start';
  int? _specificPart;
  int _durationWeeks = 1;
  final _weekOptions = [1, 2, 3, 4, 5, 6];

  // Stepper
  int _currentStep = 0;

  static const _arabicName = {
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

  Color get _primary => const Color(0xFF2E7D32);
  final Color _bg = const Color(0xFFF5F7F8);
  final Color _field = const Color(0xFFF3F6F6);

  @override
  void initState() {
    super.initState();
    _fetchExistingPlan();
  }

  /* ───────── API ───────── */

  Future<void> _fetchExistingPlan() async {
    try {
      final resp = await DioClient().dio.get('/plans/me');
      final plan = resp.data as Map<String, dynamic>? ?? {};
      if (plan.isNotEmpty && plan['approved'] == true) {
        setState(() {
          _isEditing = true;
          _planId = plan['id'];
          _heardOfficial = plan['official_attended'] ?? false;
          _officialExams = List<String>.from(plan['official_exams'] ?? []);
          _heardParts = plan['parts_attended'] ?? false;
          _partsRangeStart = plan['parts_range_start'] ?? 1;
          _partsRangeEnd = plan['parts_range_end'] ?? _partsRangeStart;
          _continuationMode = plan['continuation_mode'] ?? 'from_start';
          _specificPart = plan['specific_part'];
          _durationWeeks = plan['duration_value'] ?? 1;
          _isOverdue = plan['is_overdue'] ?? false;
          _pausedForOfficial = plan['paused_for_official'] ?? false;
        });
      }
    } catch (_) {}
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    final data = {
      'official_attended': _heardOfficial,
      'official_exams': _officialExams,
      'parts_attended': _heardParts,
      'parts_range_start': _heardParts ? _partsRangeStart : null,
      'parts_range_end': _heardParts ? _partsRangeEnd : null,
      'continuation_mode': _continuationMode,
      'specific_part': _continuationMode == 'specific' ? _specificPart : null,
      'duration_type': 'week',
      'duration_value': _durationWeeks,
    };
    try {
      await DioClient().dio.post('/plans', data: data);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('تم حفظ الخطة بنجاح', style: GoogleFonts.cairo()),
        behavior: SnackBarBehavior.floating,
      ));
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('فشل الحفظ: $e', style: GoogleFonts.cairo()),
        behavior: SnackBarBehavior.floating,
      ));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmDelete() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('تأكيد الحذف', style: GoogleFonts.cairo()),
        content: Text('هل أنت متأكد من حذف الخطة؟', style: GoogleFonts.cairo()),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: Text('إلغاء', style: GoogleFonts.cairo())),
          TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text('حذف', style: GoogleFonts.cairo())),
        ],
      ),
    );
    if (yes == true) _deletePlan();
  }

  Future<void> _deletePlan() async {
    if (_planId == null) return;
    setState(() => _busy = true);
    try {
      await DioClient().dio.delete('/plans/$_planId');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('تم حذف الخطة', style: GoogleFonts.cairo()),
        behavior: SnackBarBehavior.floating,
      ));
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('خطأ في الحذف: $e', style: GoogleFonts.cairo()),
        behavior: SnackBarBehavior.floating,
      ));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /* ───────── UI ───────── */

  @override
  Widget build(BuildContext context) {
    const regularExams = ['F1', 'F2', 'F3', 'F4', 'F5', 'F6'];
    const intensiveExams = ['T1', 'T2', 'T3', 'H1', 'H2', 'Q'];
    final allowedCodes =
        widget.studentType == 'intensive' ? intensiveExams : regularExams;

    // رأس ناعم
    final header = Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
            colors: [Color(0xFFE9F7ED), Color(0xFFCDEDD6)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(_isEditing ? 'تعديل مدة الخطة' : 'اختيار خطتي',
              style: GoogleFonts.cairo(
                  fontSize: 18, fontWeight: FontWeight.w800, color: _primary)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: -6,
            alignment: WrapAlignment.center,
            children: [
              if (_pausedForOfficial)
                _pill('موقوفة لرسمي', Colors.orange.shade700),
              if (_isOverdue) _pill('متأخر', Colors.red.shade700),
              _softTag('المدة: $_durationWeeks أسبوع'),
              if (_heardParts)
                _softTag('الأجزاء: $_partsRangeStart–$_partsRangeEnd'),
            ],
          ),
        ],
      ),
    );

    final theme = Theme.of(context).copyWith(
      colorScheme: Theme.of(context)
          .colorScheme
          .copyWith(primary: _primary, secondary: _primary),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: _field,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
      chipTheme: Theme.of(context).chipTheme.copyWith(
            backgroundColor: const Color(0xFFF3F6F6),
            selectedColor: const Color(0xFFD6F1DB),
            labelStyle: GoogleFonts.cairo(),
          ),
    );

    // صفحة تعديل مختصرة (نعمة)
    if (_isEditing) {
      return Scaffold(
        backgroundColor: _bg,
        appBar: AppBar(
          elevation: 0,
          title: Text('تعديل مدة الخطة',
              style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
          centerTitle: true,
          actions: [
            IconButton(
                onPressed: _busy ? null : _confirmDelete,
                icon: const Icon(Icons.delete_outline))
          ],
          flexibleSpace: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                  colors: [Color(0xFFA5D6A7), Color(0xFF66BB6A)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter),
            ),
          ),
        ),
        body: ListView(
          children: [
            header,
            Transform.translate(
              offset: const Offset(0, -14),
              child: _card(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('ملخص خطتك الحالية',
                        style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 10),
                    _kv(
                        'امتحانات رسمية',
                        _heardOfficial
                            ? 'نعم (${_officialExams.map((c) => _arabicName[c]).join(', ')})'
                            : 'لا'),
                    _kv(
                        'الأجزاء',
                        _heardParts
                            ? 'من $_partsRangeStart إلى $_partsRangeEnd'
                            : 'لا'),
                    _kv(
                      'نقطة البداية',
                      _continuationMode == 'from_start'
                          ? 'من البداية'
                          : _continuationMode == 'from_end'
                              ? 'من النهاية'
                              : 'جزء $_specificPart',
                    ),
                    const SizedBox(height: 14),
                    Theme(data: theme, child: _durationField()),
                    const SizedBox(height: 14),
                    _primaryBtn(_busy ? 'جاري الحفظ...' : 'حفظ التعديل',
                        onPressed: _busy ? null : _submit),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    // منشئ الخطة (Stepper ناعِم)
    final steps = <Step>[
      Step(
        title: Text('الرسمي',
            style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
        content: Theme(
          data: theme,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('هل سمعت عن الامتحانات الرسمية؟',
                  style: GoogleFonts.cairo()),
              const SizedBox(height: 4),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(_heardOfficial ? 'نعم' : 'لا',
                    style: GoogleFonts.cairo(fontWeight: FontWeight.w600)),
                value: _heardOfficial,
                onChanged: (_pausedForOfficial && !_heardOfficial)
                    ? null
                    : (v) => setState(() {
                          _heardOfficial = v;
                          if (!v) _officialExams.clear();
                        }),
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: !_heardOfficial
                    ? const SizedBox.shrink()
                    : Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final code in allowedCodes)
                            FilterChip(
                              label: Text(_arabicName[code]!,
                                  style: GoogleFonts.cairo()),
                              selected: _officialExams.contains(code),
                              onSelected: (sel) => setState(() {
                                if (sel) {
                                  if (!_officialExams.contains(code))
                                    _officialExams.add(code);
                                } else {
                                  _officialExams.remove(code);
                                }
                              }),
                            ),
                        ],
                      ),
              ),
            ],
          ),
        ),
        isActive: _currentStep >= 0,
        state: _currentStep > 0 ? StepState.complete : StepState.indexed,
      ),
      Step(
        title: Text('الأجزاء',
            style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
        content: Theme(
          data: theme,
          child: Column(
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(_heardParts ? 'نعم' : 'لا',
                    style: GoogleFonts.cairo(fontWeight: FontWeight.w600)),
                value: _heardParts,
                onChanged: (v) => setState(() => _heardParts = v),
              ),
              if (_heardParts) ...[
                Row(
                  children: [
                    Expanded(
                        child: _dropdown(
                            'من جزء',
                            _partsRangeStart,
                            (v) => setState(() {
                                  _partsRangeStart = v!;
                                  if (_partsRangeEnd < v) _partsRangeEnd = v;
                                }))),
                    const SizedBox(width: 10),
                    Expanded(
                        child: _dropdown(
                            'إلى جزء',
                            _partsRangeEnd,
                            (v) => setState(() =>
                                _partsRangeEnd = max(v!, _partsRangeStart)))),
                  ],
                ),
              ],
            ],
          ),
        ),
        isActive: _currentStep >= 1,
        state: _currentStep > 1 ? StepState.complete : StepState.indexed,
      ),
      Step(
        title: Text('نقطة البداية',
            style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
        content: Theme(
          data: theme,
          child: Column(
            children: [
              _radio('من البداية', 'from_start'),
              _radio('من النهاية', 'from_end'),
              _radio('تحديد جزء', 'specific'),
              if (_continuationMode == 'specific')
                _dropdown('جزء البداية', _specificPart ?? _partsRangeStart,
                    (v) => setState(() => _specificPart = v)),
            ],
          ),
        ),
        isActive: _currentStep >= 2,
        state: _currentStep > 2 ? StepState.complete : StepState.indexed,
      ),
      Step(
        title: Text('المدة',
            style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
        content: Theme(data: theme, child: _durationField()),
        isActive: _currentStep >= 3,
        state: _currentStep > 3 ? StepState.complete : StepState.indexed,
      ),
      Step(
        title: Text('مراجعة',
            style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_pausedForOfficial)
              _pill('الخطة متوقفة بانتظار امتحان رسمي', Colors.orange.shade700),
            _kv('رسمي', _heardOfficial ? 'نعم' : 'لا'),
            if (_heardOfficial)
              _kv('النوع',
                  _officialExams.map((c) => _arabicName[c]).join(', ')),
            _kv('الأجزاء', _heardParts ? 'نعم' : 'لا'),
            if (_heardParts)
              _kv('النطاق', 'من $_partsRangeStart إلى $_partsRangeEnd'),
            _kv(
                'نقطة البداية',
                _continuationMode == 'from_start'
                    ? 'من البداية'
                    : _continuationMode == 'from_end'
                        ? 'من النهاية'
                        : 'جزء $_specificPart'),
            _kv('المدة', '$_durationWeeks أسابيع'),
            const SizedBox(height: 10),
            _primaryBtn(_busy ? 'جاري الحفظ...' : 'حفظ الخطة',
                onPressed: _busy ? null : _submit),
          ],
        ),
        isActive: _currentStep >= 4,
        state: _currentStep == 4 ? StepState.editing : StepState.indexed,
      ),
    ];

    return Scaffold(
      backgroundColor: _bg,
      body: Column(
        children: [
          header,
          Expanded(
            child: Theme(
              data: theme,
              child: Stepper(
                type: StepperType.vertical,
                elevation: 0,
                currentStep: _currentStep,
                onStepContinue: () {
                  if (_currentStep < steps.length - 1) {
                    setState(() => _currentStep++);
                  } else {
                    _submit();
                  }
                },
                onStepCancel: _currentStep == 0
                    ? null
                    : () => setState(() => _currentStep--),
                controlsBuilder: (ctx, details) {
                  final isLast = _currentStep == steps.length - 1;
                  return Row(
                    children: [
                      Expanded(
                          child: _primaryBtn(isLast ? 'حفظ' : 'التالي',
                              onPressed: details.onStepContinue)),
                      const SizedBox(width: 8),
                      if (_currentStep > 0)
                        Expanded(
                          child: OutlinedButton(
                            onPressed: details.onStepCancel,
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14)),
                              side: BorderSide(color: _primary),
                            ),
                            child: Text('رجوع',
                                style: GoogleFonts.cairo(color: _primary)),
                          ),
                        ),
                    ],
                  );
                },
                steps: steps,
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: _isEditing
          ? FloatingActionButton.extended(
              onPressed: _confirmDelete,
              backgroundColor: Colors.red.shade600,
              icon: const Icon(Icons.delete_outline),
              label: const Text('حذف الخطة'),
            )
          : null,
    );
  }

  /* ───────── عناصر صغيرة ───────── */

  Widget _durationField() => DropdownButtonFormField<int>(
        decoration: const InputDecoration(labelText: 'عدد الأسابيع'),
        value: _durationWeeks,
        items: _weekOptions
            .map((w) => DropdownMenuItem(
                value: w, child: Text('$w أسابيع', style: GoogleFonts.cairo())))
            .toList(),
        onChanged: (v) => setState(() => _durationWeeks = v!),
      );

  Widget _dropdown(String label, int? value, ValueChanged<int?> onChanged) =>
      DropdownButtonFormField<int>(
        decoration: InputDecoration(labelText: label),
        value: value,
        items: List.generate(30, (i) => i + 1)
            .map((p) => DropdownMenuItem(
                value: p, child: Text('جزء $p', style: GoogleFonts.cairo())))
            .toList(),
        onChanged: onChanged,
      );

  Widget _radio(String title, String value) => RadioListTile<String>(
        contentPadding: EdgeInsets.zero,
        title: Text(title, style: GoogleFonts.cairo()),
        value: value,
        groupValue: _continuationMode,
        onChanged: (v) => setState(() => _continuationMode = v!),
      );

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(children: [
          Text('$k: ', style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
          Expanded(child: Text(v, style: GoogleFonts.cairo())),
        ]),
      );

  Widget _card(Widget child) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: const [
              BoxShadow(
                  color: Colors.black12, blurRadius: 18, offset: Offset(0, 10))
            ],
          ),
          padding: const EdgeInsets.all(16),
          child: child,
        ),
      );

  Widget _softTag(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFFF3F6F6),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFE6EAEA)),
        ),
        child: Text(text, style: GoogleFonts.cairo(fontSize: 12)),
      );

  Widget _pill(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(.22)),
        ),
        child: Text(text,
            style: GoogleFonts.cairo(
                fontSize: 12, color: color, fontWeight: FontWeight.w700)),
      );

  Widget _primaryBtn(String text, {VoidCallback? onPressed}) => ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: _primary,
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        child: Text(text, style: GoogleFonts.cairo(color: Colors.white)),
      );
}
