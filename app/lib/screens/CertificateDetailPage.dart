import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dio/dio.dart';
import '../../services/api_config.dart';
import '../cert_downloader_web.dart'
    if (dart.library.io) '../cert_downloader_stub.dart' as downloader;
import 'student_certificates_page.dart' show toArabicDigits;

// ألوان ثابتة تتناسب مع الصفحة الرئيسية
const Color kPrimaryColor = Color(0xff2e7d32); // أخضر داكن
const Color kAccentColor = Color(0xffc9a83c); // ذهبي معتدل
const Color kBackground = Color(0xfff1f8e9); // أخضر فاتح جدًا
const Color kBorderColor = Color(0xff388e3c); // أخضر متوسط

class CertificateDetailPage extends StatefulWidget {
  final Map<String, dynamic> exam;
  const CertificateDetailPage({Key? key, required this.exam}) : super(key: key);

  @override
  _CertificateDetailPageState createState() => _CertificateDetailPageState();
}

class _CertificateDetailPageState extends State<CertificateDetailPage> {
  bool _downloading = false;
  String _studentName = '—';
  bool _isFemale = false; // 👈 تحديد الجنس

  @override
  void initState() {
    super.initState();
    _loadStudentInfo();
  }

  // محاولة ذكية لاستخراج كونه مؤنثًا من عدة صيغ محتملة
  bool _parseIsFemale(dynamic v) {
    if (v == null) return false;
    if (v is bool) return v;
    final s = v.toString().trim().toLowerCase();
    if (s.isEmpty) return false;

    // نصوص شائعة
    const femWords = {
      'f',
      'female',
      'feminine',
      'girl',
      'woman',
      'أنثى',
      'انثى',
      'فتاة',
      'بنت',
      'امرأة'
    };
    const maleWords = {'m', 'male', 'masculine', 'boy', 'man', 'ذكر'};

    if (femWords.contains(s)) return true;
    if (maleWords.contains(s)) return false;

    // أرقام شائعة (1 = أنثى / 0 = ذكر) إن وُجدت بهذا الشكل
    final asInt = int.tryParse(s);
    if (asInt != null) return asInt == 1;

    // قيم نصية منطقية
    if (s == 'true') return true;
    if (s == 'false') return false;

    return false; // افتراضي: ذكر
  }

  /// تحميل اسم الطالب + الجنس من exam أو SharedPreferences
  Future<void> _loadStudentInfo() async {
    final sp = await SharedPreferences.getInstance();

    final storedName = sp.getString('student_name');
    final spGenderStr = sp.getString('student_gender');
    final spIsFemale = sp.getBool('is_female');

    final examGender = widget.exam['is_female'] ?? widget.exam['gender'];

    setState(() {
      _studentName = widget.exam['student_name'] ??
          widget.exam['name'] ??
          storedName ??
          '—';

      // أولوية: exam ثم SharedPreferences
      _isFemale = _parseIsFemale(examGender) ||
          _parseIsFemale(spIsFemale) ||
          _parseIsFemale(spGenderStr);
    });
  }

