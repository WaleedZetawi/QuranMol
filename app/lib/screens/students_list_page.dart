// lib/features/admin/students/students_list_page.dart
import 'dart:async';
import 'dart:io' show SocketException;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';

import '../../../services/dio_client.dart';
import '../../../services/auth_service.dart';
import 'add_student_page.dart';
import 'edit_student_page.dart';

/// helper: احسب gender من الدور أو الكلية
Future<Map<String, String>?> _genderQP() async {
  final role = await AuthService.role; // أضِف getter إن مش موجود
  final col = await AuthService.college; // قد تكون null

  if (role == 'admin_dash_f') return const {'gender': 'female'};
  if (role == 'admin_dashboard') return const {'gender': 'male'};

  const femaleCols = {'NewCampus', 'OldCampus', 'Agriculture'};
  const maleCols = {'Engineering', 'Medical', 'Sharia'};
  if (col == null) return null;
  if (femaleCols.contains(col)) return const {'gender': 'female'};
  if (maleCols.contains(col)) return const {'gender': 'male'};
  return null;
}

class StudentsListPage extends StatefulWidget {
  const StudentsListPage({Key? key}) : super(key: key);

  @override
  State<StudentsListPage> createState() => _StudentsListPageState();
}

class _StudentsListPageState extends State<StudentsListPage> {
  static const Color _greenStart = Color(0xff27ae60);
  static const Color _greenEnd = Color(0xff219150);
  static const Color _bgLight = Color(0xfff0faf2);

  final List<Map<String, dynamic>> _all = [];
  List<Map<String, dynamic>> _filtered = [];
  bool _loading = true;

  final _searchCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  Dio get _dio => DioClient().dio;

  String? _gender; // 'male' | 'female' | null

  bool get _isFemale => (_gender ?? '').toLowerCase() == 'female';
  String get _title => _isFemale ? 'قائمة الطالبات' : 'قائمة الطلاب';
  String get _addLabel => _isFemale ? 'إضافة طالبة' : 'إضافة طالب';
  String get _supLabel => _isFemale ? 'المشرفة' : 'المشرف';

  @override
  void initState() {
    super.initState();
    _initAndFetch();
    _searchCtrl.addListener(() => _applyFilter(_searchCtrl.text));
  }

