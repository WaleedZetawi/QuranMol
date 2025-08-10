// lib/screens/score_sheet_page.dart

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../date_utils.dart';
import '../../services/api_config.dart';

class ScoreSheetPage extends StatefulWidget {
  final int studentId;
  final String studentName;
  final String? studentCollege;
  final String studentType; // 'regular' / 'intensive'

  const ScoreSheetPage({
    Key? key,
    required this.studentId,
    required this.studentName,
    this.studentCollege,
    required this.studentType,
  }) : super(key: key);

  @override
  _ScoreSheetPageState createState() => _ScoreSheetPageState();
}

class _ScoreSheetPageState extends State<ScoreSheetPage> {
  bool _busy = true;

  List<Map<String, dynamic>> _official = [];
  List<Map<String, dynamic>> _parts = [];
  List<Map<String, dynamic>> _trials = [];

  double? _avgOfficial;
  double? _avgParts;
  double? _avgTrials;
  double? _avgAll;

  int _passedOfficialCount = 0;
  int _passedPartsCount = 0;
  double _progressPercent = 0;

  static const Color _bgStart = Color(0xFFE8F5E9);
  static const Color _bgEnd = Color(0xFF66BB6A);
  static const Color _cardColor = Colors.white;
  static const Color _primary = Color(0xFF2E7D32);

  final ScrollController _scrollController = ScrollController();

  double _headerOpacity = 1.0;
  static const double _fadeThreshold = 150.0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(() {
      final offset = _scrollController.offset;
      final o = (_fadeThreshold - offset) / _fadeThreshold;
      setState(() => _headerOpacity = o.clamp(0.0, 1.0));
    });
    _loadExams();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  // ➊ هل توجد درجة مسجَّلة؟
  bool _hasRecordedScore(dynamic raw) => raw != null; // قبل كان >0

