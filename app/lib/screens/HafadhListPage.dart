// lib/pages/HafadhListPage.dart
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/api_config.dart';
import '../../services/auth_service.dart';
import 'add_hafidh_page.dart';

/// helper: احسب gender من الدور أو الكلية
Future<Map<String, String>?> _genderQP() async {
  final role = await AuthService.role;
  final col = await AuthService.college;

  if (role == 'admin_dash_f') return const {'gender': 'female'};
  if (role == 'admin_dashboard') return const {'gender': 'male'};

  const femaleCols = {'NewCampus', 'OldCampus', 'Agriculture'};
  const maleCols = {'Engineering', 'Medical', 'Sharia'};
  if (col == null) return null;
  if (femaleCols.contains(col)) return const {'gender': 'female'};
  if (maleCols.contains(col)) return const {'gender': 'male'};
  return null;
}

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
  String? _gender; // 'male' | 'female' | null

  bool get _isFemale => (_gender ?? '').toLowerCase() == 'female';
  String get _title => _isFemale ? 'حافظات الملتقى' : 'حُفّاظ الملتقى';
  String get _addLabel => _isFemale ? 'إضافة حافظة' : 'إضافة حافظ';

  Future<String> _token() async =>
      (await SharedPreferences.getInstance()).getString('token') ?? '';

  Future<void> _load() async {
    setState(() => _busy = true);
    final token = await _token();
    try {
      final qp = await _genderQP();
      _gender = qp?['gender'];
      final r = await Dio().get(
        '${ApiConfig.baseUrl}/hafadh',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
        queryParameters: qp,
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
      MaterialPageRoute(builder: (_) => AddHafidhPage(gender: _gender)),
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
        label: Text(_addLabel),
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
                    Positioned(
                      right: 8,
                      child: IconButton(
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Image.asset('assets/logo1.png', width: 60, height: 60),
                        const SizedBox(height: 4),
                        Text(
                          _title,
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
                          ? Center(
                              child: Text(_isFemale
                                  ? 'لا توجد حافظات بعد'
                                  : 'لا يوجد حُفّاظ بعد'))
                          : AnimationLimiter(
                              child: ListView.separated(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 8),
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
                                              horizontal: 16, vertical: 8),
                                          shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(12)),
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
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        fontSize: 16),
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  '${h['reg_number']} • ${h['college']}',
                                                  style: const TextStyle(
                                                      color: Colors.black54),
                                                ),
                                                const SizedBox(height: 8),
                                                Row(
                                                  children: [
                                                    const Icon(Icons.date_range,
                                                        size: 18,
                                                        color: Colors.green),
                                                    const SizedBox(width: 4),
                                                    Text(
                                                      'تاريخ الختمة: $date',
                                                      style: GoogleFonts.cairo(
                                                          textStyle:
                                                              const TextStyle(
                                                                  fontSize:
                                                                      14)),
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
