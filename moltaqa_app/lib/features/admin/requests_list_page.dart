import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/api_config.dart';

class RequestsListPage extends StatefulWidget {
  const RequestsListPage({super.key});

  @override
  State<RequestsListPage> createState() => _RequestsListPageState();
}

class _RequestsListPageState extends State<RequestsListPage> {
  static const _greenStart = Color(0xFF27AE60);
  static const _greenEnd = Color(0xFF219150);
  static const _bgLight = Color(0xFFF0FAF2);

  List<Map<String, dynamic>> _reqs = [];
  bool _busy = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<String> _token() async =>
      (await SharedPreferences.getInstance()).getString('token') ?? '';

  Future<void> _load() async {
    setState(() => _busy = true);
    try {
      final dio = Dio(
        BaseOptions(headers: {'Authorization': 'Bearer ${await _token()}'}),
      );
      final resp = await dio.get('${ApiConfig.baseUrl}/requests');
      _reqs = List<Map<String, dynamic>>.from(resp.data);
    } on DioException catch (e) {
      final msg = e.response?.data['message'] ?? 'فشل تحميل الطلبات';
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(msg)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _action(int id, bool approve) async {
    try {
      final dio = Dio(
        BaseOptions(headers: {'Authorization': 'Bearer ${await _token()}'}),
      );
      await dio.post(
        '${ApiConfig.baseUrl}/requests/$id/${approve ? 'approve' : 'reject'}',
      );
      _load();
    } on DioException catch (e) {
      final msg = e.response?.data['message'] ?? 'فشل العملية';
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(msg)));
      }
    }
  }

  Future<void> _confirmAndReject(int id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد الرفض'),
        content: const Text('هل أنت متأكد من رفض هذا الطلب؟'),
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
      _action(id, false);
    }
  }

  @override
  Widget build(BuildContext ctx) => Scaffold(
    backgroundColor: _bgLight,
    body: Column(
      children: [
        // HEADER
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 24),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [_greenStart, _greenEnd],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
          ),
          child: SafeArea(
            bottom: false,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned(
                  right: 8,
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: Image.asset(
                        'assets/logo1.png',
                        width: 60,
                        height: 60,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'طلبات التسجيل المعلَّقة',
                      style: GoogleFonts.cairo(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        // BODY
        Expanded(
          child: _busy
              ? const Center(child: CircularProgressIndicator())
              : _reqs.isEmpty
              ? const Center(
                  child: Text(
                    'لا طلبات حالياً',
                    style: TextStyle(fontSize: 16),
                  ),
                )
              : AnimationLimiter(
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    itemCount: _reqs.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (_, i) {
                      final r = _reqs[i];
                      return AnimationConfiguration.staggeredList(
                        position: i,
                        duration: const Duration(milliseconds: 500),
                        child: SlideAnimation(
                          verticalOffset: 50,
                          child: FadeInAnimation(
                            child: Card(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              elevation: 3,
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                title: Text(
                                  '${r['name']} • ${r['reg_number']}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                subtitle: Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    r['role'] == 'student'
                                        ? 'طالب • ${r['college']}'
                                        : 'مشرف • ${r['college']}',
                                    style: const TextStyle(
                                      color: Colors.black54,
                                    ),
                                  ),
                                ),
                                trailing: SizedBox(
                                  width: 96,
                                  child: Row(
                                    children: [
                                      IconButton(
                                        icon: const Icon(
                                          Icons.check,
                                          color: Colors.green,
                                        ),
                                        tooltip: 'قبول',
                                        onPressed: () => _action(r['id'], true),
                                      ),
                                      IconButton(
                                        icon: const Icon(
                                          Icons.close,
                                          color: Colors.red,
                                        ),
                                        tooltip: 'رفض',
                                        onPressed: () =>
                                            _confirmAndReject(r['id']),
                                      ),
                                    ],
                                  ),
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
      ],
    ),
  );
}
