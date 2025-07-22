import 'dart:async';
import 'dart:io' show SocketException;
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';

import '../../services/api_config.dart';
import '../../services/auth_service.dart';
import 'add_student_page.dart';
import 'edit_student_page.dart';

class StudentsListPage extends StatefulWidget {
  const StudentsListPage({Key? key}) : super(key: key);
  @override
  State<StudentsListPage> createState() => _StudentsListPageState();
}

class _StudentsListPageState extends State<StudentsListPage> {
  // ثوابت الألوان
  static const _greenStart = Color(0xff27ae60);
  static const _greenEnd = Color(0xff219150);
  static const _bgLight = Color(0xfff0faf2);

  // بيانات الطلاب
  final List<Map<String, dynamic>> _all = [];
  List<Map<String, dynamic>> _filtered = [];
  bool _loading = true;

  // تحكم البحث والتمرير
  final _searchCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  // عميل Dio
  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 8),
    ),
  );

  @override
  void initState() {
    super.initState();
    _fetch();
    _searchCtrl.addListener(() => _applyFilter(_searchCtrl.text));
  }

  String _txt(dynamic v) =>
      (v == null || v.toString().trim().isEmpty) ? '‑' : v.toString();

  Future<void> _fetch() async {
    setState(() => _loading = true);
    final token = await AuthService.token;
    if (token == null || token.isEmpty) {
      _show('يجب تسجيل الدخول أولاً');
      setState(() => _loading = false);
      return;
    }
    try {
      final r = await _dio.get(
        '${ApiConfig.baseUrl}/students',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      if (r.statusCode == 200) {
        _all
          ..clear()
          ..addAll(List<Map<String, dynamic>>.from(r.data));
        _applyFilter(_searchCtrl.text);
      } else {
        throw DioException(
          requestOptions: r.requestOptions,
          response: r,
          type: DioExceptionType.badResponse,
          error: 'HTTP ${r.statusCode}',
        );
      }
    } on SocketException {
      _show('تعذّر الاتصال بالخادم');
    } on TimeoutException {
      _show('انتهت مهلة الاتصال بالخادم');
    } on DioException catch (e) {
      _show('خطأ الاتصال: ${e.message}');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _show(String m) {
    if (mounted)
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  void _applyFilter(String q) {
    setState(() {
      _filtered = _all.where((s) {
        final n = _txt(s['name']).toLowerCase();
        final r = _txt(s['reg_number']).toLowerCase();
        q = q.toLowerCase();
        return n.contains(q) || r.contains(q);
      }).toList();
      _scrollCtrl.jumpTo(0);
    });
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
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final token = await AuthService.token;
    if (token == null) return;
    try {
      await _dio.delete(
        '${ApiConfig.baseUrl}/students/$id',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      _show('تم الحذف');
      _fetch();
    } catch (_) {
      _show('فشل الحذف');
    }
  }

  @override
  Widget build(BuildContext ctx) {
    final w = MediaQuery.of(ctx).size.width;
    final isWide = w > 700;

    return Scaffold(
      // خلفية التدرج اللوني
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [_greenStart, _greenEnd],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              Column(
                children: [
                  // ترويسة الصفحة
                  Container(
                    padding: const EdgeInsets.symmetric(
                      vertical: 16,
                      horizontal: 24,
                    ),
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
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(
                            Icons.arrow_back,
                            color: Colors.white,
                          ),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                        Expanded(
                          child: Center(
                            child: Text(
                              'قائمة الطلاب',
                              style: GoogleFonts.cairo(
                                textStyle: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // المحتوى الرئيسي
                  // الشعار في الأعلى
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Image.asset(
                      'assets/logo1.png',
                      width: 100,
                      height: 100,
                    ),
                  ),
                  Expanded(
                    child: Container(
                      color: _bgLight,
                      child: AnimationLimiter(
                        child: SingleChildScrollView(
                          controller: _scrollCtrl,
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            children: [
                              // مربع البحث
                              TextField(
                                controller: _searchCtrl,
                                decoration: InputDecoration(
                                  filled: true,
                                  fillColor: Colors.white,
                                  hintText: 'ابحث بالاسم أو رقم التسجيل...',
                                  prefixIcon: const Icon(Icons.search),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide.none,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              // تحميل أو عرض البيانات
                              _loading
                                  ? const Center(
                                      child: CircularProgressIndicator(),
                                    )
                                  : _filtered.isEmpty
                                  ? const Center(child: Text('لا يوجد بيانات'))
                                  : isWide
                                  ? _buildTable()
                                  : _buildCards(),
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
                  backgroundColor: _greenStart,
                  icon: const Icon(Icons.person_add),
                  label: const Text('إضافة طالب'),
                  onPressed: () async {
                    final ok = await Navigator.push<bool>(
                      ctx,
                      MaterialPageRoute(builder: (_) => const AddStudentPage()),
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

  // بناء بطاقات العرض للهواتف
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
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(16),
                    title: Text(
                      _txt(s['name']),
                      textAlign: TextAlign.right,
                      style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'رقم التسجيل: ${_txt(s['reg_number'])}',
                          textAlign: TextAlign.right,
                        ),
                        Text(
                          'الهاتف: ${_txt(s['phone'])}',
                          textAlign: TextAlign.right,
                        ),
                        Text(
                          'الكلية: ${_txt(s['college'])}',
                          textAlign: TextAlign.right,
                        ),
                        Text(
                          'المشرف: ${_txt(s['supervisor_name'])}',
                          textAlign: TextAlign.right,
                        ),
                      ],
                    ),
                    trailing: PopupMenuButton<String>(
                      onSelected: (v) {
                        if (v == 'edit') {
                          Navigator.push<bool>(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  EditStudentPage(student: Map.from(s)),
                            ),
                          ).then((ok) {
                            if (ok == true) _fetch();
                          });
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
  }

  // بناء الجدول للأجهزة العريضة
  Widget _buildTable() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowColor: MaterialStateProperty.all(_greenStart),
        headingTextStyle: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
        columns: const [
          DataColumn(label: Text('الاسم')),
          DataColumn(label: Text('رقم التسجيل')),
          DataColumn(label: Text('الهاتف')),
          DataColumn(label: Text('الكلية')),
          DataColumn(label: Text('المشرف')),
          DataColumn(label: Text('تحكم')),
        ],
        rows: _filtered.map((s) {
          return DataRow(
            cells: [
              DataCell(Text(_txt(s['name']))),
              DataCell(Text(_txt(s['reg_number']))),
              DataCell(Text(_txt(s['phone']))),
              DataCell(Text(_txt(s['college']))),
              DataCell(Text(_txt(s['supervisor_name']))),
              DataCell(
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit, size: 20),
                      onPressed: () async {
                        final ok = await Navigator.push<bool>(
                          context,
                          MaterialPageRoute(
                            builder: (_) => EditStudentPage(student: s),
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

  @override
  void dispose() {
    _scrollCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }
}