  Future<void> _initAndFetch() async {
    final qp = await _genderQP();
    setState(() {
      _gender = qp?['gender'];
    });
    await _fetch();
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  String _txt(dynamic v) =>
      (v == null || v.toString().trim().isEmpty) ? '-' : v.toString();

  Future<void> _fetch() async {
    setState(() => _loading = true);
    try {
      final qp = await _genderQP();
      final r = await _dio.get('/students', queryParameters: qp);
      final data = List<Map<String, dynamic>>.from(r.data as List);
      _all
        ..clear()
        ..addAll(data);
      _applyFilter(_searchCtrl.text);
    } on SocketException {
      _show('تعذّر الاتصال بالخادم');
    } on TimeoutException {
      _show('انتهت مهلة الاتصال بالخادم');
    } on DioException catch (e) {
      _show('خطأ الاتصال: ${e.message}');
    } catch (e) {
      _show('حدث خطأ غير متوقع');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _show(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(m, style: GoogleFonts.cairo())),
    );
  }

  void _applyFilter(String q) {
    final query = q.toLowerCase();
    _filtered = _all.where((s) {
      final n = _txt(s['name']).toLowerCase();
      final r = _txt(s['reg_number']).toLowerCase();
      return n.contains(query) || r.contains(query);
    }).toList();

    if (_scrollCtrl.hasClients) {
      _scrollCtrl.jumpTo(0);
    }
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
              child: const Text('إلغاء')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('حذف')),
        ],
      ),
    );

    if (ok != true) return;

    try {
      await _dio.delete('/students/$id');
      _show('تم الحذف');
      _fetch();
    } on DioException catch (e) {
      _show('فشل الحذف: ${e.message}');
    } catch (_) {
      _show('فشل الحذف');
    }
  }

  /// احسب بارامترات الكلية/السماح حسب الدور الحالي
  Future<
      ({
        String? fixedCollege,
        bool lockCollege,
        List<String>? allowedColleges
      })> _calcCollegeParams() async {
    final role = await AuthService
        .role; // 'admin_dashboard' | 'admin_dash_f' | 'CollegeAdmin' | ...
    final college = await AuthService.college;

    String? fixedCollege;
    bool lockCollege = false;
    List<String>? allowedColleges;

    const femaleCols = ['NewCampus', 'OldCampus', 'Agriculture'];

    if (role == 'admin_dashboard') {
      // المشرف العام: حر يختار (يمكن تقييده لاحقًا إن أردت)
      fixedCollege = null;
      lockCollege = false;
      // مثال لو أردت قصره على كليات الذكور:
      // allowedColleges = ['Engineering','Medical','Sharia'];
    } else if (role == 'admin_dash_f') {
      // المسؤولة العامة للبنات: تختار من كليات البنات فقط
      fixedCollege = null;
      lockCollege = false;
      allowedColleges = femaleCols;
    } else if (role == 'CollegeAdmin') {
      // مسؤول/ـة كلية واحدة: ثبّت الكلية
      fixedCollege = college;
      lockCollege = true;
      allowedColleges = college != null ? [college!] : null;
    } else {
      // fallback آمن
      fixedCollege = college;
      lockCollege = college != null;
      allowedColleges = college != null ? [college!] : femaleCols;
    }

    return (
      fixedCollege: fixedCollege,
      lockCollege: lockCollege,
      allowedColleges: allowedColleges
    );
  }

  Future<void> _openAddStudent(BuildContext ctx) async {
    final p = await _calcCollegeParams();
    final ok = await Navigator.push<bool>(
      ctx,
      MaterialPageRoute(
        builder: (_) => AddStudentPage(
          fixedCollege: p.fixedCollege,
          lockCollege: p.lockCollege,
          allowedColleges: p.allowedColleges, // مهم
          themeStart: _greenStart,
          themeEnd: _greenEnd,
          bgLight: _bgLight,
          gender: _gender,
        ),
      ),
    );
    if (ok == true) _fetch();
  }

  Future<void> _openEditStudent(Map<String, dynamic> s) async {
    final p = await _calcCollegeParams();
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => EditStudentPage(
          student: Map.from(s),
          fixedCollege: p.fixedCollege,
          lockCollege: p.lockCollege,
          allowedColleges: p.allowedColleges, // مهم
          themeStart: _greenStart,
          themeEnd: _greenEnd,
          bgLight: _bgLight,
          gender: _gender,
        ),
      ),
    );
    if (ok == true) _fetch();
  }

  @override
  Widget build(BuildContext ctx) {
    final w = MediaQuery.of(ctx).size.width;
    final isWide = w > 700;

    return Scaffold(
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
                  // header
                  Container(
                    padding: const EdgeInsets.symmetric(
                        vertical: 16, horizontal: 24),
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
                          icon:
                              const Icon(Icons.arrow_back, color: Colors.white),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                        Expanded(
                          child: Center(
                            child: Text(
                              _title,
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

                  // logo
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Image.asset('assets/logo1.png',
                        width: 100, height: 100),
                  ),

                  // content
                  Expanded(
                    child: Container(
                      color: _bgLight,
                      child: RefreshIndicator(
                        onRefresh: _fetch,
                        child: AnimationLimiter(
                          child: SingleChildScrollView(
                            controller: _scrollCtrl,
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              children: [
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
                                if (_loading)
                                  const Center(
                                      child: CircularProgressIndicator())
                                else if (_filtered.isEmpty)
                                  Text('لا يوجد بيانات',
                                      style: GoogleFonts.cairo())
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
                  ),
                ],
              ),

              // add FAB
              Positioned(
                bottom: 24,
                right: 24,
                child: FloatingActionButton.extended(
                  backgroundColor: _greenStart,
                  icon: const Icon(Icons.person_add),
                  label: Text(_addLabel,
                      style: GoogleFonts.cairo(color: Colors.white)),
                  onPressed: () => _openAddStudent(ctx),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Cards (phones)
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
                        Text('رقم التسجيل: ${_txt(s['reg_number'])}',
                            textAlign: TextAlign.right,
                            style: GoogleFonts.cairo()),
                        Text('الهاتف: ${_txt(s['phone'])}',
                            textAlign: TextAlign.right,
                            style: GoogleFonts.cairo()),
                        Text('الكلية: ${_txt(s['college'])}',
                            textAlign: TextAlign.right,
                            style: GoogleFonts.cairo()),
                        Text('$_supLabel: ${_txt(s['supervisor_name'])}',
                            textAlign: TextAlign.right,
                            style: GoogleFonts.cairo()),
                      ],
                    ),
                    trailing: PopupMenuButton<String>(
                      onSelected: (v) async {
                        if (v == 'edit') {
                          _openEditStudent(s);
                        } else {
                          _delete(s['id'] as int);
                        }
                      },
                      itemBuilder: (_) => [
                        PopupMenuItem(
                            value: 'edit',
                            child: Text('تعديل', style: GoogleFonts.cairo())),
                        PopupMenuItem(
                            value: 'delete',
                            child: Text('حذف', style: GoogleFonts.cairo())),
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

  // Table (wide screens)
  Widget _buildTable() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowColor: MaterialStateProperty.all(_greenStart),
        headingTextStyle:
            const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        columns: [
          const DataColumn(label: Text('الاسم')),
          const DataColumn(label: Text('رقم التسجيل')),
          const DataColumn(label: Text('الهاتف')),
          const DataColumn(label: Text('الكلية')),
          DataColumn(label: Text(_supLabel)),
          const DataColumn(label: Text('تحكم')),
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
                      onPressed: () => _openEditStudent(s),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete, size: 20),
                      onPressed: () => _delete(s['id'] as int),
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
}
