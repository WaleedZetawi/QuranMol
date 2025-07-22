import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/api_config.dart';
import 'add_hafidh_page.dart';

class HafadhListPage extends StatefulWidget {
  const HafadhListPage({super.key});
  @override
  State<HafadhListPage> createState() => _HafadhListState();
}

class _HafadhListState extends State<HafadhListPage> {
  static const _greenStart = Color(0xff27ae60);
  static const _greenEnd = Color(0xff219150);
  static const _bgLight = Color(0xfff0faf2);

  List<Map<String, dynamic>> _rows = [];
  bool _busy = true;

  Future<String> _token() async =>
      (await SharedPreferences.getInstance()).getString('token') ?? '';

  Future<void> _load() async {
    setState(() => _busy = true);
    final token = await _token();
    try {
      final r = await Dio().get(
        '${ApiConfig.baseUrl}/hafadh',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      if (!mounted) return;
      _rows = List<Map<String, dynamic>>.from(r.data);
    } catch (_) {
      // ignore
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _openAdd() async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const AddHafidhPage()),
    );
    if (ok == true) _load();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: _greenStart,
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('إضافة حافظ'),
        onPressed: _openAdd,
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [_greenStart, _greenEnd],
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
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [_greenStart, _greenEnd],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(24),
                    bottomRight: Radius.circular(24),
                  ),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // back button on the right
                    Positioned(
                      right: 8,
                      child: IconButton(
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ),
                    // logo + title centered
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Image.asset('assets/logo1.png', width: 60, height: 60),
                        const SizedBox(height: 4),
                        Text(
                          'حُفّاظ الملتقى',
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

              // LIST
              Expanded(
                child: Container(
                  color: _bgLight,
                  child: _busy
                      ? const Center(child: CircularProgressIndicator())
                      : _rows.isEmpty
                      ? const Center(child: Text('لا يوجد حُفّاظ بعد'))
                      : AnimationLimiter(
                          child: ListView.separated(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemCount: _rows.length,
                            itemBuilder: (_, i) {
                              final h = _rows[i];
                              final date = h['hafidh_date']
                                  .toString()
                                  .split('T')
                                  .first;
                              return AnimationConfiguration.staggeredList(
                                position: i,
                                duration: const Duration(milliseconds: 400),
                                child: SlideAnimation(
                                  verticalOffset: 50,
                                  child: FadeInAnimation(
                                    child: Card(
                                      margin: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 8,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Padding(
                                        padding: const EdgeInsets.all(12),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              h['name'],
                                              style: GoogleFonts.cairo(
                                                textStyle: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 16,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              '${h['reg_number']} • ${h['college']}',
                                              style: const TextStyle(
                                                color: Colors.black54,
                                              ),
                                            ),
                                            const SizedBox(height: 8),
                                            Row(
                                              children: [
                                                const Icon(
                                                  Icons.date_range,
                                                  size: 18,
                                                  color: Colors.green,
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  'تاريخ الختمة: $date',
                                                  style: GoogleFonts.cairo(
                                                    textStyle: const TextStyle(
                                                      fontSize: 14,
                                                    ),
                                                  ),
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
            ],
          ),
        ),
      ),
    );
  }
}
