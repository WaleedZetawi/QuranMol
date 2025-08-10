// lib/features/admin/requests_list_page.dart

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/dio_client.dart';

class RequestsListPage extends StatefulWidget {
  const RequestsListPage({super.key});
  @override
  State<RequestsListPage> createState() => _RequestsListPageState();
}

class _RequestsListPageState extends State<RequestsListPage> {
  bool _busy = true;
  List<Map<String, dynamic>> _rows = [];
  List<Map<String, dynamic>> _allSups = [];
  final Map<int, int?> _pickedForRow = {}; // requestId -> supervisorId

  static const femaleColleges = {'NewCampus', 'OldCampus', 'Agriculture'};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _busy = true);
    try {
      final dio = DioClient().dio;
      // ❶ الطلبات — الخادم يفلتر تلقائيًا حسب دور المسؤول/المسؤولة
      final r1 = await dio.get('/requests');
      final rows = List<Map<String, dynamic>>.from(r1.data);

      // ❷ المشرفون — الخادم يفلتر حسب الدور والجنس/الكلية
      final r2 = await dio.get('/supervisors');
      final sups = List<Map<String, dynamic>>.from(r2.data)
        ..sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));

      setState(() {
        _rows = rows;
        _allSups = sups;
        for (final e in _rows) {
          _pickedForRow[e['id'] as int] = null;
        }
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('تعذّر تحميل الطلبات', style: GoogleFonts.cairo())),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _approve(int reqId, Map<String, dynamic> req) async {
    final dio = DioClient().dio;
    final isStudent = (req['role'] ?? 'student') == 'student';
    final college = req['college'] as String;

    try {
      if (isStudent) {
        final supId = _pickedForRow[reqId];
        if (supId == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(
                    'اختر ${femaleColleges.contains(college) ? 'المشرفة' : 'المشرف'} أولًا',
                    style: GoogleFonts.cairo())),
          );
          return;
        }
        // تأكيد محلي: نفس الكلية
        final sup =
            _allSups.firstWhere((s) => s['id'] == supId, orElse: () => {});
        if (sup is! Map || sup.isEmpty || sup['college'] != college) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(
                    'ال${femaleColleges.contains(college) ? 'مشرفة' : 'مشرف'} ليس/ت من نفس الكلية',
                    style: GoogleFonts.cairo())),
          );
          return;
        }
        await dio
            .post('/requests/$reqId/approve', data: {'supervisor_id': supId});
      } else {
        // طلب مشرف/مشرفة: لا يحتاج اختيار
        await dio.post('/requests/$reqId/approve');
      }
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تم الاعتماد', style: GoogleFonts.cairo())));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل الاعتماد', style: GoogleFonts.cairo())));
    }
  }

  Future<void> _reject(int reqId) async {
    try {
      await DioClient().dio.post('/requests/$reqId/reject');
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تم الرفض', style: GoogleFonts.cairo())));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل الرفض', style: GoogleFonts.cairo())));
    }
  }

  @override
  Widget build(BuildContext context) {
    final header = Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
      decoration: const BoxDecoration(
        gradient:
            LinearGradient(colors: [Color(0xff27ae60), Color(0xff219150)]),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          Expanded(
            child: Center(
              child: Text('طلبات التسجيل',
                  style: GoogleFonts.cairo(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 20)),
            ),
          ),
        ],
      ),
    );

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            header,
            Expanded(
              child: _busy
                  ? const Center(child: CircularProgressIndicator())
                  : _rows.isEmpty
                      ? Center(
                          child: Text('لا توجد طلبات حالياً',
                              style:
                                  GoogleFonts.cairo(color: Colors.grey[700])))
                      : ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: _rows.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (_, i) {
                            final r = _rows[i];
                            final id = r['id'] as int;
                            final isStudent =
                                (r['role'] ?? 'student') == 'student';
                            final college = r['college'] as String;
                            final createdAt = r['created_at_str'] ?? '';
                            final isFemaleCollege =
                                femaleColleges.contains(college);

                            final supsForCollege = _allSups
                                .where((s) => s['college'] == college)
                                .toList();

                            return Card(
                              elevation: 3,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Row(
                                      children: [
                                        const Icon(Icons.person,
                                            color: Colors.teal),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(r['name'] ?? '—',
                                              style: GoogleFonts.cairo(
                                                  fontWeight: FontWeight.w700)),
                                        ),
                                        Text(college,
                                            style: GoogleFonts.cairo(
                                                color: Colors.grey[700])),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Wrap(
                                      spacing: 12,
                                      runSpacing: 6,
                                      children: [
                                        _chip('الدور', r['role'] ?? 'student'),
                                        _chip('الرقم', r['reg_number'] ?? '—'),
                                        _chip('البريد', r['email'] ?? '—'),
                                        _chip('أُنشئ', createdAt),
                                        _chip('النوع',
                                            isFemaleCollege ? 'طالبة' : 'طالب'),
                                      ],
                                    ),
                                    if (isStudent) ...[
                                      const SizedBox(height: 10),
                                      DropdownButtonFormField<int>(
                                        value: _pickedForRow[id],
                                        isExpanded: true,
                                        decoration: InputDecoration(
                                          labelText: isFemaleCollege
                                              ? 'اختر المشرفة'
                                              : 'اختر المشرف',
                                          border: const OutlineInputBorder(),
                                        ),
                                        items: supsForCollege
                                            .map((s) => DropdownMenuItem(
                                                  value: s['id'] as int,
                                                  child: Text(s['name']),
                                                ))
                                            .toList(),
                                        onChanged: (v) => setState(
                                            () => _pickedForRow[id] = v),
                                      ),
                                    ],
                                    const SizedBox(height: 10),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: ElevatedButton.icon(
                                            onPressed: () => _approve(id, r),
                                            icon: const Icon(Icons.check),
                                            label: Text('اعتماد',
                                                style: GoogleFonts.cairo(
                                                    fontWeight:
                                                        FontWeight.bold)),
                                            style: ElevatedButton.styleFrom(
                                                backgroundColor: Colors.teal,
                                                foregroundColor: Colors.white),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: OutlinedButton.icon(
                                            onPressed: () => _reject(id),
                                            icon: const Icon(Icons.close,
                                                color: Colors.red),
                                            label: Text('رفض',
                                                style: GoogleFonts.cairo(
                                                    color: Colors.red,
                                                    fontWeight:
                                                        FontWeight.bold)),
                                          ),
                                        ),
                                      ],
                                    )
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, String value) {
    return Chip(
      backgroundColor: const Color(0xfff2f8f4),
      label: Text('$label: $value', style: GoogleFonts.cairo(fontSize: 12)),
    );
  }
}