  Future<String> _token() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('token') ?? '';
  }

  String _examsUrl() {
    final base = ApiConfig.baseUrl;
    final clean =
        base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    final hasApi = clean.toLowerCase().endsWith('/api');
    return hasApi
        ? '$clean/exams/${widget.studentId}'
        : '$clean/api/exams/${widget.studentId}';
  }

  Future<void> _loadExams() async {
    setState(() => _busy = true);
    try {
      final t = await _token();
      final r = await Dio().get(
        _examsUrl(),
        options: Options(headers: {'Authorization': 'Bearer $t'}),
      );
      final data = r.data as List;
      final all = data.map((e) => Map<String, dynamic>.from(e)).toList();

      bool isPart(Map e) {
        final code = (e['exam_code'] ?? '').toString();
        return code.startsWith('J');
      }

      bool isOfficialRow(Map e) =>
          (e['official'] == true || e['official'] == 1) && !isPart(e);
      bool isTrialRow(Map e) =>
          !(e['official'] == true || e['official'] == 1) && !isPart(e);

      final off = all.where(isOfficialRow).toList();
      final partsRaw = all.where(isPart).toList();
      final trials = all.where(isTrialRow).toList();

      int cmp(Map a, Map b) {
        DateTime parseSafe(dynamic raw) {
          if (raw == null) return DateTime.fromMillisecondsSinceEpoch(0);
          try {
            return DateTime.parse(raw.toString());
          } catch (_) {
            return DateTime.fromMillisecondsSinceEpoch(0);
          }
        }

        return parseSafe(b['created_at']).compareTo(parseSafe(a['created_at']));
      }

      off.sort(cmp);
      partsRaw.sort(cmp);
      trials.sort(cmp);

      /* اختيار أحدث محاولة لكل جزء */
      final distinct = <String, Map<String, dynamic>>{};
      for (var row in partsRaw) {
        final code = row['exam_code'] as String;
        if (!code.startsWith('J')) continue;
        final old = distinct[code];
        if (old == null ||
            DateTime.parse(row['created_at'].toString())
                .isAfter(DateTime.parse(old['created_at'].toString()))) {
          distinct[code] = row;
        }
      }
      final parts = distinct.values.toList();

      /* ➋ حساب المعدلات بعد تعديل شرط التسجيل */
      double? computeAvg(List<Map<String, dynamic>> list) {
        final scores = list
            .where((e) => _hasRecordedScore(e['score']))
            .map((e) => (e['score'] as num).toDouble())
            .toList();
        if (scores.isEmpty) return null;
        return scores.reduce((a, b) => a + b) / scores.length;
      }

      final avgOff = computeAvg(off);
      final avgParts = computeAvg(parts);
      final avgTri = computeAvg(trials);
      final avgAll = computeAvg([...off, ...parts, ...trials]);

      /* ➌ العدّ يشمل كلّ امتحان مُعلَّم Passed */
      final passedOff =
          off.where((e) => e['passed'] == true || e['passed'] == 1).length;
      final passedParts =
          parts.where((e) => e['passed'] == true || e['passed'] == 1).length;

      /* ➍ نسبة التقدّم حسب نوع الطالب */
      final passedCodes = off
          .where((e) => e['passed'] == true || e['passed'] == 1)
          .map((e) => e['exam_code'])
          .toSet();
      final needed = widget.studentType == 'intensive'
          ? ['T1', 'T2', 'T3', 'H1', 'H2', 'Q']
          : ['F1', 'F2', 'F3', 'F4', 'F5', 'F6'];
      final prog = needed.isEmpty
          ? 0.0
          : needed.where(passedCodes.contains).length / needed.length;

      setState(() {
        _official = off;
        _parts = parts;
        _trials = trials;
        _avgOfficial = avgOff;
        _avgParts = avgParts;
        _avgTrials = avgTri;
        _avgAll = avgAll;
        _passedOfficialCount = passedOff;
        _passedPartsCount = passedParts;
        _progressPercent = prog;
        _busy = false;
      });
    } catch (e) {
      debugPrint('Failed to load exams: $e');
      if (mounted) setState(() => _busy = false);
    }
  }

  String _arabicExamName(String? code) {
    switch (code) {
      case 'Q':
        return 'القرآن كامل';
      case 'H1':
        return 'خمسة عشر الأولى';
      case 'H2':
        return 'خمسة عشر الثانية';
      default:
        if (code != null && code.startsWith('F')) {
          return 'خمسة أجزاء ${code[1]}';
        }
        if (code != null && code.startsWith('T')) {
          return 'عشرة أجزاء ${code[1]}';
        }
        if (code != null && code.startsWith('J')) {
          final n = int.tryParse(code.substring(1)) ?? 0;
          return 'جزء $n';
        }
        return code ?? '-';
    }
  }

  // ➋ عرض الدرجة
  String _fmtScore(dynamic s) {
    return s == null
        ? 'ناجح' // null ↦ ناجح
        : (num.parse(s.toString()) % 1 == 0)
            ? num.parse(s.toString()).toInt().toString()
            : num.parse(s.toString()).toStringAsFixed(2);
  }

  String _fmtDate(String raw) => fmtYMD(raw);

  String _fmtAvg(double? v) {
    if (v == null) return '-';
    return v % 1 == 0 ? v.toInt().toString() : v.toStringAsFixed(2);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [_bgStart, _bgEnd],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: _busy
                    ? const Center(
                        child: CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(_primary),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadExams,
                        child: ListView(
                          controller: _scrollController,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          children: [
                            Opacity(
                              opacity: _headerOpacity,
                              child: Column(
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.only(
                                      top: 8,
                                      left: 16,
                                      right: 8,
                                    ),
                                    child: Align(
                                      alignment: Alignment.topRight,
                                      child: IconButton(
                                        icon: const Icon(
                                          Icons.arrow_back,
                                          color: _primary,
                                          size: 28,
                                        ),
                                        onPressed: () => Navigator.pop(context),
                                      ),
                                    ),
                                  ),
                                  Image.asset(
                                    'assets/logo1.png',
                                    width: 120,
                                    height: 120,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'كشف العلامات',
                                    style: GoogleFonts.cairo(
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold,
                                      color: _primary,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                ],
                              ),
                            ),
                            _buildStudentCard(),
                            _buildSummaryCard(),
                            _buildSection(
                              title: 'الامتحانات الرسمية',
                              items: _official,
                              icon: Icons.workspace_premium,
                            ),
                            _buildSection(
                              title: 'امتحانات الأجزاء',
                              items: _parts,
                              icon: Icons.menu_book,
                            ),
                            _buildSection(
                              title: 'الامتحانات التجريبية',
                              items: _trials,
                              icon: Icons.flaky,
                              initiallyExpanded: false,
                            ),
                          ],
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStudentCard() {
    final typeDesc =
        widget.studentType == 'intensive' ? 'تثبيت (حافظ مسبقاً)' : 'عادي';
    return Card(
      color: _cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      elevation: 4,
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.studentName,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 12,
              runSpacing: 6,
              children: [
                _infoChip(Icons.school, 'الكلية', widget.studentCollege ?? '-'),
                _infoChip(Icons.flag, 'الخطة', typeDesc),
                _infoChip(Icons.workspace_premium, 'رسمي ناجح',
                    '$_passedOfficialCount'),
                _infoChip(Icons.menu_book, 'أجزاء ناجحة', '$_passedPartsCount'),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'التقدّم: ${(_progressPercent * 100).toStringAsFixed(0)}%',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            LinearProgressIndicator(
              value: _progressPercent.clamp(0, 1),
              minHeight: 8,
              backgroundColor: Colors.grey.shade300,
              color: _primary,
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoChip(IconData ic, String label, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(ic, size: 18, color: Colors.blueGrey),
        const SizedBox(width: 4),
        Text('$label: ', style: const TextStyle(fontWeight: FontWeight.w600)),
        Text(value),
      ],
    );
  }

  Widget _buildSummaryCard() {
    Color avgColor(double? v) {
      if (v == null) return Colors.grey;
      return v >= 60 ? Colors.green : Colors.red;
    }

    return Card(
      color: _cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      elevation: 2,
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'المعدّلات',
              style: GoogleFonts.cairo(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                _avgChip('رسمي', _avgOfficial, avgColor(_avgOfficial)),
                _avgChip('أجزاء', _avgParts, avgColor(_avgParts)),
                _avgChip('تجريبي', _avgTrials, avgColor(_avgTrials)),
                _avgChip('إجمالي', _avgAll, avgColor(_avgAll)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _avgChip(String label, double? val, Color c) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: c.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.withOpacity(0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: ',
            style: TextStyle(fontWeight: FontWeight.w600, color: c),
          ),
          Text(
            _fmtAvg(val),
            style: TextStyle(fontWeight: FontWeight.bold, color: c),
          ),
        ],
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required List<Map<String, dynamic>> items,
    required IconData icon,
    bool initiallyExpanded = true,
  }) {
    return Card(
      color: _cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 1,
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ExpansionTile(
        initiallyExpanded: initiallyExpanded,
        title: Row(
          children: [
            Icon(icon, color: _primary),
            const SizedBox(width: 8),
            Text(
              title,
              style: TextStyle(fontWeight: FontWeight.bold, color: _primary),
            ),
            const Spacer(),
            Text(
              '${items.length}',
              style: TextStyle(color: _primary.withOpacity(0.7)),
            ),
          ],
        ),
        children: items.isEmpty
            ? [
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('لا يوجد بيانات'),
                ),
              ]
            : items.map((e) {
                final passed = e['passed'] == true || e['passed'] == 1;
                return ListTile(
                  leading: Icon(
                    passed ? Icons.check_circle : Icons.cancel,
                    color: passed ? Colors.green : Colors.redAccent,
                  ),
                  title: Text(_arabicExamName(e['exam_code']?.toString())),
                  subtitle: Text(
                    'الدرجة: ${_fmtScore(e['score'])}  •  التاريخ: ${_fmtDate(e['created_at'])}',
                  ),
                );
              }).toList(),
      ),
    );
  }
}
