import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../services/dio_client.dart';
import '../../../services/auth_service.dart';
import 'add_supervisor_page.dart';
import 'edit_supervisor_page.dart';
import 'edit_admin_page.dart';

/// helper: احسب gender من الدور أو الكلية
Future<Map<String, String>?> _genderQP() async {
  final role = await AuthService.role; // أضِف getter إن مش موجود
  final col = await AuthService.college; // قد تكون null

  // أدوار لوحات الملتقى:
  // - admin_dash_f  => مسؤولة الملتقى (بنات فقط)
  // - admin_dashboard => مسؤول الملتقى (ذكور فقط)
  if (role == 'admin_dash_f') return const {'gender': 'female'};
  if (role == 'admin_dashboard') return const {'gender': 'male'};

  // لو كان مسؤول كلية معيّن
  const femaleCols = {'NewCampus', 'OldCampus', 'Agriculture'};
  const maleCols = {'Engineering', 'Medical', 'Sharia'};
  if (col == null) return null; // super admin عام (لو موجود)
  if (femaleCols.contains(col)) return const {'gender': 'female'};
  if (maleCols.contains(col)) return const {'gender': 'male'};
  return null;
}

class UsersAndSupervisorsPage extends StatefulWidget {
  const UsersAndSupervisorsPage({super.key});

  @override
  State<UsersAndSupervisorsPage> createState() =>
      _UsersAndSupervisorsPageState();
}

class _UsersAndSupervisorsPageState extends State<UsersAndSupervisorsPage> {
  static const _greenStart = Color(0xFF27AE60);
  static const _greenEnd = Color(0xFF219150);
  static const _bgLight = Color(0xFFF0FAF2);

  final _searchCtrl = TextEditingController();
  bool _busy = true;
  List<Map<String, dynamic>> _admins = [], _sups = [];

  /// خريطة أدوار اختيارية (لو كان عندك أسماء أدوار ثابتة)
  final Map<String, String> _roleMap = const {
    'Engineering': 'EngAdmin',
    'Medical': 'MedicalAdmin',
    'Sharia': 'shariaAdmin',
    // ✅ أدوار مجمّعات الإناث
    'NewCampus': 'NewCampusAdmin',
    'OldCampus': 'OldCampusAdmin',
    'Agriculture': 'AgricultureAdmin',
  };

  Dio get _dio => DioClient().dio;

