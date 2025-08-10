import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/dio_client.dart';

class SupervisorChangeRequestsAdminPage extends StatefulWidget {
  const SupervisorChangeRequestsAdminPage({super.key});

  @override
  State<SupervisorChangeRequestsAdminPage> createState() =>
      _SupervisorChangeRequestsAdminPageState();
}

class _SupervisorChangeRequestsAdminPageState
    extends State<SupervisorChangeRequestsAdminPage> {
  bool _busy = true;
  List<Map<String, dynamic>> _rows = [];

  // لمسؤولة البنات: فلترة بالكلية
  static const femaleColleges = ['NewCampus', 'OldCampus', 'Agriculture'];
  String? _selectedCollege;

  @override
  void initState() {
    super.initState();
    _selectedCollege = null;
    _load();
  }

  Future<void> _load() async {
    setState(() => _busy = true);
    try {
      final dio = DioClient().dio;

      // ❶ جلب الطلبات فقط (السيرفر يعيد اسم الطالبة + المشرفة الحالية/المقترحة)
      final r1 = await dio.get(
        '/supervisor-change-requests',
        queryParameters:
            _selectedCollege == null ? null : {'college': _selectedCollege},
      );

      setState(() {
        _rows = List<Map<String, dynamic>>.from(r1.data ?? const []);
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تعذر تحميل الطلبات', style: GoogleFonts.cairo()),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// اعتماد/رفض بدون إرسال supervisor_id
  /// الباك إند سيستخدم desired_supervisor_id تلقائياً عند الموافقة.
  Future<void> _resolve(int reqId, {required bool approve}) async {
    try {
      final dio = DioClient().dio;
      await dio.post('/supervisor-change-requests/$reqId/resolve', data: {
        'approve': approve,
      });
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم التنفيذ', style: GoogleFonts.cairo())),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('فشل التنفيذ', style: GoogleFonts.cairo())),
      );
    }
  }

  Future<void> _deleteReq(int reqId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: const Text('هل تريد حذف هذا الطلب؟'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('حذف')),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await DioClient().dio.delete('/supervisor-change-requests/$reqId');
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم الحذف', style: GoogleFonts.cairo())),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('فشل الحذف', style: GoogleFonts.cairo())),
      );
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
              child: Text('طلبات تغيير المشرفة (طالبات)',
                  style: GoogleFonts.cairo(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 20)),
            ),
          ),
        ],
      ),
    );

    final collegePicker = Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: DropdownButtonFormField<String?>(
        value: _selectedCollege,
        decoration: InputDecoration(
          labelText: 'فلترة بالكلية (اختياري لمسؤولة البنات)',
          labelStyle: GoogleFonts.cairo(),
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
        items: <DropdownMenuItem<String?>>[
          const DropdownMenuItem<String?>(
            value: null,
            child: Text('الكل'),
          ),
          ...femaleColleges
              .map((c) => DropdownMenuItem<String?>(value: c, child: Text(c)))
              .toList(),
        ],
        onChanged: (v) {
          setState(() => _selectedCollege = v);
          _load();
        },
      ),
    );

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            header,
            const SizedBox(height: 8),
            collegePicker,
            Expanded(
              child: _busy
                  ? const Center(child: CircularProgressIndicator())
                  : _rows.isEmpty
                      ? Center(
                          child: Text('لا توجد طلبات حالياً',
                              style:
                                  GoogleFonts.cairo(color: Colors.grey[600])),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(16),
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemCount: _rows.length,
                          itemBuilder: (_, i) {
                            final r = _rows[i];
                            final id = r['id'] as int;
                            final college = r['college'] as String? ?? '';

                            return Card(
                              elevation: 3,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
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
                                          child: Text(
                                            r['student_name'] ?? '—',
                                            style: GoogleFonts.cairo(
                                                fontWeight: FontWeight.w700),
                                          ),
                                        ),
                                        Text(college,
                                            style: GoogleFonts.cairo(
                                                color: Colors.grey[700])),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      'المشرفة الحالية: ${r['current_name'] ?? '—'}',
                                      style: GoogleFonts.cairo(),
                                    ),
                                    Text(
                                      'المشرفة المقترحة: ${r['desired_name'] ?? '—'}',
                                      style: GoogleFonts.cairo(),
                                    ),
                                    if ((r['reason'] as String?)?.isNotEmpty ??
                                        false)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 6),
                                        child: Text(
                                          'السبب: ${r['reason']}',
                                          style: GoogleFonts.cairo(
                                              color: Colors.grey[700]),
                                        ),
                                      ),

                                    // ملاحظة بديلة عن Dropdown (تمت إزالته)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 8),
                                      child: Text(
                                        'سيتم اعتماد المشرفة المقترحة تلقائيًا عند الضغط على اعتماد.',
                                        style: GoogleFonts.cairo(
                                            color: Colors.grey[700]),
                                      ),
                                    ),
                                    const SizedBox(height: 10),

                                    Row(
                                      children: [
                                        Expanded(
                                          child: ElevatedButton.icon(
                                            onPressed: () =>
                                                _resolve(id, approve: true),
                                            icon: const Icon(Icons.check),
                                            label: Text('اعتماد',
                                                style: GoogleFonts.cairo(
                                                    fontWeight:
                                                        FontWeight.bold)),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: Colors.teal,
                                              foregroundColor: Colors.white,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: OutlinedButton.icon(
                                            onPressed: () =>
                                                _resolve(id, approve: false),
                                            icon: const Icon(Icons.close,
                                                color: Colors.red),
                                            label: Text('رفض',
                                                style: GoogleFonts.cairo(
                                                    color: Colors.red,
                                                    fontWeight:
                                                        FontWeight.bold)),
                                          ),
                                        ),
                                        IconButton(
                                          tooltip: 'حذف الطلب',
                                          onPressed: () => _deleteReq(id),
                                          icon: const Icon(Icons.delete_forever,
                                              color: Colors.red),
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
}
