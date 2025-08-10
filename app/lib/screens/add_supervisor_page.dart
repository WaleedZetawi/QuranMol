import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';

import '../../services/dio_client.dart';
import '../../services/auth_service.dart';

class AddSupervisorPage extends StatefulWidget {
  const AddSupervisorPage({super.key});
  @override
  State<AddSupervisorPage> createState() => _AddSupervisorPageState();
}

class _AddSupervisorPageState extends State<AddSupervisorPage> {
  static const _greenStart = Color(0xff27ae60);
  static const _greenEnd = Color(0xff219150);
  static const _bgLight = Color(0xfff0faf2);

  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();

  String? _college;
  String? _adminGender; // male / female
  bool _isRegular = true;
  bool _isTrial = false;
  bool _isDoctor = false;
  bool _isExaminer = false;
  bool _busy = false;
  bool _ready = false;

  final _maleCols = const ['Engineering', 'Medical', 'Sharia'];
  final _femaleCols = const ['NewCampus', 'OldCampus', 'Agriculture'];

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final g = await AuthService.genderForAdmin(); // يقرأه من التوكن
    setState(() {
      _adminGender = g;
      _college = (g == 'female' ? _femaleCols.first : _maleCols.first);
      _ready = true;
    });
  }

  String _genderFromCollege(String? c) {
    if (c == null) return 'male';
    return _femaleCols.contains(c) ? 'female' : 'male';
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final dio = DioClient().dio;
      await dio.post('/supervisors', data: {
        'name': _name.text.trim(),
        'email': _email.text.trim().isEmpty ? null : _email.text.trim(),
        'phone': _phone.text.trim().isEmpty ? null : _phone.text.trim(),
        'college': _college,
        'is_regular': _isRegular,
        'is_trial': _isTrial,
        'is_doctor': _isDoctor,
        'is_examiner': _isExaminer,
        // مهم: السيرفر يدوّر gender، فنبعته صريح حسب الكلية/اللوحة
        'gender': _genderFromCollege(_college),
      });
      if (!mounted) return;
      Navigator.pop(context, true);
    } on DioException catch (e) {
      final m = e.response?.data is Map
          ? (e.response?.data['message'] ?? 'فشل الحفظ')
          : 'فشل الحفظ';
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _field(
    String lbl,
    TextEditingController ctrl, {
    TextInputType? kb,
    bool req = true,
  }) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: TextFormField(
          controller: ctrl,
          keyboardType: kb,
          validator: (v) =>
              !req || (v != null && v.trim().isNotEmpty) ? null : 'مطلوب',
          decoration: InputDecoration(
            labelText: lbl, // ← كانت ثابتة، صارت ديناميكية
            border: const OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(12)),
            ),
            filled: true,
            fillColor: Colors.white,
          ),
        ),
      );

  Widget _ddCollege() {
    final items = (_adminGender == 'female' ? _femaleCols : _maleCols)
        .map((c) => DropdownMenuItem(value: c, child: Text(c)))
        .toList();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: DropdownButtonFormField<String>(
        value: _college,
        decoration: const InputDecoration(
          labelText: 'المجمّع',
          border: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
          ),
          filled: true,
          fillColor: Colors.white,
        ),
        items: items,
        validator: (v) => v == null ? 'مطلوب' : null,
        onChanged: (v) => setState(() => _college = v),
      ),
    );
  }

  Widget _switchTile(String lbl, bool val, ValueChanged<bool> on) =>
      SwitchListTile(
        title: Text(lbl),
        value: val,
        onChanged: on,
        activeColor: _greenStart,
      );

  @override
  Widget build(BuildContext ctx) {
    if (!_ready) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
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
                  borderRadius: BorderRadius.vertical(
                    bottom: Radius.circular(24),
                  ),
                ),
                child: Directionality(
                  textDirection: TextDirection.rtl,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      PositionedDirectional(
                        start: 8,
                        child: IconButton(
                          icon:
                              const Icon(Icons.arrow_back, color: Colors.white),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ),
                      const Text(
                        'إضافة مشرف',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),
              // FORM
              Expanded(
                child: Container(
                  color: _bgLight,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Form(
                    key: _form,
                    child: AnimationLimiter(
                      child: ListView(
                        physics: const BouncingScrollPhysics(),
                        children: AnimationConfiguration.toStaggeredList(
                          duration: const Duration(milliseconds: 600),
                          childAnimationBuilder: (w) => SlideAnimation(
                              verticalOffset: 50,
                              child: FadeInAnimation(child: w)),
                          children: [
                            _field('اسم المشرف', _name),
                            _field('البريد الإلكتروني', _email,
                                kb: TextInputType.emailAddress, req: false),
                            _field('الهاتف', _phone,
                                kb: TextInputType.phone, req: false),
                            _ddCollege(),
                            const Divider(height: 32),
                            _switchTile('متابعة أسبوعية فقط', _isRegular,
                                (v) => setState(() => _isRegular = v)),
                            _switchTile('مختص للتجريبي', _isTrial,
                                (v) => setState(() => _isTrial = v)),
                            _switchTile('دكتور (رسمي)', _isDoctor,
                                (v) => setState(() => _isDoctor = v)),
                            _switchTile('ممتحن أجزاء', _isExaminer,
                                (v) => setState(() => _isExaminer = v)),
                            const SizedBox(height: 28),
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
                                        color: Colors.white)
                                    : const Text('حفظ',
                                        style: TextStyle(color: Colors.white)),
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
}