  @override
  void initState() {
    super.initState();
    _loadData();
    _searchCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _busy = true);
    try {
      final qp = await _genderQP();

      // users: بدون gender
      final respUsers = await _dio.get('/users');

      // supervisors: مع gender ديناميكي
      final respSups = await _dio.get(
        '/supervisors',
        queryParameters: qp,
      );

      final users = List<Map<String, dynamic>>.from(respUsers.data as List);
      final sups = List<Map<String, dynamic>>.from(respSups.data as List);

      _admins = users.where((u) {
        final role = (u['role'] ?? '').toString();
        return role.endsWith('Admin');
      }).toList();

      _sups = sups;
    } on DioException catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text('تعذّر تحميل البيانات', style: GoogleFonts.cairo())),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteSupervisor(int id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: const Text('هل تريد حذف هذا المشرف نهائيًا؟'),
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

    try {
      await _dio.delete('/supervisors/$id');
      await _loadData();
    } on DioException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text('فشل الحذف: ${e.message}', style: GoogleFonts.cairo())),
      );
    }
  }

  /// تجميع المسؤولين/المشرفين حسب الكلية + تطبيق البحث
  Map<String, Map<String, dynamic>> _grouped() {
    final q = _searchCtrl.text.trim().toLowerCase();

    // استنتج الكليات الموجودة من بيانات المشرفين أولاً
    final colleges = <String>{};
    for (final s in _sups) {
      final c = (s['college'] ?? '').toString();
      if (c.isNotEmpty) colleges.add(c);
    }
    // لو ما قدرنا نستنتج، جرّب من بيانات المسؤولين (لو فيها college)
    if (colleges.isEmpty) {
      for (final a in _admins) {
        final c = (a['college'] ?? '').toString();
        if (c.isNotEmpty) colleges.add(c);
      }
    }
    // ولو برضه فاضي، استخدم مفاتيح خريطة الأدوار (اختياري)
    if (colleges.isEmpty) {
      colleges.addAll(_roleMap.keys);
    }

    final out = <String, Map<String, dynamic>>{};
    for (final college in colleges) {
      // ابحث عن المسؤول حسب college إن أمكن
      Map<String, dynamic> admin = _admins.firstWhere(
        (u) => (u['college'] ?? '') == college,
        orElse: () => <String, dynamic>{},
      );

      // لو ما لقيناه بالكلية، جرّب عبر الاسم الدور من _roleMap
      if (admin.isEmpty && _roleMap[college] != null) {
        final wantedRole = _roleMap[college]!;
        admin = _admins.firstWhere(
          (u) => (u['role'] ?? '') == wantedRole,
          orElse: () => <String, dynamic>{},
        );
      }

      // كل المشرفين ضمن الكلية
      var list = _sups.where((s) => (s['college'] ?? '') == college).toList();

      // تطبيق البحث
      if (q.isNotEmpty) {
        list = list.where((s) {
          final name = (s['name'] ?? '').toString().toLowerCase();
          final phone = (s['phone'] ?? '').toString().toLowerCase();
          return name.contains(q) || phone.contains(q);
        }).toList();
      }

      out[college] = {'admin': admin, 'sups': list};
    }

    return out;
  }

  @override
  Widget build(BuildContext ctx) {
    return Scaffold(
      backgroundColor: _bgLight,

      // زر إضافة مشرف
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: _greenStart,
        icon: const Icon(Icons.person_add, color: Colors.white),
        label:
            Text('إضافة مشرف', style: GoogleFonts.cairo(color: Colors.white)),
        onPressed: () async {
          final ok = await Navigator.push<bool>(
            ctx,
            MaterialPageRoute(builder: (_) => const AddSupervisorPage()),
          );
          if (ok == true) _loadData();
        },
      ),

      body: Column(
        children: [
          // ─── HEADER ───
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 20),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [_greenStart, _greenEnd],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
            ),
            child: SafeArea(
              bottom: false,
              child: Directionality(
                textDirection: TextDirection.rtl,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    PositionedDirectional(
                      start: 12,
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
                            width: 64,
                            height: 64,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'المسؤولون والمشرفون',
                          style: GoogleFonts.cairo(
                            fontSize: 22,
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
          ),

          // ─── SEARCH ───
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'ابحث بالاسم أو الهاتف…',
                hintStyle: GoogleFonts.cairo(color: Colors.black45),
                prefixIcon: const Icon(Icons.search, color: Colors.black54),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),

          // ─── CONTENT ───
          Expanded(
            child: _busy
                ? const Center(child: CircularProgressIndicator())
                : AnimationLimiter(
                    child: ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      children: _grouped().entries.mapIndexed((i, entry) {
                        final college = entry.key;
                        final admin =
                            entry.value['admin'] as Map<String, dynamic>;
                        final sups =
                            (entry.value['sups'] as List<Map<String, dynamic>>);

                        if (_searchCtrl.text.isNotEmpty &&
                            admin.isEmpty &&
                            sups.isEmpty) {
                          return const SizedBox.shrink();
                        }

                        return AnimationConfiguration.staggeredList(
                          position: i,
                          duration: const Duration(milliseconds: 600),
                          child: SlideAnimation(
                            verticalOffset: 50,
                            child: FadeInAnimation(
                              child: _buildCollegeCard(college, admin, sups),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildCollegeCard(
    String college,
    Map<String, dynamic> admin,
    List<Map<String, dynamic>> sups,
  ) {
    final displayAdmin = (admin['name'] ?? '').toString().isNotEmpty
        ? admin['name']
        : (admin['reg_number'] ?? 'غير محدد');

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // header row
            Row(
              children: [
                Expanded(
                  child: Text(
                    college,
                    style: TextStyle(
                      color: _greenStart,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.edit, color: _greenStart),
                  onPressed: () async {
                    if (admin.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                            content: Text('لا يوجد مسؤول محدد',
                                style: GoogleFonts.cairo())),
                      );
                      return;
                    }
                    final ok = await Navigator.push<bool>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => EditAdminPage(data: admin),
                      ),
                    );
                    if (ok == true) _loadData();
                  },
                ),
              ],
            ),

            // admin info
            Row(
              children: [
                const Icon(Icons.verified_user, color: Colors.grey),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'المسؤول: $displayAdmin',
                    style: GoogleFonts.cairo(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            if ((admin['phone'] ?? '').toString().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4, left: 32),
                child: Text(
                  'الهاتف: ${admin['phone']}',
                  style: GoogleFonts.cairo(color: Colors.black54, fontSize: 12),
                ),
              ),

            const Divider(height: 24),

            // supervisors list
            ...sups.map(
              (s) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(
                  Icons.supervisor_account,
                  color: _greenStart,
                ),
                title: Text(
                  s['name'],
                  style: GoogleFonts.cairo(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  '${s['phone'] ?? '-'} • ${s['college']}',
                  style: GoogleFonts.cairo(color: Colors.black54),
                ),
                trailing: PopupMenuButton<String>(
                  onSelected: (v) {
                    if (v == 'edit') {
                      Navigator.push<bool>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => EditSupervisorPage(data: s),
                        ),
                      ).then((ok) => ok == true ? _loadData() : null);
                    } else {
                      _deleteSupervisor(s['id'] as int);
                    }
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                        value: 'edit',
                        child: Text('تعديل', style: GoogleFonts.cairo())),
                    PopupMenuItem(
                        value: 'del',
                        child: Text('حذف', style: GoogleFonts.cairo())),
                  ],
                ),
              ),
            ),

            if (sups.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('لا يوجد مشرفين بعد',
                    style: GoogleFonts.cairo(color: Colors.black54)),
              ),
          ],
        ),
      ),
    );
  }
}

/// tiny helper so you can do `.mapIndexed(...)` on `entries`
extension _IterableIndexed<E> on Iterable<E> {
  Iterable<T> mapIndexed<T>(T Function(int index, E e) fn) sync* {
    var i = 0;
    for (final e in this) {
      yield fn(i, e);
      i++;
    }
  }
}
