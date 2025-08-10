import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/api_config.dart';
import '../../date_utils.dart';
import '../../college_theme.dart'; // استورد الملف الجديد

class CollegeExamRequestsPage extends StatefulWidget {
  final String college;
  final Color? themeStart;
  final Color? themeEnd;
  final Color? bgLight;

  const CollegeExamRequestsPage({
    super.key,
    required this.college,
    this.themeStart,
    this.themeEnd,
    this.bgLight,
  });

  @override
  State<CollegeExamRequestsPage> createState() =>
      _CollegeExamRequestsPageState();
}

class _CollegeExamRequestsPageState extends State<CollegeExamRequestsPage> {
  late final CollegeTheme _th;

  bool _busy = true;
  List<Map<String, dynamic>> _rows = [];
  List<Map<String, dynamic>> _sup = [];

  @override
  void initState() {
    super.initState();
    _th = CollegeTheme(
      widget.themeStart ?? CollegeTheme.byName(widget.college).start,
      widget.themeEnd ?? CollegeTheme.byName(widget.college).end,
      widget.bgLight ?? CollegeTheme.byName(widget.college).bgLight,
    );
    _load();
  }

  Future<String> _token() async =>
      (await SharedPreferences.getInstance()).getString('token') ?? '';

  String _apiPath(String path) {
    final base = ApiConfig.baseUrl.endsWith('/')
        ? ApiConfig.baseUrl.substring(0, ApiConfig.baseUrl.length - 1)
        : ApiConfig.baseUrl;
    final hasApi = base.toLowerCase().endsWith('/api');
    return hasApi ? '$base$path' : '$base/api$path';
  }

  Future<void> _load() async {
    setState(() => _busy = true);
    final t = await _token();
    final opt = Options(headers: {'Authorization': 'Bearer $t'});

    try {
      final reqUrl = _apiPath('/exam-requests');
      final supUrl = _apiPath('/supervisors');

      final r1 = await Dio().get(reqUrl, options: opt);
      final r2 = await Dio().get(supUrl, options: opt);

      if (!mounted) return;

      final list1 = List<Map<String, dynamic>>.from(
        (r1.data as List).map((e) => Map<String, dynamic>.from(e)),
      );
      final list2 = List<Map<String, dynamic>>.from(
        (r2.data as List).map((e) => Map<String, dynamic>.from(e)),
      );

      _rows = list1
          .where((e) => (e['college'] ?? widget.college) == widget.college)
          .toList();

      _sup = list2
          .where(
              (s) => s['college'] == widget.college && s['is_examiner'] == true)
          .toList();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('خطأ في جلب البيانات')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _update(int id, int? examinerId, bool ok) async {
    final t = await _token();
    try {
      final url = _apiPath('/exam-requests/$id');
      await Dio().patch(
        url,
        options: Options(headers: {'Authorization': 'Bearer $t'}),
        data: {
          'approved': ok,
          'supervisor_trial_id': examinerId,
          'supervisor_official_id': null,
          'official_date': null,
        },
      );
      _load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('تعذر الحفظ')));
      }
    }
  }

  Future<void> _delete(int id) async {
    final t = await _token();
    try {
      final url = _apiPath('/exam-requests/$id');
      await Dio().delete(url,
          options: Options(headers: {'Authorization': 'Bearer $t'}));
      _load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('تعذر الحذف')));
      }
    }
  }

  @override
  Widget build(BuildContext ctx) => Scaffold(
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
                // HEADER
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
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Image.asset('assets/logo1.png',
                              width: 60, height: 60),
                          const SizedBox(height: 4),
                          Text(
                            'طلبات أجزاء ${widget.college}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
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
                    color: _th.bgLight,
                    child: _busy
                        ? const Center(child: CircularProgressIndicator())
                        : _rows.isEmpty
                            ? const Center(child: Text('لا توجد طلبات حالية'))
                            : ListView.separated(
                                padding: const EdgeInsets.all(12),
                                itemCount: _rows.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 8),
                                itemBuilder: (_, i) {
                                  final e = _rows[i];
                                  final part = e['part'];
                                  final dateStr = fmtYMD(e['date']);

                                  return Card(
                                    elevation: 2,
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(14)),
                                    child: Padding(
                                      padding: const EdgeInsets.all(14),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            e['student_name'] ?? '—',
                                            style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 16),
                                          ),
                                          const SizedBox(height: 6),
                                          Text('الجزء المطلوب: ${part ?? '—'}'),
                                          Text('التاريخ المقترح: $dateStr'),
                                          if (e['orig_supervisor'] != null)
                                            Text(
                                                'المشرف المختص: ${e['orig_supervisor']}'),
                                          if (e['examiner_name'] != null)
                                            Text(
                                                'الممتحِن: ${e['examiner_name']}'),
                                          const SizedBox(height: 10),
                                          Row(
                                            children: [
                                              Expanded(
                                                child: DropdownButton<int>(
                                                  isExpanded: true,
                                                  hint: const Text(
                                                      'اختر الممتحن'),
                                                  value:
                                                      e['supervisor_trial_id']
                                                          as int?,
                                                  items: _sup
                                                      .map((s) =>
                                                          DropdownMenuItem<int>(
                                                            value:
                                                                s['id'] as int,
                                                            child: Text(
                                                                s['name']
                                                                    as String),
                                                          ))
                                                      .toList(),
                                                  onChanged: (v) => setState(() =>
                                                      e['supervisor_trial_id'] =
                                                          v),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              _smallBtn('قبول', _th.start, () {
                                                if (e['supervisor_trial_id'] ==
                                                    null) {
                                                  ScaffoldMessenger.of(ctx)
                                                      .showSnackBar(
                                                    const SnackBar(
                                                        content: Text(
                                                            'اختر الممتحن أولاً قبل القبول')),
                                                  );
                                                  return;
                                                }
                                                _update(
                                                    e['id'] as int,
                                                    e['supervisor_trial_id']
                                                        as int?,
                                                    true);
                                              }),
                                              const SizedBox(width: 6),
                                              _smallBtn(
                                                  'رفض',
                                                  Colors.red,
                                                  () => _update(e['id'] as int,
                                                      null, false)),
                                              const SizedBox(width: 4),
                                              IconButton(
                                                tooltip: 'حذف',
                                                icon: const Icon(Icons.delete,
                                                    color: Colors.red),
                                                onPressed: () =>
                                                    _delete(e['id'] as int),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

  Widget _smallBtn(String t, Color c, VoidCallback f) => ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: c,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        onPressed: f,
        child: Text(t, style: const TextStyle(fontWeight: FontWeight.w600)),
      );
}
