import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dio/dio.dart';
import '../../services/api_config.dart';
import 'CertificateDetailPage.dart';

/// تحويل الأرقام الغربية إلى عربية
String toArabicDigits(String s) {
  return s.replaceAllMapped(RegExp(r'\d'), (m) {
    return String.fromCharCode(0x0660 + int.parse(m[0]!));
  });
}

/// تنسيق الدرجة إلى نص (أو null)
String? _formatScore(dynamic raw) {
  if (raw == null) return null;
  if (raw is num) {
    final n = raw.toDouble();
    return n % 1 == 0 ? n.toStringAsFixed(0) : n.toStringAsFixed(2);
  }
  final n = num.tryParse('$raw');
  if (n == null) return null;
  return n % 1 == 0 ? n.toStringAsFixed(0) : n.toStringAsFixed(2);
}

/// إظهار الدرجة للواجهة: إن لم تتوفر → "ناجح"
String displayScoreForUi(String? score) {
  if (score == null || score.trim().isEmpty) return 'ناجح';
  return toArabicDigits(score);
}

class CertificatesPage extends StatefulWidget {
  const CertificatesPage({Key? key}) : super(key: key);

  @override
  _CertificatesPageState createState() => _CertificatesPageState();
}

class _CertificatesPageState extends State<CertificatesPage> {
  bool _loading = true;
  List<Map<String, dynamic>> _certs = [];

  Future<String> _getToken() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getString('token') ?? '';
  }

  /// جلب الشهادات الرسمية التي اجتازها الطالب
  Future<void> _loadCerts() async {
    setState(() => _loading = true);

    try {
      final token = await _getToken();
      final resp = await Dio().get(
        '${ApiConfig.baseUrl}/exams/me?official=1&passed=1',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );

      final sp = await SharedPreferences.getInstance();
      final storedName = sp.getString('student_name');

      final list = (resp.data as List?) ?? const [];

      // استبعاد امتحانات الأجزاء
      final filtered = list.where((e) {
        final code = e['exam_code']?.toString();
        return code == null || !code.startsWith('J');
      });

      // توحيد الحقول مع ضمان أن القيم النصّية ليست أرقامًا Null
      _certs = filtered.map<Map<String, dynamic>>((e) {
        return {
          'id': e['id'],
          'arabic_name': e['arabic_name'],
          'score': _formatScore(e['score']), // **نخزّنها كنص**
          'created_at': e['created_at']?.toString() ?? '',
          'student_name': e['student_name'] ?? e['name'] ?? storedName,
          'exam_code': e['exam_code'],
          'passed': e['passed'] ?? true, // معلومات مفيدة لو لزم
        };
      }).toList(growable: false);
    } catch (err) {
      // في حال حدوث خطأ API، لا نكسر الـ UI
      _certs = const [];
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _loadCerts();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xfff3f4f8),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(child: _loading ? _buildSpinner() : _buildGrid()),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() => Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xff8e44ad), Color(0xff3498db)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8)],
        ),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
              onPressed: () => Navigator.of(context).pop(),
            ),
            const Spacer(),
            Text(
              'شهاداتي',
              style: GoogleFonts.cairo(
                textStyle: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const Spacer(),
            const SizedBox(width: 24),
          ],
        ),
      );

  Widget _buildSpinner() => const Center(child: CircularProgressIndicator());

  Widget _buildGrid() {
    return AnimationLimiter(
      child: LayoutBuilder(builder: (_, constraints) {
        final cross = constraints.maxWidth < 600 ? 2 : 4;
        return GridView.builder(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cross,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 0.7,
          ),
          itemCount: _certs.length,
          itemBuilder: (ctx, i) => AnimationConfiguration.staggeredGrid(
            position: i,
            duration: const Duration(milliseconds: 800),
            columnCount: cross,
            child: ScaleAnimation(
              child: FadeInAnimation(
                child: _CertCard(exam: _certs[i]),
              ),
            ),
          ),
        );
      }),
    );
  }
}

class _CertCard extends StatelessWidget {
  final Map<String, dynamic> exam;
  const _CertCard({Key? key, required this.exam}) : super(key: key);

  void _openDetail(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CertificateDetailPage(exam: exam),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scoreStr = exam['score'] as String?;
    final dateStr = toArabicDigits(exam['created_at']?.toString() ?? '-');

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => _openDetail(context),
      child: Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 4,
        shadowColor: Colors.black26,
        child: Column(
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xffFFFEFC),
                  borderRadius: BorderRadius.circular(12),
                  border:
                      Border.all(color: const Color(0xffD4AF37), width: 1.5),
                ),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Opacity(
                        opacity: 0.08,
                        child:
                            Image.asset('assets/logo2.jpg', fit: BoxFit.cover),
                      ),
                    ),
                    Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.picture_as_pdf,
                              size: 32, color: Color(0xff16794F)),
                          const SizedBox(height: 8),
                          Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 8.0),
                            child: Text(
                              exam['arabic_name'] ?? '',
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.cairo(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: const Color(0xff0C3C60),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    exam['arabic_name'] ?? '–',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.cairo(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: const Color(0xff333333),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'تاريخ: $dateStr',
                    style:
                        GoogleFonts.cairo(fontSize: 12, color: Colors.black54),
                  ),
                  Text(
                    'درجة: ${displayScoreForUi(scoreStr)}',
                    style:
                        GoogleFonts.cairo(fontSize: 12, color: Colors.black54),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
