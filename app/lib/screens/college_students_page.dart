// lib/pages/admin/college_students_page.dart
import 'dart:async';
import 'dart:io' show SocketException;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';

import '../../services/api_config.dart';
import '../../services/auth_service.dart';
import 'add_student_page.dart';
import 'edit_student_page.dart';

class CollegeStudentsPage extends StatefulWidget {
  final String college; // "Engineering" أو "Medical" أو "Sharia"
  final String title; // عنوان الـ AppBar
  final Color themeStart; // لون التدرّج البداية
  final Color themeEnd; // لون التدرّج النهاية

  const CollegeStudentsPage({
    Key? key,
    required this.college,
    required this.title,
    required this.themeStart,
    required this.themeEnd,
  }) : super(key: key);

  @override
  State<CollegeStudentsPage> createState() => _CollegeStudentsPageState();
}

class _CollegeStudentsPageState extends State<CollegeStudentsPage> {
  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 8),
    ),
  );

  bool _loading = true;
  List<Map<String, dynamic>> _all = [];
  List<Map<String, dynamic>> _filtered = [];

  final _searchCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  // لون خلفية المحتوى الداخلي
  static const Color _bgLight = Color(0xfff0faf2);

  @override
  void initState() {
    super.initState();
    _fetch();
    _searchCtrl.addListener(() => _applyFilter(_searchCtrl.text));
  }

  @override
  void dispose() {
    _searchCtrl.removeListener(() => _applyFilter(_searchCtrl.text));
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    setState(() => _loading = true);

    final token = await AuthService.token;
    if (token == null || token.isEmpty) {
      _show('يجب تسجيل الدخول أولاً');
      if (mounted) setState(() => _loading = false);
      return;
    }

    try {
      final r = await _dio.get(
        '${ApiConfig.baseUrl}/students',
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
      if (mounted) setState(() => _loading = false);
    }
  }

  void _applyFilter(String q) {
    final query = q.toLowerCase();
    _filtered = _all.where((s) {
      final n = (s['name'] ?? '').toString().toLowerCase();
      final r = (s['reg_number'] ?? '').toString().toLowerCase();
      return n.contains(query) || r.contains(query);
    }).toList();

    if (_scrollCtrl.hasClients) _scrollCtrl.jumpTo(0);
    setState(() {});
  }

  Future<void> _delete(int id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: const Text('هل أنت متأكد؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('لا'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('نعم'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final token = await AuthService.token;
    if (token == null || token.isEmpty) return;

    try {
      await _dio.delete(
        '${ApiConfig.baseUrl}/students/$id',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      _fetch();
    } catch (_) {
      _show('فشل الحذف');
    }
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
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [widget.themeStart, widget.themeEnd],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              Column(
                children: [
                  // الترويسة
                  Container(
                    padding: const EdgeInsets.symmetric(
                      vertical: 16,
                      horizontal: 24,
                    ),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [widget.themeStart, widget.themeEnd],
                      ),
                      borderRadius: const BorderRadius.vertical(
                        bottom: Radius.circular(24),
                      ),
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          icon:
                              const Icon(Icons.arrow_back, color: Colors.white),
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
                      color: Colors.white,
                      child: AnimationLimiter(
                        child: SingleChildScrollView(
                          controller: _scrollCtrl,
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            children: [
                              TextField(
                                controller: _searchCtrl,
                                decoration: InputDecoration(
                                  hintText: 'ابحث بالاسم أو رقم التسجيل',
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
                              if (_loading)
                                const Center(child: CircularProgressIndicator())
                              else if (_filtered.isEmpty)
                                const Center(child: Text('لا توجد بيانات'))
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

              // زر الإضافة
              Positioned(
                bottom: 24,
                right: 24,
                child: FloatingActionButton.extended(
                  backgroundColor: widget.themeStart,
                  icon: const Icon(Icons.person_add),
                  label: const Text('إضافة طالب'),
                  onPressed: () async {
                    final isRoot = await AuthService.isRoot;
                    final ok = await Navigator.push<bool>(
                      ctx,
                      MaterialPageRoute(
                        builder: (_) => AddStudentPage(
                          fixedCollege: isRoot ? null : widget.college,
                          lockCollege: !isRoot,
                          themeStart: widget.themeStart,
                          themeEnd: widget.themeEnd,
                          bgLight: _bgLight,
                        ),
                      ),
                    );
                    if (ok == true) _fetch();
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCards() => AnimationLimiter(
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
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ListTile(
                      title: Text(s['name'] ?? '-', textAlign: TextAlign.right),
                      subtitle: Text('رقم: ${s['reg_number'] ?? '-'}',
                          textAlign: TextAlign.right),
                      trailing: PopupMenuButton<String>(
                        onSelected: (v) async {
                          if (v == 'edit') {
                            final isRoot = await AuthService.isRoot;
                            final ok = await Navigator.push<bool>(
                              context,
                              MaterialPageRoute(
                                builder: (_) => EditStudentPage(
                                  student: Map.from(s),
                                  fixedCollege: isRoot ? null : widget.college,
                                  lockCollege: !isRoot,
                                  themeStart: widget.themeStart,
                                  themeEnd: widget.themeEnd,
                                  bgLight: _bgLight,
                                ),
                              ),
                            );
                            if (ok == true) _fetch();
                          } else {
                            _delete(s['id']);
                          }
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'edit', child: Text('تعديل')),
                          PopupMenuItem(value: 'delete', child: Text('حذف')),
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

  Widget _buildTable() => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: MaterialStateProperty.all(widget.themeStart),
          headingTextStyle: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
          columns: const [
            DataColumn(label: Text('الاسم')),
            DataColumn(label: Text('رقم التسجيل')),
            DataColumn(label: Text('الهاتف')),
            DataColumn(label: Text('مشرف')),
            DataColumn(label: Text('تحكم')),
          ],
          rows: _filtered.map((s) {
            return DataRow(
              cells: [
                DataCell(Text(s['name'] ?? '-')),
                DataCell(Text(s['reg_number'] ?? '-')),
                DataCell(Text(s['phone'] ?? '-')),
                DataCell(Text(s['supervisor_name'] ?? '-')),
                DataCell(
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit, size: 20),
                        onPressed: () async {
                          final isRoot = await AuthService.isRoot;
                          final ok = await Navigator.push<bool>(
                            context,
                            MaterialPageRoute(
                              builder: (_) => EditStudentPage(
                                student: Map.from(s),
                                fixedCollege: isRoot ? null : widget.college,
                                lockCollege: !isRoot,
                                themeStart: widget.themeStart,
                                themeEnd: widget.themeEnd,
                                bgLight: _bgLight,
                              ),
                            ),
                          );
                          if (ok == true) _fetch();
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, size: 20),
                        onPressed: () => _delete(s['id']),
                      ),
                    ],
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      );
}
