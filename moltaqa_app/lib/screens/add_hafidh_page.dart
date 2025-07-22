import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/api_config.dart';

class Student {
  final int id;
  final String regNumber;
  final String name;

  Student({required this.id, required this.regNumber, required this.name});

  @override
  String toString() => '$regNumber - $name';
}

class AddHafidhPage extends StatefulWidget {
  const AddHafidhPage({super.key});

  @override
  State<AddHafidhPage> createState() => _AddHafidhState();
}

class _AddHafidhState extends State<AddHafidhPage> {
  static const _greenStart = Color(0xff27ae60);
  static const _greenEnd = Color(0xff219150);
  static const _bgLight = Color(0xfff0faf2);

  final _formKey = GlobalKey<FormState>();
  DateTime? _date;

  // قائمة الطلاب المحمّلة من السيرفر
  List<Student> _students = [];
  // الطالب المختار بواسطة الـ Autocomplete
  Student? _selectedStudent;
  // كنترولر للحقل النصّي
  late TextEditingController _searchCtrl;

  Future<String> _token() async =>
      (await SharedPreferences.getInstance()).getString('token') ?? '';

  @override
  void initState() {
    super.initState();
    _searchCtrl = TextEditingController();
    _loadStudents();
  }

  Future<void> _loadStudents() async {
    final token = await _token();
    final res = await Dio().get(
      '${ApiConfig.baseUrl}/students',
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
    if (!mounted) return;
    setState(() {
      _students = (res.data as List).map((e) {
        return Student(
          id: e['id'],
          regNumber: e['reg_number'] ?? '',
          name: e['name'] ?? '',
        );
      }).toList();
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    try {
      await Dio().post(
        '${ApiConfig.baseUrl}/hafadh',
        data: {
          'student_id': _selectedStudent!.id,
          if (_date != null) 'hafidh_date': _date!.toIso8601String(),
        },
        options: Options(
          headers: {'Authorization': 'Bearer ${await _token()}'},
        ),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تمت إضافة الحافظ 👌', style: GoogleFonts.cairo()),
        ),
      );
      Navigator.pop(context, true);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطأ: $e', style: GoogleFonts.cairo())),
      );
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
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
              // HEADER
              Container(
                width: double.infinity,
                padding: const EdgeInsets.only(top: 16, bottom: 24),
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
                        const SizedBox(height: 8),
                        Text(
                          'إضافة حافظ',
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

              // FORM
              Expanded(
                child: Container(
                  color: _bgLight,
                  padding: const EdgeInsets.all(16),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // هنا استبدلنا TextFormField بـ Autocomplete
                        Autocomplete<Student>(
                          optionsBuilder: (TextEditingValue textEditingValue) {
                            if (textEditingValue.text.isEmpty ||
                                _students.isEmpty) {
                              return const Iterable<Student>.empty();
                            }
                            return _students.where((stu) {
                              final q = textEditingValue.text.toLowerCase();
                              return stu.regNumber.toLowerCase().contains(q) ||
                                  stu.name.toLowerCase().contains(q);
                            });
                          },
                          displayStringForOption: (Student option) =>
                              '${option.regNumber} - ${option.name}',
                          fieldViewBuilder:
                              (
                                context,
                                controller,
                                focusNode,
                                onFieldSubmitted,
                              ) {
                                return TextFormField(
                                  controller: controller,
                                  focusNode: focusNode,
                                  style: GoogleFonts.cairo(),
                                  decoration: InputDecoration(
                                    labelText: 'رقم الطالب أو الاسم',
                                    filled: true,
                                    fillColor: Colors.white,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide.none,
                                    ),
                                  ),
                                  validator: (v) => _selectedStudent == null
                                      ? 'اختر طالبًا من القائمة'
                                      : null,
                                );
                              },
                          onSelected: (Student selection) {
                            _selectedStudent = selection;
                          },
                        ),

                        const SizedBox(height: 16),
                        InkWell(
                          onTap: () async {
                            final now = DateTime.now();
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: _date ?? now,
                              firstDate: DateTime(now.year - 10),
                              lastDate: now,
                            );
                            if (picked != null) setState(() => _date = picked);
                          },
                          child: InputDecorator(
                            decoration: InputDecoration(
                              labelText: 'تاريخ الختمة',
                              filled: true,
                              fillColor: Colors.white,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  _date == null
                                      ? 'اختر التاريخ'
                                      : DateFormat('yyyy-MM-dd').format(_date!),
                                  style: GoogleFonts.cairo(),
                                ),
                                const Icon(
                                  Icons.calendar_today,
                                  color: Color(0xff27ae60),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const Spacer(),
                        SizedBox(
                          height: 48,
                          child: ElevatedButton.icon(
                            onPressed: _save,
                            icon: const Icon(Icons.save),
                            label: Text('حفظ', style: GoogleFonts.cairo()),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _greenStart,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                      ],
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
