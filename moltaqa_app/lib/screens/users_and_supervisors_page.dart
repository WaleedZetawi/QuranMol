// lib/features/admin/users_and_supervisors/users_and_supervisors_page.dart

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/api_config.dart';
import 'add_supervisor_page.dart';
import 'edit_supervisor_page.dart';
import 'edit_admin_page.dart';

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

  /// map college → its admin‐role
  final Map<String, String> _roleMap = {
    'Engineering': 'EngAdmin',
    'Medical': 'MedicalAdmin',
    'Sharia': 'shariaAdmin',
  };

  @override
  void initState() {
    super.initState();
    _loadData();
    _searchCtrl.addListener(() => setState(() {}));
  }

  Future<void> _loadData() async {
    setState(() => _busy = true);
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token') ?? '';
    final dio = Dio(BaseOptions(headers: {'Authorization': 'Bearer $token'}));

    try {
      final respUsers = await dio.get('${ApiConfig.baseUrl}/users');
      final respSups = await dio.get('${ApiConfig.baseUrl}/supervisors');

      final users = List<Map<String, dynamic>>.from(respUsers.data);
      final sups = List<Map<String, dynamic>>.from(respSups.data);

      _admins = users.where((u) {
        return (u['role'] as String).endsWith('Admin');
      }).toList();

      _sups = sups;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('تعذّر تحميل البيانات')));
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

    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token') ?? '';
    final dio = Dio(BaseOptions(headers: {'Authorization': 'Bearer $token'}));
    await dio.delete('${ApiConfig.baseUrl}/supervisors/$id');
    _loadData();
  }

  /// groups your admins/sups by college, applying the search filter
  Map<String, Map<String, dynamic>> _grouped() {
    final q = _searchCtrl.text.trim().toLowerCase();
    final out = <String, Map<String, dynamic>>{};

    for (final college in _roleMap.keys) {
      // find the matching admin
      final admin = _admins.firstWhere(
        (u) => u['role'] as String == _roleMap[college],
        orElse: () => <String, dynamic>{},
      );

      // all sups for that college
      var list = _sups.where((s) => s['college'] == college).toList();

      // apply search
      if (q.isNotEmpty) {
        list = list.where((s) {
          final name = (s['name'] as String).toLowerCase();
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

      // floating ADD button
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: _greenStart,
        icon: const Icon(Icons.person_add, color: Colors.white),
        label: const Text('إضافة مشرف', style: TextStyle(color: Colors.white)),
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
                hintStyle: const TextStyle(color: Colors.black45),
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
                        const SnackBar(content: Text('لا يوجد مسؤول محدد')),
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
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            if ((admin['phone'] ?? '').toString().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4, left: 32),
                child: Text(
                  'الهاتف: ${admin['phone']}',
                  style: const TextStyle(color: Colors.black54, fontSize: 12),
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
                  style: const TextStyle(color: Colors.black54),
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
                      _deleteSupervisor(s['id']);
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('تعديل')),
                    PopupMenuItem(value: 'del', child: Text('حذف')),
                  ],
                ),
              ),
            ),

            if (sups.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'لا يوجد مشرفين بعد',
                  style: const TextStyle(color: Colors.black54),
                ),
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
