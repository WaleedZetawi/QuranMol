// lib/pages/admin/college_supervisors_page.dart
import 'dart:async';
import 'dart:io' show SocketException;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/api_config.dart';
import '../../services/auth_service.dart';

class CollegeSupervisorsPage extends StatefulWidget {
  final String college;
  final String title;
  final Color themeStart;
  final Color themeEnd;

  const CollegeSupervisorsPage({
    Key? key,
    required this.college,
    required this.title,
    required this.themeStart,
    required this.themeEnd,
  }) : super(key: key);

  @override
  State<CollegeSupervisorsPage> createState() => _CollegeSupervisorsPageState();
}

class _CollegeSupervisorsPageState extends State<CollegeSupervisorsPage> {
  static const _bgLight = Color(0xfff0faf2);

  final _searchCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 8),
    ),
  );

  bool _busy = true;
  List<Map<String, dynamic>> _all = [];
  List<Map<String, dynamic>> _filtered = [];

  @override
  void initState() {
    super.initState();
    _load();
    _searchCtrl.addListener(() => _applyFilter(_searchCtrl.text));
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _busy = true);

    final token = await AuthService.token;
    if (token == null || token.isEmpty) {
      _show('يجب تسجيل الدخول');
      setState(() => _busy = false);
      return;
    }

    try {
      final r = await _dio.get(
        '${ApiConfig.baseUrl}/supervisors',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      final data = List<Map<String, dynamic>>.from(r.data);
      _all = data.where((s) => s['college'] == widget.college).toList();
      _applyFilter(_searchCtrl.text);
    } on SocketException {
      _show('تعذّر الاتصال بالخادم');
    } on TimeoutException {
      _show('انتهت مهلة الاتصال بالخادم');
    } catch (_) {
      _show('فشل جلب البيانات');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _applyFilter(String q) {
    final query = q.toLowerCase();
    _filtered = _all.where((s) {
      final name = (s['name'] ?? '').toString().toLowerCase();
      final phone = (s['phone'] ?? '').toString().toLowerCase();
      return name.contains(query) || phone.contains(query);
    }).toList();
    if (_scrollCtrl.hasClients) _scrollCtrl.jumpTo(0);
    setState(() {});
  }

  void _show(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  @override
  Widget build(BuildContext ctx) {
    final isWide = MediaQuery.of(ctx).size.width > 700;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [widget.themeStart, widget.themeEnd],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // HEADER
              Container(
                padding:
                    const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                      colors: [widget.themeStart, widget.themeEnd]),
                  borderRadius:
                      const BorderRadius.vertical(bottom: Radius.circular(24)),
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                    Expanded(
                      child: Center(
                        child: Text(
                          widget.title,
                          style: GoogleFonts.cairo(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),
              Image.asset('assets/logo1.png', width: 100, height: 100),
              const SizedBox(height: 16),

              Expanded(
                child: Container(
                  color: _bgLight,
                  child: AnimationLimiter(
                    child: SingleChildScrollView(
                      controller: _scrollCtrl,
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          TextField(
                            controller: _searchCtrl,
                            decoration: InputDecoration(
                              hintText: 'ابحث بالاسم أو الهاتف…',
                              prefixIcon: const Icon(Icons.search),
                              filled: true,
                              fillColor: Colors.white,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          if (_busy)
                            const Center(child: CircularProgressIndicator())
                          else if (_filtered.isEmpty)
                            const Center(child: Text('لا يوجد مشرفون'))
                          else if (isWide)
                            _buildTable()
                          else
                            _buildCards(),
                        ],
                      ),
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

  Widget _buildCards() {
    return AnimationLimiter(
      child: ListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _filtered.length,
        itemBuilder: (_, i) {
          final s = _filtered[i];
          return AnimationConfiguration.staggeredList(
            position: i,
            duration: const Duration(milliseconds: 500),
            child: SlideAnimation(
              verticalOffset: 50,
              child: FadeInAnimation(
                child: Card(
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(16),
                    title: Text(
                      s['name'] ?? '—',
                      textAlign: TextAlign.right,
                      style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('الهاتف: ${s['phone'] ?? '-'}',
                            textAlign: TextAlign.right),
                        Text('البريد: ${s['email'] ?? '-'}',
                            textAlign: TextAlign.right),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTable() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowColor: MaterialStateProperty.all(widget.themeStart),
        headingTextStyle:
            const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        columns: const [
          DataColumn(label: Text('الاسم')),
          DataColumn(label: Text('الهاتف')),
          DataColumn(label: Text('البريد')),
        ],
        rows: _filtered.map((s) {
          return DataRow(cells: [
            DataCell(Text(s['name'] ?? '-')),
            DataCell(Text(s['phone'] ?? '-')),
            DataCell(Text(s['email'] ?? '-')),
          ]);
        }).toList(),
      ),
    );
  }
}
