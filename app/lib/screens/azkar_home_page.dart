// lib/pages/azkar_home_page.dart

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:confetti/confetti.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

import '../services/auth_service.dart';

class AzkarHomePage extends StatelessWidget {
  const AzkarHomePage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          title: const Text('الأذكار',
              style: TextStyle(fontWeight: FontWeight.bold)),
          backgroundColor: const Color(0xFF43A047),
          centerTitle: true,
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Image.asset('assets/logo1.png', height: 120),
                const SizedBox(height: 50),
                CustomAzkarButton(
                  title: 'أذكار الصباح',
                  gradient: const LinearGradient(
                      colors: [Color(0xFF66BB6A), Color(0xFF43A047)]),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const AzkariPage(azkarType: 'morning')),
                  ),
                ),
                const SizedBox(height: 20),
                CustomAzkarButton(
                  title: 'أذكار المساء',
                  gradient: const LinearGradient(
                      colors: [Color(0xFF81C784), Color(0xFF388E3C)]),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const AzkariPage(azkarType: 'evening')),
                  ),
                ),
                const SizedBox(height: 20),
                CustomAzkarButton(
                  title: 'أدعية من القرآن',
                  gradient: const LinearGradient(
                      colors: [Color(0xFF4CAF50), Color(0xFF2E7D32)]),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const AzkariPage(azkarType: 'quran')),
                  ),
                ),
                const SizedBox(height: 20),
                CustomAzkarButton(
                  title: 'أدعية مأثورة',
                  gradient: const LinearGradient(
                      colors: [Color(0xFF66BB6A), Color(0xFF1B5E20)]),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const AzkariPage(azkarType: 'prophet')),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

class CustomAzkarButton extends StatelessWidget {
  final String title;
  final VoidCallback onPressed;
  final LinearGradient gradient;

  const CustomAzkarButton({
    super.key,
    required this.title,
    required this.onPressed,
    required this.gradient,
  });

  @override
  Widget build(BuildContext context) => AnimationConfiguration.staggeredList(
        position: 0,
        duration: const Duration(milliseconds: 500),
        child: SlideAnimation(
          verticalOffset: 50,
          child: FadeInAnimation(
            child: Container(
              width: double.infinity,
              height: 60,
              decoration: BoxDecoration(
                  gradient: gradient, borderRadius: BorderRadius.circular(12)),
              child: ElevatedButton(
                onPressed: onPressed,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  padding: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(title,
                    style: const TextStyle(
                        fontSize: 22,
                        color: Colors.white,
                        fontWeight: FontWeight.bold)),
              ),
            ),
          ),
        ),
      );
}

class AzkariPage extends StatefulWidget {
  final String azkarType;
  const AzkariPage({super.key, required this.azkarType});

  @override
  State<AzkariPage> createState() => _AzkariPageState();
}

class _AzkariPageState extends State<AzkariPage> {
  late final List<Map<String, dynamic>> azkar;
  late List<int> _counts;
  late ConfettiController _confettiController;
  late final String _prefsKey;
  final GlobalKey _shareKey = GlobalKey();
  String _shareTextForImage = '';

  @override
  void initState() {
    super.initState();
    // هنا تضع قوائمك morningAzkar, eveningAzkar, quranPrayers, prophetPrayers
    switch (widget.azkarType) {
      case 'morning':
        azkar = morningAzkar;
        break;
      case 'evening':
        azkar = eveningAzkar;
        break;
      case 'quran':
        azkar = quranPrayers;
        break;
      default:
        azkar = prophetPrayers;
    }
    _counts = List<int>.filled(azkar.length, 0);
    _confettiController =
        ConfettiController(duration: const Duration(seconds: 2));
    final userId = AuthService.currentUserId.toString();
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    _prefsKey = 'azkar_${widget.azkarType}_$userId\_$today';
    _loadProgress();
  }

  @override
  void dispose() {
    _confettiController.dispose();
    super.dispose();
  }

