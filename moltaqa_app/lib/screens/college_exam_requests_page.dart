import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/api_config.dart';

class CollegeExamRequestsPage extends StatefulWidget {
  final String college;
  const CollegeExamRequestsPage({super.key, required this.college});

  @override
  State<CollegeExamRequestsPage> createState() =>
      _CollegeExamRequestsPageState();
}

class _CollegeExamRequestsPageState extends State<CollegeExamRequestsPage> {
  bool _busy = true;
  List<Map<String, dynamic>> _rows = [];
  List<Map<String, dynamic>> _sup = [];

  /* ---------------- Helpers ---------------- */

  Future<String> _token() async =>
      (await SharedPreferences.getInstance()).getString('token') ?? '';

  /// يبني URL يُضيف /api فقط إذا لم تكن موجودة أصلاً
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

      debugPrint('➡️ GET $reqUrl');
      debugPrint('➡️ GET $supUrl');

      final r1 = await Dio().get(reqUrl, options: opt);
      final r2 = await Dio().get(supUrl, options: opt);

      if (!mounted) return;

      final list1 = List<Map<String, dynamic>>.from(
        (r1.data as List).map((e) => Map<String, dynamic>.from(e)),
      );
      final list2 = List<Map<String, dynamic>>.from(
        (r2.data as List).map((e) => Map<String, dynamic>.from(e)),
      );

      // الطلبات (الخادم أصلاً يقيّدها حسب الدور والكلية)
      // نحافظ على الفلترة الاحتياطية:
      _rows = list1
          .where((e) => (e['college'] ?? widget.college) == widget.college)
          .toList();

      // الممتحنون فقط (is_examiner = true) ومن نفس الكلية
      _sup = list2
          .where(
            (s) => s['college'] == widget.college && s['is_examiner'] == true,
          )
          .toList();

      debugPrint('✅ exam-requests fetched = ${_rows.length}');
      for (final e in _rows) {
        debugPrint(
          ' • id=${e['id']} kind=${e['kind']} part=${e['part']} date=${e['date']} exam_code=${e['exam_code']}',
        );
      }
    } catch (e, st) {
      debugPrint('❌ load error: $e');
      debugPrint(st.toString());
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('خطأ في جلب البيانات')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _update(int id, int? examinerId, bool ok) async {
    final t = await _token();
    try {
      final url = _apiPath('/exam-requests/$id');
      debugPrint('PATCH $url approved=$ok trial=$examinerId');
      await Dio().patch(
        url,
        options: Options(headers: {'Authorization': 'Bearer $t'}),
        data: {
          'approved': ok,
          'supervisor_trial_id': examinerId,
          'supervisor_official_id': null, // طلب جزء لا يحتاج رسمي
          'official_date': null,
        },
      );
      _load();
    } catch (e) {
      debugPrint('❌ update error: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('تعذر الحفظ')));
      }
    }
  }

  Future<void> _delete(int id) async {
    final t = await _token();
    try {
      final url = _apiPath('/exam-requests/$id');
      debugPrint('DELETE $url');
      await Dio().delete(
        url,
        options: Options(headers: {'Authorization': 'Bearer $t'}),
      );
      _load();
    } catch (e) {
      debugPrint('❌ delete error: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('تعذر الحذف')));
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  /* ---------------- UI ---------------- */

  @override
  Widget build(BuildContext ctx) => Scaffold(
    appBar: AppBar(title: Text('طلبات أجزاء ${widget.college}')),
    body: _busy
        ? const Center(child: CircularProgressIndicator())
        : _rows.isEmpty
        ? const Center(child: Text('لا توجد طلبات حالية'))
        : ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: _rows.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              final e = _rows[i];
              final part = e['part'];
              final rawDate = e['date'];
              String dateStr = '-';
              if (rawDate != null) {
                try {
                  dateStr = DateFormat(
                    'yyyy-MM-dd',
                  ).format(DateTime.parse(rawDate.toString()));
                } catch (_) {}
              }

              return Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        e['student_name'] ?? '—',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text('الجزء المطلوب: ${part ?? '—'}'),
                      Text('التاريخ المقترح: $dateStr'),
                      if (e['orig_supervisor'] != null)
                        Text('المشرف المختص: ${e['orig_supervisor']}'),
                      if (e['examiner_name'] != null)
                        Text('الممتحِن: ${e['examiner_name']}'),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButton<int>(
                              isExpanded: true,
                              hint: const Text('اختر الممتحن'),
                              value: e['supervisor_trial_id'] as int?,
                              items: _sup
                                  .map(
                                    (s) => DropdownMenuItem<int>(
                                      value: s['id'] as int,
                                      child: Text(s['name'] as String),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (v) =>
                                  setState(() => e['supervisor_trial_id'] = v),
                            ),
                          ),
                          const SizedBox(width: 8),
                          _smallBtn('قبول', Colors.green, () {
                            if (e['supervisor_trial_id'] == null) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'اختر الممتحن أولاً قبل القبول',
                                  ),
                                ),
                              );
                              return;
                            }
                            _update(
                              e['id'] as int,
                              e['supervisor_trial_id'] as int?,
                              true,
                            );
                          }),
                          const SizedBox(width: 6),
                          _smallBtn(
                            'رفض',
                            Colors.red,
                            () => _update(e['id'] as int, null, false),
                          ),
                          const SizedBox(width: 4),
                          IconButton(
                            tooltip: 'حذف',
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () => _delete(e['id'] as int),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
  );

  Widget _smallBtn(String t, Color c, VoidCallback f) => ElevatedButton(
    style: ElevatedButton.styleFrom(
      backgroundColor: c,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    ),
    onPressed: f,
    child: Text(t, style: const TextStyle(fontWeight: FontWeight.w600)),
  );
}
