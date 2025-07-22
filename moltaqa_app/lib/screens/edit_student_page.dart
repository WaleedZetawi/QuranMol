// lib/features/admin/students/edit_student_page.dart

import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/api_config.dart';

class EditStudentPage extends StatefulWidget {
  final Map<String, dynamic> student;
  const EditStudentPage({super.key, required this.student});

  @override
  State<EditStudentPage> createState() => _EditStudentPageState();
}

class _EditStudentPageState extends State<EditStudentPage> {
  static const _greenStart = Color(0xff27ae60);
  static const _greenEnd = Color(0xff219150);
  static const _bgLight = Color(0xfff0faf2);

  final _formKey = GlobalKey<FormState>();
  late TextEditingController _name;
  late TextEditingController _phone;
  late TextEditingController _email;
  String? _college;
  late ValueNotifier<String> _studentType;
  late List<Map<String, dynamic>> _supers;
  int? _supervisorId;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.student['name']);
    _phone = TextEditingController(text: widget.student['phone']);
    _email = TextEditingController(text: widget.student['email'] ?? '');
    _college = widget.student['college'];
    _studentType = ValueNotifier(widget.student['student_type'] ?? 'regular');
    _supervisorId = widget.student['supervisor_id'];
    _supers = [];
    _fetchSupers(_college);
  }

  Future<void> _fetchSupers(String? coll) async {
    setState(() {
      _supers = [];
      _supervisorId = null;
    });
    if (coll == null) return;
    try {
      final r = await Dio().get(
        '${ApiConfig.baseUrl}/public/regular-supervisors',
        queryParameters: {'college': coll},
      );
      if (!mounted) return;
      setState(() {
        _supers = List<Map<String, dynamic>>.from(r.data);
        if (_supervisorId != null &&
            !_supers.any((s) => s['id'] == _supervisorId)) {
          _supervisorId = null;
        }
      });
    } catch (_) {}
  }

  Future<String> _token() async =>
      (await SharedPreferences.getInstance()).getString('token') ?? '';

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    final token = await _token();
    try {
      await Dio().put(
        '${ApiConfig.baseUrl}/students/${widget.student['id']}',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
        data: {
          'name': _name.text.trim(),
          'phone': _phone.text.trim(),
          'email': _email.text.trim(),
          'college': _college,
          'student_type': _studentType.value,
          'supervisor_id': _supervisorId,
        },
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } on DioException catch (e) {
      final msg = e.response?.data['message'] ?? 'فشل التعديل';
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg, style: GoogleFonts.cairo())),
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _field(
    String label,
    TextEditingController ctrl, {
    TextInputType? kb,
    bool req = true,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: TextFormField(
        controller: ctrl,
        keyboardType: kb,
        style: GoogleFonts.cairo(),
        validator: (v) =>
            !req || (v != null && v.trim().isNotEmpty) ? null : 'مطلوب',
        decoration: InputDecoration(
          labelText: label,
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  Widget _dropdownCollege() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: DropdownButtonFormField<String>(
        value: _college,
        decoration: InputDecoration(
          labelText: 'الكلية',
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
        items: const [
          DropdownMenuItem(value: 'Engineering', child: Text('Engineering')),
          DropdownMenuItem(value: 'Medical', child: Text('Medical')),
          DropdownMenuItem(value: 'Sharia', child: Text('Sharia')),
        ],
        validator: (v) => v == null ? 'مطلوب' : null,
        onChanged: (v) {
          setState(() => _college = v);
          _fetchSupers(v);
        },
      ),
    );
  }

  Widget _ddSupervisor() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: DropdownButtonFormField<int>(
        value: _supervisorId,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: 'المشرف',
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
        items: _supers.map<DropdownMenuItem<int>>((s) {
          final id = s['id'] as int;
          final name = s['name']?.toString() ?? '';
          return DropdownMenuItem<int>(
            value: id,
            child: Text(name, style: GoogleFonts.cairo()),
          );
        }).toList(),
        validator: (v) => v == null ? 'مطلوب' : null,
        onChanged: (v) => setState(() => _supervisorId = v),
      ),
    );
  }

  Widget _radioType() {
    return ValueListenableBuilder<String>(
      valueListenable: _studentType,
      builder: (_, v, __) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                Radio<String>(
                  value: 'regular',
                  groupValue: v,
                  onChanged: (s) => _studentType.value = s!,
                ),
                Text('عادي', style: GoogleFonts.cairo()),
              ],
            ),
            const SizedBox(width: 24),
            Row(
              children: [
                Radio<String>(
                  value: 'intensive',
                  groupValue: v,
                  onChanged: (s) => _studentType.value = s!,
                ),
                Text('تثبيت', style: GoogleFonts.cairo()),
              ],
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
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
          child: Column(
            children: [
              // ─── HEADER ───
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
                          'تعديل بيانات الطالب',
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

              // ─── FORM ───
              Expanded(
                child: Container(
                  color: _bgLight,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 24,
                  ),
                  child: AnimationLimiter(
                    child: Form(
                      key: _formKey,
                      child: ListView(
                        physics: const BouncingScrollPhysics(),
                        children: AnimationConfiguration.toStaggeredList(
                          duration: const Duration(milliseconds: 600),
                          childAnimationBuilder: (w) => SlideAnimation(
                            verticalOffset: 50,
                            child: FadeInAnimation(child: w),
                          ),
                          children: [
                            _radioType(),
                            _field('الاسم الكامل', _name),
                            _field(
                              'الهاتف',
                              _phone,
                              kb: TextInputType.phone,
                              req: false,
                            ),
                            _field(
                              'البريد الإلكتروني',
                              _email,
                              kb: TextInputType.emailAddress,
                              req: false,
                            ),
                            _dropdownCollege(),
                            _ddSupervisor(),
                            const SizedBox(height: 24),
                            SizedBox(
                              height: 48,
                              child: ElevatedButton(
                                onPressed: _busy ? null : _save,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _greenStart,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: _busy
                                    ? const CircularProgressIndicator(
                                        color: Colors.white,
                                      )
                                    : Text(
                                        'حفظ التعديلات',
                                        style: GoogleFonts.cairo(
                                          color: Colors.white,
                                        ),
                                      ),
                              ),
                            ),
                          ],
                        ),
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

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    _studentType.dispose();
    super.dispose();
  }
}