  Future<void> _loadProgress() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList('$_prefsKey\_counts');
    if (saved != null && saved.length == azkar.length) {
      final resume = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('استئناف الأذكار'),
          content: const Text('لديك أذكار غير مكتملة اليوم، استئناف؟'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('إعادة')),
            TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('استئناف')),
          ],
        ),
      );
      if (resume == true) {
        setState(() => _counts = saved.map(int.parse).toList());
      } else {
        prefs.remove('$_prefsKey\_counts');
      }
    }
  }

  Future<void> _saveProgress() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
        '$_prefsKey\_counts', _counts.map((c) => c.toString()).toList());
  }

  void _increment(int idx) {
    final max = azkar[idx]['count'] as int;
    if (_counts[idx] < max) {
      setState(() => _counts[idx]++);
      _saveProgress();
      if (_counts
          .every((c) => c >= (azkar[_counts.indexOf(c)]['count'] as int))) {
        _confettiController.play();
        Future.delayed(const Duration(milliseconds: 300), () {
          showDialog<void>(
            context: context,
            barrierDismissible: true,
            builder: (_) => Stack(
              alignment: Alignment.topCenter,
              children: [
                ConfettiWidget(
                  confettiController: _confettiController,
                  blastDirectionality: BlastDirectionality.explosive,
                  shouldLoop: false,
                  colors: const [
                    Colors.green,
                    Colors.blue,
                    Colors.orange,
                    Colors.pink
                  ],
                ),
                AlertDialog(
                  title: const Text('ما شاء الله!'),
                  content: const Text('لقد انتهيت من الأذكار بالكامل'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('حسناً')),
                  ],
                ),
              ],
            ),
          );
        });
      }
    }
  }

  Future<void> _showShareOptions(int idx) async {
    final choice = await showDialog<String>(
      context: context,
      builder: (_) => SimpleDialog(
        title: const Text('كيف تريد المشاركة؟'),
        children: [
          SimpleDialogOption(
              child: const Text('نص'),
              onPressed: () => Navigator.pop(context, 'text')),
          SimpleDialogOption(
              child: const Text('صورة'),
              onPressed: () => Navigator.pop(context, 'image')),
        ],
      ),
    );
    if (choice == 'text') {
      Share.share(azkar[idx]['text'] as String);
    } else if (choice == 'image') {
      setState(() => _shareTextForImage = azkar[idx]['text'] as String);
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await Future.delayed(const Duration(milliseconds: 100));
        await WidgetsBinding.instance.endOfFrame;
        _captureAndShareImage();
      });
    }
  }

  Future<void> _captureAndShareImage() async {
    try {
      final boundary =
          _shareKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final pngBytes = byteData!.buffer.asUint8List();

      // نكتب الصورة في ملف مؤقت
      final tempDir = await getTemporaryDirectory();
      final file =
          await File('${tempDir.path}/azkar.png').writeAsBytes(pngBytes);
      final xfile = XFile(file.path, mimeType: 'image/png');

      // نشارك عبر share_plus على كل المنصّات
      await Share.shareXFiles([xfile], text: _shareTextForImage);
    } catch (e) {
      debugPrint('Share image error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = azkar.fold<int>(0, (s, e) => s + (e['count'] as int));
    final done = _counts.fold<int>(0, (s, c) => s + c);

    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1B5E20),
        title: Text(
          widget.azkarType == 'morning'
              ? 'أذكار الصباح'
              : widget.azkarType == 'evening'
                  ? 'أذكار المساء'
                  : widget.azkarType == 'quran'
                      ? 'أدعية من القرآن'
                      : 'أدعية مأثورة',
          style: const TextStyle(
              fontWeight: FontWeight.bold, fontSize: 26, color: Colors.white),
        ),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          Column(
            children: [
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: LinearProgressIndicator(
                  value: total > 0 ? done / total : 0,
                  minHeight: 8,
                  backgroundColor: Colors.green.shade100,
                  valueColor: AlwaysStoppedAnimation(Colors.green.shade700),
                ),
              ),
              Expanded(
                child: AnimationLimiter(
                  child: ListView.builder(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    itemCount: azkar.length,
                    itemBuilder: (context, idx) {
                      final item = azkar[idx];
                      final c = _counts[idx];
                      final max = item['count'] as int;
                      return AnimationConfiguration.staggeredList(
                        position: idx,
                        duration: const Duration(milliseconds: 400),
                        child: SlideAnimation(
                          verticalOffset: 50,
                          child: FadeInAnimation(
                            child: Card(
                              margin: const EdgeInsets.symmetric(vertical: 8),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16)),
                              elevation: 4,
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Text(
                                      item['text'] as String,
                                      style: TextStyle(
                                        fontSize:
                                            MediaQuery.of(context).size.width <
                                                    350
                                                ? 18
                                                : 20,
                                        height: 1.8,
                                        color: Colors.green.shade900,
                                      ),
                                      textAlign: TextAlign.justify,
                                    ),
                                    const SizedBox(height: 12),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: InkWell(
                                            onTap: c < max
                                                ? () => _increment(idx)
                                                : null,
                                            borderRadius:
                                                BorderRadius.circular(14),
                                            child: Container(
                                              height: 48,
                                              decoration: BoxDecoration(
                                                color: c < max
                                                    ? Colors.green.shade700
                                                    : Colors.grey.shade400,
                                                borderRadius:
                                                    BorderRadius.circular(14),
                                              ),
                                              alignment: Alignment.center,
                                              child: const Text('تم',
                                                  style: TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 18,
                                                      fontWeight:
                                                          FontWeight.bold)),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Text(
                                          '$c / $max',
                                          style: TextStyle(
                                            fontSize: 18,
                                            color: c == max
                                                ? Colors.green.shade700
                                                : Colors.red.shade400,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        IconButton(
                                          onPressed: () =>
                                              _showShareOptions(idx),
                                          icon: Icon(Icons.share,
                                              color: Colors.green.shade700),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),

          // Invisible RepaintBoundary for capture
          Opacity(
            opacity: 0.0,
            child: RepaintBoundary(
              key: _shareKey,
              child: Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      colors: [Color(0xFF66BB6A), Color(0xFF43A047)]),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.asset('assets/logo1.png', height: 60),
                    const SizedBox(height: 12),
                    Text(
                      _shareTextForImage,
                      style: const TextStyle(
                          fontSize: 20, height: 1.6, color: Colors.white),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // البيانات
  final List<Map<String, dynamic>> morningAzkar = [
    {
      'text': '''

آية الكرسي:

اللّهُ لاَ إِلَهَ إِلَّا هُوَ الْحَيُّ الْقَيُّومُ ۚ لَا تَأْخُذُهُ سِنَةٌ وَلَا نَوْمٌ ۚ لَهُ مَا فِي السَّمَاوَاتِ وَمَا فِي الْأَرْضِ ۗ  مَن ذَا الَّذِي يَشْفَعُ عِندَهُ إِلَّا بِإِذْنِهِ ۚ يَعْلَمُ مَا بَيْنَ أَيْدِيهِمْ وَمَا خَلْفَهُمْ ۖ وَلَا يُحِيطُونَ بِشَيْءٍ مِنْ عِلْمِهِ إِلَّا بِمَا شَاءَ ۚ وَسِعَ كُرْسِيُّهُ السَّمَاوَاتِ وَالْأَرْضَ وَلَا يَئُودُهُ حِفْظُهُمَا ۚ وَهُوَ الْعَلِيُّ الْعَظِيمُ
(البقرة 255)

من قالها حين يصبح أجير من الجن حتى يمسى، ومن قالها حين يمسى أجير من الجن حتى يصبح.''',
      'count': 1,
    },
    {
      'text': '''سورة الإخلاص:
﴿قُلْ هُوَ ٱللَّهُ أَحَدٌ﴾۝١  
﴿ٱللَّهُ ٱلصَّمَدُ﴾۝٢  
﴿لَمْ يَلِدْ وَلَمْ يُولَدْ﴾۝٣  
﴿وَلَمْ يَكُن لَّهُۥ كُفُوٗا أَحَدٌ﴾۝٤


من قالها ثلاث مرات كفت من كل شيء.''',
      'count': 3,
    },
    {
      'text': '''سورة الفلق:
﴿قُلْ أَعُوذُ بِرَبِّ ٱلْفَلَقِ﴾۝١  
﴿مِن شَرِّ مَا خَلَقَ﴾۝٢  
﴿وَمِن شَرِّ غَاسِقٍ إِذَا وَقَبَ﴾۝٣  
﴿وَمِن شَرِّ ٱلنَّفَّـٰثَـٰتِ فِى ٱلْعُقَدِ﴾۝٤  
﴿وَمِن شَرِّ حَاسِدٍ إِذَا حَسَدَ﴾۝

من قالها حين يصبح وحين يمسى كفت من كل شيء.''',
      'count': 3,
    },
    {
      'text': '''سورة الناس:
﴿قُلْ أَعُوذُ بِرَبِّ ٱلنَّاسِ﴾۝١  
﴿مَلِكِ ٱلنَّاسِ﴾۝٢  
﴿إِلَـٰهِ ٱلنَّاسِ﴾۝٣  
﴿مِن شَرِّ ٱلْوَسْوَاسِ ٱلْخَنَّاسِ﴾۝٤  
﴿ٱلَّذِى يُوَسْوِسُ فِى صُدُورِ ٱلنَّاسِ﴾۝٥  
﴿مِنَ ٱلْجِنَّةِ وَٱلنَّاسِ﴾۝٦
من قالها حين يصبح وحين يمسى كفت من كل شيء.''',
      'count': 3,
    },
    {
      'text': '''دعاء سيد الاستغفار:
اللَّهُمَّ أَنْتَ رَبِّي لا إِلَهَ إِلَّا أَنْتَ، خَلَقْتَنِي وَأَنَا عَبْدُكَ، وَأَنَا عَلَى عَهْدِكَ وَوَعْدِكَ مَا اسْتَطَعْتُ، أَعُوذُ بِكَ مِنْ شَرِّ مَا صَنَعْتُ، أَبُوءُ لَكَ بِنِعْمَتِكَ عَلَيَّ، وَأَبُوءُ بِذَنْبِي فَاغْفِرْ لِي،  فَإِنَّهُ لا يَغْفِرُ الذُّنُوبَ إِلَّا أَنْتَ.


من قاله موقنًا به حين يمسى ومات من ليلته دخل الجنة، وكذلك حين يصبح.''',
      'count': 1,
    },
    {
      'text':
          '''رضيت بالله رباً، وبالإسلام ديناً، وبمحمد صلى الله عليه وسلم نبياً.

من قالها حين يصبح وحين يمسى كان حقا على الله أن يرضيه يوم القيامة.''',
      'count': 3,
    },
    {
      'text':
          '''اللَّهُمَّ إِنِّي أَصْبَحْتُ أُشْهِدُكَ وَأُشْهِدُ حَمَلَةَ عَرْشِكَ وَمَلَائِكَتَكَ وَجَمِيعَ خَلْقِكَ أَنَّكَ أَنْتَ اللَّهُ لا إِلَهَ إِلَّا أَنْتَ وَحْدَكَ لا شَرِيكَ لَكَ، وَأَنَّ مُحَمَّدًا عَبْدُكَ وَرَسُولُكَ.
من قالها أعتقه الله من النار.''',
      'count': 4,
    },
    {
      'text':
          '''اللَّهُمَّ مَا أَصْبَحَ بِي مِنْ نِعْمَةٍ أَوْ بِأَحَدٍ مِنْ خَلْقِكَ فَمِنْكَ وَحْدَكَ لَا شَرِيكَ لَكَ، فَلَكَ الْحَمْدُ وَلَكَ الشُّكْر.
من قالها حين يصبح أدى شكر يومه.''',
      'count': 1,
    },
    {
      'text': '''حسبي الله لا إله إلا هو عليه توكلت وهو رب العرش العظيم.
من قالها كفاه الله ما أهمه من أمر الدنيا والآخرة.''',
      'count': 7,
    },
    {
      'text':
          '''بسم الله الذي لا يضر مع اسمه شيء في الأرض ولا في السماء وهو السميع العليم.
لم يضره شيء من الله.''',
      'count': 3,
    },
    {
      'text':
          '''اللَّهُمَّ بِكَ أَصْبَحْنَا وَبِكَ أَمْسَيْنَا، وَبِكَ نَحْيَا وَبِكَ نَمُوتُ وَإِلَيْكَ النُّشُور.''',
      'count': 1,
    },
    {
      'text':
          '''أصبحنا على فطرة الإسلام، وعلى كلمة الإخلاص، وعلى دين نبينا محمد صلى الله عليه وسلم، وعلى ملة أبينا إبراهيم حنيفا مسلما، وما كان من المشركين.''',
      'count': 1,
    },
    {
      'text':
          '''سبحان الله وبحمده عدد خلقه، ورضا نفسه، وزنة عرشه، ومداد كلماته.''',
      'count': 3,
    },
    {
      'text':
          '''اللَّهُمَّ عافني في بدني، اللَّهُمَّ عافني في سمعي، اللَّهُمَّ عافني في بصري، لا إله إلا أنت.''',
      'count': 3,
    },
    {
      'text':
          '''اللَّهُمَّ إِنِّي أَعُوذُ بِكَ مِنَ الْكُفْرِ، وَالْفَقْرِ، وَأَعُوذُ بِكَ مِنْ عَذَابِ الْقَبْرِ، لا إله إلا أنت.''',
      'count': 3,
    },
    {
      'text':
          '''اللَّهُمَّ إِنِّي أَسْأَلُكَ العَفْوَ وَالعَافِيَةَ فِي الدُّنْيَا وَالآخِرَةِ، اللَّهُمَّ إِنِّي أَسْأَلُكَ العَفْوَ وَالعَافِيَةَ فِي ديني وَدُنْيَايَ وَأَهْلِي وَمالي، اللَّهُمَّ اسْتُرْ عَوْراتي وَآمِنْ رَوْعَاتي، اللَّهُمَّ احْفَظْنِي مِنْ بَيْنِ يَدَيَّ وَمِنْ خَلْفِي وَعَنْ يَمِينِي وَعَنْ شِمَالِي، وَمِنْ فَوْقِي، وَأَعُوذُ بِعَظَمَتِكَ أَنْ أُغْتَالَ مِنْ تَحْتِي.''',
      'count': 1,
    },
    {
      'text':
          '''يَا حَيُّ يَا قَيُّومُ بِرَحْمَتِكَ أَسْتَغِيثُ أَصْلِحْ لِي شَأْنِي كُلَّهُ وَلا تَكِلْنِي إِلَى نَفْسِي طَرْفَةَ عَيْنٍ.''',
      'count': 3,
    },
    {
      'text':
          '''أصبحنا وأصبح الملك لله رب العالمين، اللَّهُمَّ إِنِّي أَسْأَلُكَ خَيْرَ هَذَا الْيَوْمِ، فَتْحَهُ، وَنَصْرَهُ، وَنُورَهُ، وَبَرَكَتَهُ، وَهُدَاهُ، وَأَعُوذُ بِكَ مِنْ شَرِّ مَا فِيهِ وَشَرِّ مَا بَعْدَه.''',
      'count': 1,
    },
    {
      'text':
          '''اللَّهُمَّ عَلِمَ الغَيْبَ وَالشَّهَادَةَ فَاطِرَ السَّمَاوَاتِ وَالأَرْضِ رَبَّ كُلِّ شَيْءٍ وَمَلِيكَهُ، أَشْهَدُ أَنْ لا إِلَهَ إِلَّا أَنْتَ، أَعُوذُ بِكَ مِنْ شَرِّ نَفْسِي وَمِنْ شَرِّ الشَّيْطَانِ وَشِرْكِهِ، وَأَنْ أَقْتَرِفَ عَلَى نَفْسِي سُوءًا أَوْ أَجُرَّهُ إِلَى مُسْلِم.''',
      'count': 1,
    },
    {
      'text':
          '''أَعُوذُ بِكَلِمَاتِ اللَّهِ التَّامَّاتِ مِنْ شَرِّ مَا خَلَق.''',
      'count': 3,
    },
    {
      'text':
          '''اللَّهُمَّ صَلِّ وَسَلِّمْ وَبَارِكْ عَلَى نَبِيِّنَا مُحَمَّدٍ، من صلى عليه حين يصبح وحين يمسى أدرَكَته شفاعتي يوم القيامة.''',
      'count': 10,
    },
    {
      'text':
          '''اللَّهُمَّ إِنَّا نَعُوذُ بِكَ مِنْ أَنْ نُشْرِكَ بِكَ شَيْئًا نَعْلَمُهُ، وَنَسْتَغْفِرُكَ لِمَا لَا نَعْلَمُهُ.''',
      'count': 3,
    },
    {
      'text':
          '''اللَّهُمَّ إِنِّي أَعُوذُ بِكَ مِنَ الْهَمِّ وَالْحَزَنِ، وَأَعُوذُ بِكَ مِنَ الْعَجْزِ وَالْكَسَلِ، وَأَعُوذُ بِكَ مِنَ الْجُبْنِ وَالْبُخْلِ، وَأَعُوذُ بِكَ مِنْ غَلَبَةِ الدَّيْنِ وَقَهْرِ الرِّجَالِ.''',
      'count': 3,
    },
    {
      'text':
          '''أَسْتَغْفِرُ اللَّهَ الْعَظِيمَ الَّذِي لَا إِلَهَ إِلَّا هُوَ، الْحَيُّ الْقَيُّومُ، وَأَتُوبُ إِلَيْهِ.''',
      'count': 3,
    },
    {
      'text':
          '''يَا رَبِّ، لَكَ الْحَمْدُ كَمَا يَنْبَغِي لِجَلَالِ وَجْهِكَ، وَلِعَظِيمِ سُلْطَانِكَ.''',
      'count': 3,
    },
    {
      'text':
          '''اللَّهُمَّ إِنِّي أَسْأَلُكَ عِلْمًا نَافِعًا، وَرِزْقًا طَيِّبًا، وَعَمَلًا مُتَقَبَّلًا.''',
      'count': 1,
    },
    {
      'text':
          '''اللَّهُمَّ أَنْتَ رَبِّي لا إِلَهَ إِلَّا أَنْتَ، عَلَيْكَ تَوَكَّلْتُ، وَأَنْتَ رَبُّ الْعَرْشِ الْعَظِيمِ، مَا شَاءَ اللَّهُ كَانَ وَمَا لَمْ يَشَأْ لَمْ يَكُنْ، لَا حَوْلَ وَلَا قُوَّةَ إِلَّا بِاللَّهِ، أَعْلَمُ أَنَّ الْحَيَّ لَا يَمُوتُ، وَأَنَّ الْمَوْتَ لَا مَفَرَّ مِنْهُ، وَأَنَّكَ تَجْمَعُ بَيْنَ الْمَوْتِ وَالْحَيَاةِ، اللَّهُمَّ إِنِّي أَسْأَلُكَ الْجَنَّةَ، وَأَعُوذُ بِكَ مِنَ النَّارِ.''',
      'count': 1,
    },
    {
      'text':
          '''لَا إِلَهَ إِلَّا اللَّهُ وَحْدَهُ لَا شَرِيكَ لَهُ، لَهُ الْمُلْكُ وَلَهُ الْحَمْدُ، وَهُوَ عَلَى كُلِّ شَيْءٍ قَدِيرٌ.
          
كانت له عدل عشر رقاب، وكتبت له مئة حسنة، ومحيت عنه مئة سيئة، وكانت له حرزًا من الشيطان.''',
      'count': 100,
    },
    {
      'text': '''سُبْحـانَ اللهِ وَبِحَمْـدِهِ. ٌ.


حُطَّتْ خَطَايَاهُ وَإِنْ كَانَتْ مِثْلَ زَبَدِ الْبَحْرِ.
 لَمْ يَأْتِ أَحَدٌ يَوْمَ الْقِيَامَةِ بِأَفْضَلَ مِمَّا جَاءَ بِهِ 
 إِلَّا أَحَدٌ قَالَ مِثْلَ مَا قَالَ أَوْ زَادَ عَلَيْهِ.''',
      'count': 100,
    },
    {
      'text': '''أسْتَغْفِرُ اللهَ وَأتُوبُ إلَيْهِ
''',
      'count': 100,
    },
  ];

  final List<Map<String, dynamic>> eveningAzkar = [
    {
      'text': '''آية الكرسي:
اللّهُ لاَ إِلَهَ إِلَّا هُوَ الْحَيُّ الْقَيُّومُ ۚ 
لَا تَأْخُذُهُ سِنَةٌ وَلَا نَوْمٌ ۚ لَهُ مَا فِي السَّمَاوَاتِ وَمَا فِي الْأَرْضِ ۗ 
مَن ذَا الَّذِي يَشْفَعُ عِندَهُ إِلَّا بِإِذْنِهِ ۚ يَعْلَمُ مَا بَيْنَ أَيْدِيهِمْ وَمَا خَلْفَهُمْ ۖ 
وَلَا يُحِيطُونَ بِشَيْءٍ مِنْ عِلْمِهِ إِلَّا بِمَا شَاءَ ۚ وَسِعَ كُرْسِيُّهُ السَّمَاوَاتِ وَالْأَرْضَ 
وَلَا يَئُودُهُ حِفْظُهُمَا ۚ وَهُوَ الْعَلِيُّ الْعَظِيمُ
(البقرة 255)

من قالها حين يمسي أجير من الجن حتى يصبح.''',
      'count': 1,
    },
    {
      'text': '''سورة الإخلاص:
      
﴿قُلْ هُوَ ٱللَّهُ أَحَدٌ﴾۝١  
﴿ٱللَّهُ ٱلصَّمَدُ﴾۝٢  
﴿لَمْ يَلِدْ وَلَمْ يُولَدْ﴾۝٣  
﴿وَلَمْ يَكُن لَّهُۥ كُفُوٗا أَحَدٌ﴾۝٤
من قالها ثلاث مرات حين يمسي كفت من كل شيء.''',
      'count': 3,
    },
    {
      'text': '''سورة الفلق:

﴿قُلْ أَعُوذُ بِرَبِّ ٱلْفَلَقِ﴾۝١  
﴿مِن شَرِّ مَا خَلَقَ﴾۝٢
﴿وَمِن شَرِّ غَاسِقٍ إِذَا وَقَبَ﴾۝٣  
﴿وَمِن شَرِّ ٱلنَّفَّـٰثَـٰتِ فِى ٱلْعُقَدِ﴾۝٤  
﴿وَمِن شَرِّ حَاسِدٍ إِذَا حَسَدَ﴾۝
من قالها حين يمسي كفت من كل شيء.''',
      'count': 3,
    },
    {
      'text': '''سورة الناس:
﴿قُلْ أَعُوذُ بِرَبِّ ٱلنَّاسِ﴾۝١  
﴿مَلِكِ ٱلنَّاسِ﴾۝٢  
﴿إِلَـٰهِ ٱلنَّاسِ﴾۝٣  
﴿مِن شَرِّ ٱلْوَسْوَاسِ ٱلْخَنَّاسِ﴾۝٤  
﴿ٱلَّذِى يُوَسْوِسُ فِى صُدُورِ ٱلنَّاسِ﴾۝٥  
﴿مِنَ ٱلْجِنَّةِ وَٱلنَّاسِ﴾۝٦

من قالها حين يمسي كفت من كل شيء.''',
      'count': 3,
    },
    {
      'text': '''دعاء سيد الاستغفار:
اللَّهُمَّ أَنْتَ رَبِّي لا إِلَهَ إِلَّا أَنْتَ، خَلَقْتَنِي وَأَنَا عَبْدُكَ، وَأَنَا عَلَى عَهْدِكَ وَوَعْدِكَ مَا اسْتَطَعْتُ، أَعُوذُ بِكَ مِنْ شَرِّ مَا صَنَعْتُ، أَبُوءُ لَكَ بِنِعْمَتِكَ عَلَيَّ، وَأَبُوءُ بِذَنْبِي فَاغْفِرْ لِي، فَإِنَّهُ لا يَغْفِرُ الذُّنُوبَ إِلَّا أَنْتَ.

من قاله موقنًا به حين يمسي ومات من ليلته دخل الجنة.''',
      'count': 1,
    },
    {
      'text':
          '''رضيت بالله رباً، وبالإسلام ديناً، وبمحمد صلى الله عليه وسلم نبياً.

من قالها حين يمسي كان حقا على الله أن يرضيه يوم القيامة.''',
      'count': 3,
    },
    {
      'text':
          '''اللَّهُمَّ إِنِّي أَصْبَحْتُ أُشْهِدُكَ وَأُشْهِدُ حَمَلَةَ عَرْشِكَ وَمَلَائِكَتَكَ وَجَمِيعَ خَلْقِكَ أَنَّكَ أَنْتَ اللَّهُ لا إِلَهَ إِلَّا أَنْتَ وَحْدَكَ لا شَرِيكَ لَكَ، وَأَنَّ مُحَمَّدًا عَبْدُكَ وَرَسُولُكَ.

من قالها حين يمسي أعتقه الله من النار.''',
      'count': 4,
    },
    {
      'text':
          '''اللَّهُمَّ مَا أَصْبَحَ بِي مِنْ نِعْمَةٍ أَوْ بِأَحَدٍ مِنْ خَلْقِكَ فَمِنْكَ وَحْدَكَ لَا شَرِيكَ لَكَ، فَلَكَ الْحَمْدُ وَلَكَ الشُّكْر.

من قالها حين يمسي أدى شكر يومه.''',
      'count': 1,
    },
    {
      'text': '''حسبي الله لا إله إلا هو عليه توكلت وهو رب العرش العظيم.

من قالها حين يمسي كفاه الله ما أهمه من أمر الدنيا والآخرة.''',
      'count': 7,
    },
    {
      'text':
          '''بسم الله الذي لا يضر مع اسمه شيء في الأرض ولا في السماء وهو السميع العليم.

لم يضره شيء من الله.''',
      'count': 3,
    },
    {
      'text':
          '''اللَّهُمَّ بِكَ أَصْبَحْنَا وَبِكَ أَمْسَيْنَا، وَبِكَ نَحْيَا وَبِكَ نَمُوتُ وَإِلَيْكَ النُّشُور.''',
      'count': 1,
    },
    {
      'text':
          '''أصبحنا على فطرة الإسلام، وعلى كلمة الإخلاص، وعلى دين نبينا محمد صلى الله عليه وسلم، وعلى ملة أبينا إبراهيم حنيفا مسلما، وما كان من المشركين.''',
      'count': 1,
    },
    {
      'text':
          '''سبحان الله وبحمده عدد خلقه، ورضا نفسه، وزنة عرشه، ومداد كلماته.''',
      'count': 3,
    },
    {
      'text':
          '''اللَّهُمَّ عافني في بدني، اللَّهُمَّ عافني في سمعي، اللَّهُمَّ عافني في بصري، لا إله إلا أنت.''',
      'count': 3,
    },
    {
      'text':
          '''اللَّهُمَّ إِنِّي أَعُوذُ بِكَ مِنَ الْكُفْرِ، وَالْفَقْرِ، وَأَعُوذُ بِكَ مِنْ عَذَابِ الْقَبْرِ، لا إله إلا أنت.''',
      'count': 3,
    },
    {
      'text':
          '''اللَّهُمَّ إِنِّي أَسْأَلُكَ العَفْوَ وَالعَافِيَةَ فِي الدُّنْيَا وَالآخِرَةِ، اللَّهُمَّ إِنِّي أَسْأَلُكَ العَفْوَ وَالعَافِيَةَ فِي ديني وَدُنْيَايَ وَأَهْلِي وَمالي، اللَّهُمَّ اسْتُرْ عَوْراتي وَآمِنْ رَوْعَاتي، اللَّهُمَّ احْفَظْنِي مِنْ بَيْنِ يَدَيَّ وَمِنْ خَلْفِي وَعَنْ يَمِينِي وَعَنْ شِمَالِي، وَمِنْ فَوْقِي، وَأَعُوذُ بِعَظَمَتِكَ أَنْ أُغْتَالَ مِنْ تَحْتِي.''',
      'count': 1,
    },
    {
      'text':
          '''يَا حَيُّ يَا قَيُّومُ بِرَحْمَتِكَ أَسْتَغِيثُ أَصْلِحْ لِي شَأْنِي كُلَّهُ وَلا تَكِلْنِي إِلَى نَفْسِي طَرْفَةَ عَيْنٍ.''',
      'count': 3,
    },
    {
      'text':
          '''أصبحنا وأصبح الملك لله رب العالمين، اللَّهُمَّ إِنِّي أَسْأَلُكَ خَيْرَ هَذَا الْيَوْمِ، فَتْحَهُ، وَنَصْرَهُ، وَنُورَهُ، وَبَرَكَتَهُ، وَهُدَاهُ، وَأَعُوذُ بِكَ مِنْ شَرِّ مَا فِيهِ وَشَرِّ مَا بَعْدَه.''',
      'count': 1,
    },
    {
      'text':
          '''اللَّهُمَّ عَلِمَ الغَيْبَ وَالشَّهَادَةَ فَاطِرَ السَّمَاوَاتِ وَالأَرْضِ رَبَّ كُلِّ شَيْءٍ وَمَلِيكَهُ، أَشْهَدُ أَنْ لا إِلَهَ إِلَّا أَنْتَ، أَعُوذُ بِكَ مِنْ شَرِّ نَفْسِي وَمِنْ شَرِّ الشَّيْطَانِ وَشِرْكِهِ، وَأَنْ أَقْتَرِفَ عَلَى نَفْسِي سُوءًا أَوْ أَجُرَّهُ إِلَى مُسْلِم.''',
      'count': 1,
    },
    {
      'text':
          '''أَعُوذُ بِكَلِمَاتِ اللَّهِ التَّامَّاتِ مِنْ شَرِّ مَا خَلَق.''',
      'count': 3,
    },
    {
      'text':
          '''اللَّهُمَّ صَلِّ وَسَلِّمْ وَبَارِكْ عَلَى نَبِيِّنَا مُحَمَّدٍ، 

من صلى عليّ حين يمسي أدركته شفاعتي يوم القيامة.''',
      'count': 10,
    },
    {
      'text':
          '''اللَّهُمَّ إِنَّا نَعُوذُ بِكَ مِنْ أَنْ نُشْرِكَ بِكَ شَيْئًا نَعْلَمُهُ، وَنَسْتَغْفِرُكَ لِمَا لَا نَعْلَمُهُ.''',
      'count': 3,
    },
    {
      'text': '''اللَّهُمَّ إِنِّي أَعُوذُ بِكَ مِنَ الْهَمِّ وَالْحَزَنِ،
 وَأَعُوذُ بِكَ مِنَ الْعَجْزِ وَالْكَسَلِ، 
 وَأَعُوذُ بِكَ مِنَ الْجُبْنِ وَالْبُخْلِ،
 وَأَعُوذُ بِكَ مِنْ غَلَبَةِ الدَّيْنِ وَقَهْرِ الرِّجَالِ.''',
      'count': 3,
    },
    {
      'text':
          '''أَسْتَغْفِرُ اللَّهَ الْعَظِيمَ الَّذِي لَا إِلَهَ إِلَّا هُوَ، الْحَيُّ الْقَيُّومُ، وَأَتُوبُ إِلَيْهِ.''',
      'count': 3,
    },
    {
      'text':
          '''يَا رَبِّ، لَكَ الْحَمْدُ كَمَا يَنْبَغِي لِجَلَالِ وَجْهِكَ، وَلِعَظِيمِ سُلْطَانِكَ.''',
      'count': 3,
    },
    {
      'text':
          '''اللَّهُمَّ إِنِّي أَسْأَلُكَ عِلْمًا نَافِعًا، وَرِزْقًا طَيِّبًا، وَعَمَلًا مُتَقَبَّلًا.''',
      'count': 1,
    },
    {
      'text':
          '''اللَّهُمَّ أَنْتَ رَبِّي لا إِلَهَ إِلَّا أَنْتَ، عَلَيْكَ تَوَكَّلْتُ، وَأَنْتَ رَبُّ الْعَرْشِ الْعَظِيمِ، مَا شَاءَ اللَّهُ كَانَ وَمَا لَمْ يَشَأْ لَمْ يَكُنْ، لَا حَوْلَ وَلَا قُوَّةَ إِلَّا بِاللَّهِ، أَعْلَمُ أَنَّ الْحَيَّ لَا يَمُوتُ، وَأَنَّ الْمَوْتَ لَا مَفَرَّ مِنْهُ، وَأَنَّكَ تَجْمَعُ بَيْنَ الْمَوْتِ وَالْحَيَاةِ، اللَّهُمَّ إِنِّي أَسْأَلُكَ الْجَنَّةَ، وَأَعُوذُ بِكَ مِنَ النَّارِ.''',
      'count': 1,
    },
    {
      'text':
          '''لَا إِلَهَ إِلَّا اللَّهُ وَحْدَهُ لَا شَرِيكَ لَهُ، لَهُ الْمُلْكُ وَلَهُ الْحَمْدُ، وَهُوَ عَلَى كُلِّ شَيْءٍ قَدِيرٌ.

كانت له عدل عشر رقاب، وكتبت له مئة حسنة، ومحيت عنه مئة سيئة، وكانت له حرزًا من الشيطان.''',
      'count': 100,
    },
    {
      'text': '''سُبْحـانَ اللهِ وَبِحَمْـدِهِ.

حُطَّتْ خَطَايَاهُ وَإِنْ كَانَتْ مِثْلَ زَبَدِ الْبَحْرِ.
 لَمْ يَأْتِ أَحَدٌ يَوْمَ الْقِيَامَةِ بِأَفْضَلَ مِمَّا جَاءَ بِهِ 
 إِلَّا أَحَدٌ قَالَ مِثْلَ مَا قَالَ أَوْ زَادَ عَلَيْهِ.''',
      'count': 100,
    },
    {'text': '''أسْتَغْفِرُ اللهَ وَأتُوبُ إلَيْهِ''', 'count': 100},
  ];

  final List<Map<String, dynamic>> quranPrayers = [
    {
      'text': 'رَبَّنَا تَقَبَّلْ مِنَّا ۖ إِنَّكَ أَنتَ السَّمِيعُ الْعَلِيمُ',
      'count': 3,
    }, // البقرة:127
    {
      'text':
          'رَبَّنَا آتِنَا فِي الدُّنْيَا حَسَنَةً وَفِي الْآخِرَةِ حَسَنَةً وَقِنَا عَذَابَ النَّارِ',
      'count': 3,
    }, // البقرة:201
    {
      'text':
          'رَبَّنَا لَا تُزِغْ قُلُوبَنَا بَعْدَ إِذْ هَدَيْتَنَا وَهَبْ لَنَا مِن لَّدُنكَ رَحْمَةً ۚ إِنَّكَ أَنتَ الْوَهَّابُ',
      'count': 3,
    }, // آل عمران:8
    {
      'text':
          'رَبَّنَا إِنَّنَا آمَنَّا فَاغْفِرْ لَنَا ذُنُوبَنَا وَقِنَا عَذَابَ النَّارِ',
      'count': 3,
    }, // آل عمران:16
    {
      'text':
          'رَبَّنَا أَفْرِغْ عَلَيْنَا صَبْرًا وَثَبِّتْ أَقْدَامَنَا وَانصُرْنَا عَلَى الْقَوْمِ الْكَافِرِينَ',
      'count': 3,
    }, // البقرة:250
    {
      'text': 'رَبِّ اشْرَحْ لِي صَدْرِي ۝ وَيَسِّرْ لِي أَمْرِي',
      'count': 3,
    }, // طه:25-26
    {'text': 'رَبِّ زِدْنِي عِلْمًا', 'count': 1},
    {
      'text': 'رَبِّ هَبْ لِي حُكْمًا وَأَلْحِقْنِي بِالصَّالِحِينَ',
      'count': 3,
    },
    {
      'text':
          'رَبِّ اجْعَلْنِي مُقِيمَ الصَّلَاةِ وَمِن ذُرِّيَّتِي ۚ رَبَّنَا وَتَقَبَّلْ دُعَاءِ',
      'count': 3,
    },
    {
      'text':
          'رَبَّنَا اغْفِرْ لِي وَلِوَالِدَيَّ وَلِلْمُؤْمِنِينَ يَوْمَ يَقُومُ الْحِسَابُ',
      'count': 3,
    },
    {'text': 'رَبِّ نَجِّنِي مِنَ الْقَوْمِ الظَّالِمِينَ', 'count': 3},
    {
      'text': 'رَبِّ أَعُوذُ بِكَ مِنْ هَمَزَاتِ الشَّيَاطِينِ',
      'count': 3,
    }, // المؤمنون:97
    {'text': 'وَقُل رَّبِّ زِدْنِي عِلْمًا', 'count': 3},
    {
      'text':
          'رَبَّنَا ظَلَمْنَا أَنفُسَنَا وَإِن لَّمْ تَغْفِرْ لَنَا وَتَرْحَمْنَا لَنَكُونَنَّ مِنَ الْخَاسِرِينَ',
      'count': 3,
    }, // الأعراف:23
    {'text': 'رَبِّ هَبْ لِي مِنَ الصَّالِحِينَ', 'count': 3}, // الصافات:100
    {
      'text': 'رَبِّ لَا تَذَرْنِي فَرْدًا وَأَنتَ خَيْرُ الْوَارِثِينَ',
      'count': 3,
    }, // الأنبياء:89
    {
      'text':
          'رَبِّ إِنِّي أَعُوذُ بِكَ أَنْ أَسْأَلَكَ مَا لَيْسَ لِي بِهِ عِلْمٌ',
      'count': 3,
    }, // هود:47
    {
      'text': 'رَبِّ نَجِّنِي وَأَهْلِي مِمَّا يَعْمَلُونَ',
      'count': 3,
    }, // الشعراء:169
    {
      'text': 'رَبَّنَا أَتْمِمْ لَنَا نُورَنَا وَاغْفِرْ لَنَا',
      'count': 3,
    }, // التحريم:8
    {
      'text':
          'رَبِّ أَدْخِلْنِي مُدْخَلَ صِدْقٍ وَأَخْرِجْنِي مُخْرَجَ صِدْقٍ وَاجْعَل لِّي مِن لَّدُنكَ سُلْطَانًا نَّصِيرًا',
      'count': 3,
    }, // الإسراء:80
  ];

  final List<Map<String, dynamic>> prophetPrayers = [
    {
      'text':
          'اللّهُمَّ آتِ نَفْسِي تَقْوَاهَا، وَزَكِّهَا أَنْتَ خَيْرُ مَنْ زَكَّاهَا، أَنْتَ وَلِيُّهَا وَمَوْلَاهَا.',
      'count': 3,
    },
    {
      'text':
          'اللّهُمَّ إني أَسْأَلُكَ الْهُدَى، وَالتُّقَى، وَالْعَفَافَ، وَالْغِنَى.',
      'count': 3,
    },
    {
      'text':
          'اللّهُمَّ إني أعوذُ بك من زوالِ نِعمتك، وتحوُّلِ عافيتك، وفُجاءة نقمتك، وجميعِ سَخَطِك.',
      'count': 3,
    },
    {
      'text':
          'اللَّهُمَّ إني أَعُوذُ بِكَ مِنَ الْهَمِّ وَالْحَزَنِ، وَالْعَجْزِ وَالْكَسَلِ، وَالْجُبْنِ وَالْبُخْلِ، وَغَلَبَةِ الدَّيْنِ، وَقَهْرِ الرِّجَالِ.',
      'count': 3,
    },
    {
      'text':
          'اللَّهُمَّ اجْعَلْ خَيْرَ عُمْرِي آخِرَهُ، وَخَيْرَ عَمَلِي خَوَاتِمَهُ، وَخَيْرَ أَيَّامِي يَوْمَ أَلْقَاكَ فِيهِ.',
      'count': 3,
    },
    {
      'text':
          'اللَّهُمَّ إني أَسْأَلُكَ رِضَاكَ وَالْجَنَّةَ، وَأَعُوذُ بِكَ مِنْ سَخَطِكَ وَالنَّارِ.',
      'count': 3,
    },
    {
      'text':
          'اللَّهُمَّ طَهِّرْنِي مِنَ الذُّنُوبِ وَالْخَطَايَا كَمَا يُنَقَّى الثَّوْبُ الْأَبْيَضُ مِنَ الدَّنَسِ.',
      'count': 3,
    },
    {
      'text':
          'اللَّهُمَّ بَارِكْ لِي فِيمَا رَزَقْتَنِي، وَقِنِي عَذَابَ النَّارِ.',
      'count': 3,
    },
    {
      'text':
          'اللَّهُمَّ إني أَعُوذُ بِكَ مِنَ الْفَقْرِ، وَالْقِلَّةِ، وَالذِّلَّةِ، وَأَعُوذُ بِكَ مِنْ أَنْ أَظْلِمَ أَوْ أُظْلَمَ.',
      'count': 3,
    },
    {
      'text':
          'اللَّهُمَّ إني أَعُوذُ بِكَ مِنْ جَهْدِ الْبَلَاءِ، وَدَرَكِ الشَّقَاءِ، وَسُوءِ الْقَضَاءِ، وَشَمَاتَةِ الْأَعْدَاءِ.',
      'count': 3,
    },
    {
      'text':
          'اللَّهُمَّ اكْفِنِي بِحَلالِكَ عَنْ حَرَامِكَ، وَأَغْنِنِي بِفَضْلِكَ عَمَّنْ سِوَاكَ.',
      'count': 3,
    },
    {
      'text':
          'اللَّهُمَّ أَحْسِنْ عَاقِبَتَنَا فِي الْأُمُورِ كُلِّهَا، وَأَجِرْنَا مِنْ خِزْيِ الدُّنْيَا وَعَذَابِ الْآخِرَةِ.',
      'count': 3,
    },
    {
      'text':
          'اللَّهُمَّ اجْعَلْنِي مِنَ التَّوَّابِينَ وَاجْعَلْنِي مِنَ الْمُتَطَهِّرِينَ.',
      'count': 3,
    },
    {
      'text':
          'اللَّهُمَّ إني أَعُوذُ بِكَ مِنْ قَلْبٍ لاَ يَخْشَعُ، وَمِنْ دُعَاءٍ لاَ يُسْمَعُ، وَمِنْ نَفْسٍ لاَ تَشْبَعُ، وَمِنْ عِلْمٍ لاَ يَنْفَعُ.',
      'count': 3,
    },
    {
      'text':
          'اللَّهُمَّ اهْدِنِي وَسَدِّدْنِي، اللَّهُمَّ إني أَسْأَلُكَ الْهُدَى وَالسَّدَادَ.',
      'count': 3,
    },
    {
      'text':
          'اللَّهُمَّ إني أَعُوذُ بِكَ مِنْ مُنْكَرَاتِ الْأَخْلَاقِ وَالْأَعْمَالِ وَالْأَهْوَاءِ.',
      'count': 3,
    },
    {
      'text': 'اللَّهُمَّ ثَبِّتْنِي وَاجْعَلْنِي هَادِيًا مَهْدِيًّا.',
      'count': 3,
    },
    {
      'text':
          'اللَّهُمَّ اغْفِرْ لِي ذَنْبِي كُلَّهُ، دِقَّهُ وَجِلَّهُ، وَأَوَّلَهُ وَآخِرَهُ، وَعَلاَنِيَتَهُ وَسِرَّهُ.',
      'count': 3,
    },
    {
      'text':
          'اللَّهُمَّ إنِّي أَعُوذُ بِرِضَاكَ مِنْ سَخَطِكَ، وَبِمُعَافَاتِكَ مِنْ عُقُوبَتِكَ.',
      'count': 3,
    },
    {
      'text':
          'اللَّهُمَّ إني أَسْأَلُكَ مِنَ الْخَيْرِ كُلِّهِ، عَاجِلِهِ وَآجِلِهِ، مَا عَلِمْتُ مِنْهُ وَمَا لَمْ أَعْلَمْ.',
      'count': 3,
    },
    {
      'text':
          'اللَّهُمَّ إني أَعُوذُ بِكَ مِنَ الْعَجْزِ وَالْكَسَلِ، وَالْبُخْلِ وَالْهَرَمِ، وَعَذَابِ الْقَبْرِ.',
      'count': 3,
    },
    {
      'text':
          'اللَّهُمَّ اجْعَلْنِي لَكَ شَكَّارًا، لَكَ ذَكَّارًا، لَكَ رَهَّابًا، لَكَ مِطْوَاعًا، لَكَ مُخْبِتًا، إِلَيْكَ أَوَّاهًا مُنِيبًا.',
      'count': 3,
    },
    {
      'text':
          'اللَّهُمَّ إني أَعُوذُ بِكَ مِنْ سُوءِ الْمُنْقَلَبِ فِي الْمَالِ وَالْأَهْلِ وَالْوَلَدِ.',
      'count': 3,
    },
    {
      'text':
          'اللَّهُمَّ إني أَسْأَلُكَ نَفْسًا مُطْمَئِنَّةً، تُؤْمِنُ بِلِقَائِكَ، وَتَرْضَى بِقَضَائِكَ، وَتَقْنَعُ بِعَطَائِكَ.',
      'count': 3,
    },
    {
      'text':
          'اللَّهُمَّ إني أَسْأَلُكَ الْعَافِيَةَ فِي الدُّنْيَا وَالآخِرَةِ.',
      'count': 3,
    },
    {
      'text':
          'اللَّهُمَّ إني أَسْأَلُكَ الرِّضَا بَعْدَ الْقَضَاءِ، وَبَرْدَ الْعَيْشِ بَعْدَ الْمَوْتِ.',
      'count': 3,
    },
    {
      'text':
          'اللَّهُمَّ اجْعَلْنِي مِنَ الَّذِينَ إِذَا أَحْسَنُوا اسْتَبْشَرُوا، وَإِذَا أَسَاءُوا اسْتَغْفَرُوا.',
      'count': 3,
    },
    {
      'text':
          'اللَّهُمَّ اجْعَلْ خَيْرَ أَعْمَالِنَا خَوَاتِمَهَا، وَخَيْرَ أَيَّامِنَا يَوْمَ نَلْقَاكَ فِيهِ.',
      'count': 3,
    },
    {
      'text':
          'اللَّهُمَّ اجْعَلْنِي نُورًا فِي قَلْبِي، وَنُورًا فِي سَمْعِي، وَنُورًا فِي بَصَرِي، وَنُورًا عَنْ يَمِينِي، وَنُورًا عَنْ شِمَالِي.',
      'count': 3,
    },
    {
      'text':
          'اللَّهُمَّ إني أَعُوذُ بِكَ مِنْ شَرِّ نَفْسِي، وَمِنْ شَرِّ كُلِّ دَابَّةٍ أَنْتَ آخِذٌ بِنَاصِيَتِهَا.',
      'count': 3,
    },
  ];
}
