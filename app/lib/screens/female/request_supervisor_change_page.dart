import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/dio_client.dart';

class RequestSupervisorChangePage extends StatefulWidget {
  /// مرّر true لطالبة، false لطالب
  final bool isFemale;
  const RequestSupervisorChangePage({Key? key, required this.isFemale})
      : super(key: key);

  @override
  State<RequestSupervisorChangePage> createState() =>
      _RequestSupervisorChangePageState();
}

class _RequestSupervisorChangePageState
    extends State<RequestSupervisorChangePage> {
  int? _desiredId;
  final _reason = TextEditingController();
  List<Map<String, dynamic>> _supervisors = [];
  bool _busy = true;

  @override
  void initState() {
    super.initState();
    _loadSupers();
  }

  Future<void> _loadSupers() async {
    try {
      final dio = DioClient().dio;
      // لا نرسل gender — السيرفر يفلتر حسب التوكن (جنس المستخدم + كليته)
      final r = await dio.get('/supervisors');
      final list = List<Map<String, dynamic>>.from(r.data ?? const [])
        ..sort((a, b) {
          final an = (a['name'] ?? '') as String;
          final bn = (b['name'] ?? '') as String;
          return an.compareTo(bn);
        });

      if (!mounted) return;
      setState(() => _supervisors = list);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذّر تحميل قائمة المشرفين/المشرفات')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit() async {
    if (_desiredId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.isFemale ? 'اختاري المشرفة أولًا' : 'اختر المشرف أولًا',
            style: GoogleFonts.cairo(),
          ),
        ),
      );
      return;
    }
    try {
      await DioClient().dio.post(
        '/supervisor-change-requests',
        data: {
          'desired_supervisor_id': _desiredId,
          'reason': _reason.text.trim().isEmpty ? null : _reason.text.trim(),
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم إرسال الطلب')),
      );
      Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذّر الإرسال')),
        );
      }
    }
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title =
        widget.isFemale ? 'اختيار/تغيير المشرفة' : 'اختيار/تغيير المشرف';
    final ddLabel = widget.isFemale ? 'اختاري المشرفة' : 'اختر المشرف';

    final emptyState = Center(
      child: Text(
        'لا توجد أسماء متاحة حاليًا من جهتك/كليتك',
        style: GoogleFonts.cairo(color: Colors.grey[700]),
        textAlign: TextAlign.center,
      ),
    );

    return Scaffold(
      appBar: AppBar(title: Text(title), centerTitle: true),
      body: _busy
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  DropdownButtonFormField<int>(
                    value: _desiredId,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: ddLabel,
                      border: const OutlineInputBorder(),
                    ),
                    items: _supervisors
                        .map(
                          (s) => DropdownMenuItem<int>(
                            value: (s['id'] as num).toInt(),
                            child: Text('${s['name']}'),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setState(() => _desiredId = v),
                  ),
                  if (!_busy && _supervisors.isEmpty) ...[
                    const SizedBox(height: 8),
                    emptyState,
                  ],
                  const SizedBox(height: 12),
                  TextField(
                    controller: _reason,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'سبب الطلب (اختياري)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _submit,
                      child: Text('إرسال', style: GoogleFonts.cairo()),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