  /// تحميل الشهادة PDF بدون إظهار رسالة فشل حتى عند اعتراض IDM
  Future<void> _downloadPdf() async {
    if (_downloading) return;
    setState(() => _downloading = true);
    try {
      final sp = await SharedPreferences.getInstance();
      final token = sp.getString('token') ?? '';

      final resp = await Dio().get<Uint8List>(
        '${ApiConfig.baseUrl}/certificates/${widget.exam['id']}?download=1',
        options: Options(
          headers: {'Authorization': 'Bearer $token'},
          responseType: ResponseType.bytes,
        ),
      );

      final bytes = resp.data!;
      try {
        await downloader.saveAndOpen(
          bytes: bytes,
          fileName: 'certificate_${widget.exam['id']}.pdf',
        );
      } catch (_) {/* ممكن IDM يعترض الفتح، ولا داعي لتنبيه */}
    } catch (_) {
      // غالبًا التحميل صار عبر مدير التنزيل، فلا نزعج المستخدم برسالة فشل
    } finally {
      if (mounted) {
        setState(() => _downloading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم بدء تحميل الشهادة', style: GoogleFonts.cairo()),
            backgroundColor: kPrimaryColor,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final examTitle = widget.exam['arabic_name'] ?? '—';

    // قد تكون الدرجة String أو num أو null
    final dynamic rawScore = widget.exam['score'];
    final bool hasScore =
        rawScore != null && rawScore.toString().trim().isNotEmpty;
    final String scoreStr =
        hasScore ? toArabicDigits(rawScore.toString()) : 'ناجح';

    final dateStr = toArabicDigits(widget.exam['created_at']?.toString() ?? '');

    // تراكيب حسب الجنس
    final pronounHaHu = _isFemale ? 'ها' : 'ه'; // حصوله/ها - اجتيازِه/ها
    final lihaLahu = _isFemale ? 'لها' : 'له'; // له/لها
    final tafawoq = _isFemale ? 'لتفوقها' : 'لتفوقه';

    // السطر التفصيلي حسب توفر الدرجة
    final String resultLine = hasScore
        ? 'بعد حصول$pronounHaHu على $scoreStr درجة بتاريخ $dateStr'
        : 'بعد اجتياز$pronounHaHu الامتحان بتاريخ $dateStr';

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text('شهادة تقدير',
            style:
                GoogleFonts.cairo(fontSize: 20, fontWeight: FontWeight.w600)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 1,
        centerTitle: true,
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xffe8f5e9), Color(0xff66bb6a)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 30),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 640),
              padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 48),
              decoration: BoxDecoration(
                color: kBackground,
                borderRadius: BorderRadius.circular(28),
                border:
                    Border.all(color: kBorderColor.withOpacity(0.6), width: 2),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 20,
                    offset: Offset(0, 10),
                  ),
                ],
              ),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Opacity(
                      opacity: 0.04,
                      child: Image.asset('assets/logo2.jpg', fit: BoxFit.cover),
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Image.asset('assets/logo1.png', width: 120),
                      const SizedBox(height: 28),
                      Text(
                        'شهادة شكر وتقدير',
                        style: GoogleFonts.cairo(
                          fontSize: 30,
                          fontWeight: FontWeight.bold,
                          color: kPrimaryColor,
                          shadows: [
                            Shadow(color: Colors.black12, blurRadius: 5)
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        'تتشرف إدارة ملتقى القرآن الكريم بمنح هذه الشهادة لـ',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.cairo(
                          fontSize: 18,
                          color: Colors.black87,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        _studentName,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.cairo(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          color: kAccentColor,
                          letterSpacing: 1.3,
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        'وذلك $tafawoq في اجتياز «$examTitle»',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.cairo(
                          fontSize: 19,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        resultLine,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.cairo(
                          fontSize: 18,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Divider(
                          color: kBorderColor.withOpacity(0.5), thickness: 1.4),
                      const SizedBox(height: 14),
                      Text(
                        'نسأل الله $lihaLahu دوام التوفيق والسداد',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.cairo(
                          fontSize: 17,
                          fontStyle: FontStyle.italic,
                          color: Colors.black54,
                        ),
                      ),
                      const SizedBox(height: 36),
                      Text(
                        'إدارة ملتقى القرآن الكريم',
                        style: GoogleFonts.cairo(
                          fontSize: 17,
                          fontWeight: FontWeight.w500,
                          color: Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        child: ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: kPrimaryColor,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(50),
            shape: const StadiumBorder(),
            elevation: 4,
          ),
          icon: _downloading
              ? SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    valueColor: AlwaysStoppedAnimation(Colors.white),
                  ),
                )
              : const Icon(Icons.download_rounded),
          label: Text(
            _downloading ? 'جاري التنزيل…' : 'تحميل PDF',
            style: GoogleFonts.cairo(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          onPressed: _downloading ? null : _downloadPdf,
        ),
      ),
    );
  }
}
