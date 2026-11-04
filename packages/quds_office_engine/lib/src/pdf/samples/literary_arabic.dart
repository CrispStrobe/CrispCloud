import 'dart:typed_data';

import '../../fonts/sfnt_parser.dart';
import '../widgets/pw_box.dart';
import '../widgets/pw_chrome.dart';
import '../widgets/pw_content.dart';
import '../widgets/pw_core.dart';
import '../widgets/pw_layout.dart';
import '../widgets/pw_media.dart';
import '../widgets/pw_style.dart';
import '../widgets/pw_table.dart';
import '../widgets/pw_text.dart';
import '../widgets/pw_types.dart';

/// Vocalised Arabic verses and classical qasidas (Tajawal / any glyf face).
Uint8List buildAyatWaAsharPdf({SfntFont? font, SfntFont? fontBold}) {
  final Document doc = Document(
    title: 'آيَاتٌ وَأَشْعَارٌ',
    author: 'Quds Studio',
    font: font,
    fontBold: fontBold,
    theme: const ThemeData(
      defaultTextStyle: TextStyle(fontSize: 11, color: '292524', height: 1.55),
    ),
  );
  doc.addPage(
    MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const EdgeInsets.fromLTRB(40, 34, 40, 42),
      textDirection: TextDirection.rtl,
      header: (Context context) {
        if (context.pageNumber == 1) {
          return const SizedBox.shrink();
        }
        return const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: Column(
            children: <Widget>[
              Row(
                children: <Widget>[
                  Text(
                    'آيَاتٌ وَأَشْعَارٌ',
                    style: TextStyle(
                      fontSize: 8,
                      fontWeight: FontWeight.bold,
                      color: '9A3412',
                    ),
                  ),
                  Spacer(),
                  Text(
                    'قُدْس  ·  تَجْوَال',
                    style: TextStyle(fontSize: 8, color: 'A8A29E'),
                  ),
                ],
              ),
              Divider(height: 8, thickness: 0.7, color: 'E7D5C4'),
            ],
          ),
        );
      },
      footer: (Context context) => Footer(
        leading: const Text(
          'مُشَكَّلٌ  ·  غَيْرُ مُصْحَفٍ',
          style: TextStyle(fontSize: 7.5, color: 'A8A29E'),
        ),
        title: const SizedBox.shrink(),
        trailing: PageNumber(
          builder: (int page, int count) => Text(
            '\u202D$page / $count\u202C',
            softWrap: false,
            style: const TextStyle(fontSize: 8, color: '78716C'),
          ),
        ),
      ),
      build: (Context context) => <Widget>[
        _cover(),
        const NewPage(),
        const TableOfContent(title: 'الْفِهْرِسُ'),
        const SizedBox(height: 12),
        const Callout(
          title: 'هَذِهِ عَيِّنَةُ صَفٍّ',
          body:
              'النَّصُّ مَشْكُولٌ لِاخْتِبَارِ التَّشْكِيلِ وَجَدْوَلِ GPOS، '
              'لَا يُغْنِي عَنْ مُصْحَفٍ مُعْتَمَدٍ وَلَا عَنْ دِيوَانٍ مُحَقَّقٍ. '
              'الْوَجْهُ الْمُضَمَّنُ تَجْوَال، وَالِاتِّجَاهُ مِنَ الْيَمِينِ.',
          tone: BadgeTone.warning,
          accentColor: 'B45309',
          backgroundColor: 'FFF7ED',
        ),
        const NewPage(),
        Header(
          level: 1,
          text: 'مِنَ الذِّكْرِ الْحَكِيمِ',
          textStyle: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: '14532D',
          ),
        ),
        const Text(
          'مُخْتَارَاتٌ قِصَارٌ مَشْكُولَةٌ. كُلُّ آيَةٍ فِي بِطَاقَةٍ مُسْتَقِلَّةٍ '
          'حَتَّى لَا يَنْقَطِعَ السَّطْرُ عَنْ حَرَكَتِهِ.',
          textAlign: TextAlign.start,
          style: TextStyle(fontSize: 10.5, color: '44403C', height: 1.6),
        ),
        const SizedBox(height: 10),
        _band('سُورَةُ الْفَاتِحَةِ', 'حَفْصٌ عَنْ عَاصِمٍ  ·  سَبْعُ آيَاتٍ', '14532D', 'DCFCE7'),
        ..._numberedAyat(const <String>[
          'بِسْمِ اللَّهِ الرَّحْمَنِ الرَّحِيمِ',
          'الْحَمْدُ لِلَّهِ رَبِّ الْعَالَمِينَ',
          'الرَّحْمَنِ الرَّحِيمِ',
          'مَالِكِ يَوْمِ الدِّينِ',
          'إِيَّاكَ نَعْبُدُ وَإِيَّاكَ نَسْتَعِينُ',
          'اهْدِنَا الصِّرَاطَ الْمُسْتَقِيمَ',
          'صِرَاطَ الَّذِينَ أَنْعَمْتَ عَلَيْهِمْ غَيْرِ الْمَغْضُوبِ عَلَيْهِمْ وَلَا الضَّالِّينَ',
        ]),
        const SizedBox(height: 14),
        Header(
          level: 2,
          text: 'سُورَةُ الْإِخْلَاصِ',
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: '166534',
          ),
        ),
        ..._numberedAyat(const <String>[
          'قُلْ هُوَ اللَّهُ أَحَدٌ',
          'اللَّهُ الصَّمَدُ',
          'لَمْ يَلِدْ وَلَمْ يُولَدْ',
          'وَلَمْ يَكُنْ لَهُ كُفُوًا أَحَدٌ',
        ]),
        const NewPage(),
        Header(
          level: 2,
          text: 'سُورَةُ الْعَصْرِ',
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: '166534',
          ),
        ),
        ..._numberedAyat(const <String>[
          'وَالْعَصْرِ',
          'إِنَّ الْإِنْسَانَ لَفِي خُسْرٍ',
          'إِلَّا الَّذِينَ آمَنُوا وَعَمِلُوا الصَّالِحَاتِ وَتَوَاصَوْا بِالْحَقِّ وَتَوَاصَوْا بِالصَّبْرِ',
        ]),
        const SizedBox(height: 12),
        Header(
          level: 2,
          text: 'مِنْ سُورَةِ الشَّرْحِ',
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: '166534',
          ),
        ),
        ..._numberedAyat(const <String>[
          'فَإِنَّ مَعَ الْعُسْرِ يُسْرًا',
          'إِنَّ مَعَ الْعُسْرِ يُسْرًا',
        ], start: 5),
        const SizedBox(height: 12),
        Header(
          level: 2,
          text: 'مِنْ سُورَةِ الْإِسْرَاءِ',
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: '166534',
          ),
        ),
        _ayatCard(
          '٨٢',
          'وَنُنَزِّلُ مِنَ الْقُرْآنِ مَا هُوَ شِفَاءٌ وَرَحْمَةٌ لِلْمُؤْمِنِينَ',
        ),
        const SizedBox(height: 12),
        Header(
          level: 2,
          text: 'آيَةُ الْكُرْسِيِّ',
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: '166534',
          ),
        ),
        _ayatCard(
          '٢٥٥',
          'اللَّهُ لَا إِلَهَ إِلَّا هُوَ الْحَيُّ الْقَيُّومُ '
          'لَا تَأْخُذُهُ سِنَةٌ وَلَا نَوْمٌ '
          'لَهُ مَا فِي السَّمَاوَاتِ وَمَا فِي الْأَرْضِ '
          'مَنْ ذَا الَّذِي يَشْفَعُ عِنْدَهُ إِلَّا بِإِذْنِهِ '
          'يَعْلَمُ مَا بَيْنَ أَيْدِيهِمْ وَمَا خَلْفَهُمْ '
          'وَلَا يُحِيطُونَ بِشَيْءٍ مِنْ عِلْمِهِ إِلَّا بِمَا شَاءَ '
          'وَسِعَ كُرْسِيُّهُ السَّمَاوَاتِ وَالْأَرْضَ '
          'وَلَا يَئُودُهُ حِفْظُهُمَا وَهُوَ الْعَلِيُّ الْعَظِيمُ',
        ),
        const NewPage(),
        Header(
          level: 1,
          text: 'مِنْ عُيُونِ الشِّعْرِ الْعَرَبِيِّ',
          textStyle: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: '9F1239',
          ),
        ),
        const Text(
          'أَبْيَاتٌ مَشْهُورَةٌ مِنَ الْجَاهِلِيَّةِ إِلَى الْأَنْدَلُسِ. '
          'الصَّدْرُ عَلَى الْيَمِينِ، وَالْعَجُزُ عَلَى الْيَسَارِ، وَالْبَحْرُ فِي شَارَةٍ.',
          textAlign: TextAlign.start,
          style: TextStyle(fontSize: 10.5, color: '44403C', height: 1.6),
        ),
        const SizedBox(height: 10),
        Header(
          level: 2,
          text: 'امْرُؤُ الْقَيْسِ',
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: '9F1239',
          ),
        ),
        _poetMeta('مُعَلَّقَتُهُ', 'الطَّوِيلُ', 'قَبْلَ الْإِسْلَامِ'),
        _bayt(
          'قِفَا نَبْكِ مِنْ ذِكْرَى حَبِيبٍ وَمَنْزِلِ',
          'بِسِقْطِ اللِّوَى بَيْنَ الدَّخُولِ فَحَوْمَلِ',
        ),
        _bayt(
          'فَتُوضِحَ فَالْمِقْرَاةِ لَمْ يَعْفُ رَسْمُهَا',
          'لِمَا نَسَجَتْهَا مِنْ جَنُوبٍ وَشَمْأَلِ',
        ),
        const SizedBox(height: 8),
        Header(
          level: 2,
          text: 'عَنْتَرَةُ بْنُ شَدَّادٍ',
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: '9F1239',
          ),
        ),
        _poetMeta('مِنَ الْمُعَلَّقَةِ', 'الْكَامِلُ', 'قَبْلَ الْإِسْلَامِ'),
        _bayt(
          'وَلَقَدْ ذَكَرْتُكِ وَالرِّمَاحُ نَوَاهِلٌ',
          'مِنِّي وَبِيضُ الْهِنْدِ تَقْطُرُ مِنْ دَمِي',
        ),
        _bayt(
          'فَوَدِدْتُ تَقْبِيلَ السُّيُوفِ لِأَنَّهَا',
          'لَمَعَتْ كَبَارِقِ ثَغْرِكِ الْمُتَبَسِّمِ',
        ),
        const NewPage(),
        Header(
          level: 2,
          text: 'أَبُو الطَّيِّبِ الْمُتَنَبِّي',
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: '9F1239',
          ),
        ),
        _poetMeta('مِنْ مَدِيحِ سَيْفِ الدَّوْلَةِ', 'الطَّوِيلُ', 'الْقَرْنُ الرَّابِعُ'),
        _bayt(
          'عَلَى قَدْرِ أَهْلِ الْعَزْمِ تَأْتِي الْعَزَائِمُ',
          'وَتَأْتِي عَلَى قَدْرِ الْكِرَامِ الْمَكَارِمُ',
        ),
        _bayt(
          'وَتَعْظُمُ فِي عَيْنِ الصَّغِيرِ صِغَارُهَا',
          'وَتَصْغُرُ فِي عَيْنِ الْعَظِيمِ الْعَظَائِمُ',
        ),
        const SizedBox(height: 8),
        Header(
          level: 2,
          text: 'أَبُو فِرَاسٍ الْحَمْدَانِيُّ',
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: '9F1239',
          ),
        ),
        _poetMeta('الرُّومِيَّاتُ', 'الطَّوِيلُ', 'الْقَرْنُ الرَّابِعُ'),
        _bayt(
          'أَرَاكَ عَصِيَّ الدَّمْعِ شِيمَتُكَ الصَّبْرُ',
          'أَمَا لِلْهَوَى نَهْيٌ عَلَيْكَ وَلَا أَمْرُ',
        ),
        _bayt(
          'بَلَى أَنَا مُشْتَاقٌ وَعِنْدِيَ لَوْعَةٌ',
          'وَلَكِنَّ مِثْلِي لَا يُذَاعُ لَهُ سِرُّ',
        ),
        const SizedBox(height: 8),
        Header(
          level: 2,
          text: 'ابْنُ زَيْدُونَ',
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: '9F1239',
          ),
        ),
        _poetMeta('النُّونِيَّةُ', 'الْبَسِيطُ', 'الْأَنْدَلُسُ'),
        _bayt(
          'أَضْحَى التَّنَائِي بَدِيلًا مِنْ تَدَانِينَا',
          'وَنَابَ عَنْ طِيبِ لُقْيَانَا تَجَافِينَا',
        ),
        _bayt(
          'إِنَّ الزَّمَانَ الَّذِي مَا زَالَ يُضْحِكُنَا',
          'أُنْسًا بِقُرْبِهِمُ قَدْ عَادَ يُبْكِينَا',
        ),
        const NewPage(),
        Header(
          level: 1,
          text: 'ثَبَتُ الْمُخْتَارَاتِ',
          textStyle: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: '1C1917',
          ),
        ),
        const Text(
          'جَدْوَلُ الْقِطَعِ كَمَا رُتِّبَتْ فِي هَذَا الدِّيوَانِ الْقَصِيرِ.',
          textAlign: TextAlign.start,
          style: TextStyle(fontSize: 10.5, color: '44403C', height: 1.55),
        ),
        const SizedBox(height: 10),
        Table.fromTextArray(
          headers: const <String>['الْقِطْعَةُ', 'الْفَنُّ', 'الْبَحْرُ / الرِّوَايَةُ', 'الْعَصْرُ'],
          columnWidths: const <double>[1.6, 0.9, 1.5, 1.1],
          cellHeight: 22,
          headerDecoration: '1C1917',
          oddRowDecoration: 'FFF7ED',
          cellStyle: const TextStyle(fontSize: 8.5, color: '292524'),
          headerStyle: const TextStyle(
            fontSize: 8,
            fontWeight: FontWeight.bold,
            color: 'FFFFFF',
          ),
          data: const <List<String>>[
            <String>['سُورَةُ الْفَاتِحَةِ', 'قُرْآنٌ', 'حَفْصٌ', 'مَكِّيَّةٌ'],
            <String>['سُورَةُ الْإِخْلَاصِ', 'قُرْآنٌ', 'حَفْصٌ', 'مَكِّيَّةٌ'],
            <String>['سُورَةُ الْعَصْرِ', 'قُرْآنٌ', 'حَفْصٌ', 'مَكِّيَّةٌ'],
            <String>['الشَّرْحُ ٥–٦', 'قُرْآنٌ', 'حَفْصٌ', 'مَكِّيَّةٌ'],
            <String>['الْإِسْرَاءُ ٨٢', 'قُرْآنٌ', 'حَفْصٌ', 'مَكِّيَّةٌ'],
            <String>['آيَةُ الْكُرْسِيِّ', 'قُرْآنٌ', 'حَفْصٌ', 'مَدَنِيَّةٌ'],
            <String>['قِفَا نَبْكِ', 'شِعْرٌ', 'الطَّوِيلُ', 'جَاهِلِيٌّ'],
            <String>['وَلَقَدْ ذَكَرْتُكِ', 'شِعْرٌ', 'الْكَامِلُ', 'جَاهِلِيٌّ'],
            <String>['عَلَى قَدْرِ أَهْلِ الْعَزْمِ', 'شِعْرٌ', 'الطَّوِيلُ', 'عَبَّاسِيٌّ'],
            <String>['أَرَاكَ عَصِيَّ الدَّمْعِ', 'شِعْرٌ', 'الطَّوِيلُ', 'حَمْدَانِيٌّ'],
            <String>['أَضْحَى التَّنَائِي', 'شِعْرٌ', 'الْبَسِيطُ', 'أَنْدَلُسِيٌّ'],
          ],
        ),
        const SizedBox(height: 14),
        const Callout(
          title: 'خَاتِمَةُ الصَّفِّ',
          body:
              'الضَّمَّةُ وَالْفَتْحَةُ وَالْكَسْرَةُ وَالشَّدَّةُ تُرْسَمُ عَلَى '
              'حُرُوفِهَا مِنْ مَرَاسِي GPOS لَا مِنْ وَسَطِ الْعَرْضِ. '
              'إِنْ فُتِحَتِ الْعَيِّنَةُ فِي عَارِضِ قُدْسٍ فَانْظُرِ الضَّمَّةَ '
              'فَوْقَ الْأَلِفِ فِي «أُنْسًا» وَفَوْقَ الْقَافِ فِي «قُلْ».',
          tone: BadgeTone.info,
          accentColor: '9A3412',
          backgroundColor: 'FFF7ED',
        ),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: <String>['1C1917', '7C2D12'],
              vertical: false,
            ),
            borderRadius: 4,
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                'قُدْس أُوفِس  ·  عَيِّنَةُ الْمَعْرِضِ',
                textAlign: TextAlign.start,
                style: TextStyle(fontSize: 8, color: 'FDBA74', letterSpacing: 0.4),
              ),
              SizedBox(height: 4),
              Text(
                'صُفَّتْ هَذِهِ الْأَوْرَاقُ لِتَرَى الْعَرَبِيَّةَ كَمَا يَنْبَغِي أَنْ تُرَى: '
                'مَشْكُولَةً، مَوْزُونَةً، عَلَى وَجْهٍ يُحْسِنُ الضَّمَّةَ.',
                textAlign: TextAlign.start,
                style: TextStyle(fontSize: 10, color: 'FFF7ED', height: 1.55),
              ),
            ],
          ),
        ),
      ],
    ),
  );
  return doc.save();
}

Widget _cover() {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      Container(
        height: 118,
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: <String>['1C1917', '9A3412', 'B45309'],
            vertical: false,
          ),
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'قُدْس أُوفِس  ·  دِيوَانُ الْعَيِّنَةِ  ·  تَجْوَال',
              textAlign: TextAlign.start,
              style: TextStyle(fontSize: 8, color: 'FED7AA', letterSpacing: 0.5),
            ),
            SizedBox(height: 8),
            Text(
              'آيَاتٌ وَأَشْعَارٌ',
              textAlign: TextAlign.start,
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: 'FFFFFF',
                height: 1.15,
              ),
            ),
            SizedBox(height: 4),
            Text(
              'مُخْتَارَاتٌ عَرَبِيَّةٌ مَشْكُولَةٌ، مُرَتَّبَةٌ عَلَى نَسَقِ الدَّوَاوِينِ.',
              textAlign: TextAlign.start,
              style: TextStyle(fontSize: 11, color: 'FFEDD5', height: 1.4),
            ),
          ],
        ),
      ),
      const SizedBox(height: 14),
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: const <Widget>[
          Badge('قُرْآنٌ', backgroundColor: 'DCFCE7', foregroundColor: '14532D'),
          Badge('شِعْرٌ جَاهِلِيٌّ', backgroundColor: 'FFE4E6', foregroundColor: '9F1239'),
          Badge('شِعْرٌ عَبَّاسِيٌّ', backgroundColor: 'FFEDD5', foregroundColor: '9A3412'),
          Badge('أَنْدَلُسِيٌّ', backgroundColor: 'E0E7FF', foregroundColor: '3730A3'),
          Badge('مَشْكُولٌ', backgroundColor: 'FEF3C7', foregroundColor: '92400E'),
        ],
      ),
      const SizedBox(height: 16),
      const Text(
        'يَجْمَعُ هَذَا الْمَلَفُّ بَيْنَ آيَاتٍ قِصَارٍ مِنَ الذِّكْرِ، '
        'وَأَبْيَاتٍ مِنَ الْمُعَلَّقَاتِ وَالْمَدِيحِ وَالرُّومِيَّاتِ وَالنُّونِيَّةِ. '
        'كُلُّ حَرَكَةٍ مَكْتُوبَةٌ، وَكُلُّ بَيْتٍ مَوْزُونٌ عَلَى صَدْرٍ وَعَجُزٍ.',
        textAlign: TextAlign.start,
        style: TextStyle(fontSize: 12, color: '44403C', height: 1.7),
      ),
      const SizedBox(height: 14),
      Row(
        children: <Widget>[
          Expanded(child: _stat('٦', 'سُوَرٌ وَآيَاتٌ', 'مِنَ الذِّكْرِ')),
          const SizedBox(width: 8),
          Expanded(child: _stat('٥', 'قَصَائِدُ', 'مِنْ عُيُونِ الشِّعْرِ')),
          const SizedBox(width: 8),
          Expanded(child: _stat('١١', 'قِطَعٌ', 'فِي الثَّبَتِ')),
        ],
      ),
      const SizedBox(height: 14),
      const Steps(
        direction: Axis.vertical,
        activeColor: '9A3412',
        doneColor: '3F6212',
        items: <StepItem>[
          StepItem(
            title: 'مِنَ الذِّكْرِ الْحَكِيمِ',
            subtitle: 'الْفَاتِحَةُ · الْإِخْلَاصُ · الْعَصْرُ · آيَاتٌ قِصَارٌ',
            done: true,
          ),
          StepItem(
            title: 'مِنْ عُيُونِ الشِّعْرِ',
            subtitle: 'امْرُؤُ الْقَيْسِ · عَنْتَرَةُ · الْمُتَنَبِّي · أَبُو فِرَاسٍ · ابْنُ زَيْدُونَ',
            done: true,
          ),
          StepItem(
            title: 'ثَبَتُ الْمُخْتَارَاتِ',
            subtitle: 'الْبُحُورُ وَالْعَصْرُ وَمَوْضِعُ كُلِّ قِطْعَةٍ',
            active: true,
          ),
        ],
      ),
    ],
  );
}

Widget _stat(String value, String label, String hint) {
  return Container(
    padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
    decoration: BoxDecoration(
      color: 'FFF7ED',
      border: Border.all(color: 'FED7AA', width: 0.8),
      borderRadius: 4,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          value,
          textAlign: TextAlign.start,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: '9A3412',
          ),
        ),
        Text(
          label,
          textAlign: TextAlign.start,
          style: const TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.bold,
            color: '7C2D12',
          ),
        ),
        Text(
          hint,
          textAlign: TextAlign.start,
          style: const TextStyle(fontSize: 8, color: '78716C'),
        ),
      ],
    ),
  );
}

Widget _band(String title, String kicker, String ink, String wash) {
  return Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
    decoration: BoxDecoration(color: wash, borderRadius: 3),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          kicker,
          textAlign: TextAlign.start,
          style: TextStyle(fontSize: 7.5, color: ink, letterSpacing: 0.3),
        ),
        Text(
          title,
          textAlign: TextAlign.start,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: ink,
          ),
        ),
      ],
    ),
  );
}

List<Widget> _numberedAyat(List<String> ayat, {int start = 1}) {
  return <Widget>[
    for (int i = 0; i < ayat.length; i++) ...<Widget>[
      _ayatCard(_arabicDigit(start + i), ayat[i]),
      const SizedBox(height: 6),
    ],
  ];
}

Widget _ayatCard(String number, String text) {
  return KeepTogether(
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: 'F7FEE7',
        border: Border.all(color: 'BBF7D0', width: 0.7),
        borderRadius: 4,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: '166534',
              shape: BoxShape.circle,
            ),
            child: Text(
              number,
              style: const TextStyle(
                fontSize: 8,
                fontWeight: FontWeight.bold,
                color: 'FFFFFF',
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                color: '14532D',
                height: 1.9,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

Widget _poetMeta(String work, String meter, String era) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Wrap(
      spacing: 6,
      runSpacing: 6,
      children: <Widget>[
        Badge(work, backgroundColor: 'FFE4E6', foregroundColor: '9F1239'),
        Badge(meter, backgroundColor: 'FFEDD5', foregroundColor: '9A3412'),
        Badge(era, tone: BadgeTone.neutral),
      ],
    ),
  );
}

Widget _bayt(String sadr, String ajuz) {
  return KeepTogether(
    child: Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: 'FFF7ED',
        border: Border.all(color: 'FED7AA', width: 0.7),
        borderRadius: 4,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Text(
              sadr,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 11.5,
                color: '7C2D12',
                height: 1.75,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Container(width: 0.8, height: 22, color: 'D6D3D1'),
          ),
          Expanded(
            child: Text(
              ajuz,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 11.5,
                color: '7C2D12',
                height: 1.75,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

String _arabicDigit(int n) {
  const String digits = '٠١٢٣٤٥٦٧٨٩';
  final String latin = n.toString();
  final StringBuffer out = StringBuffer();
  for (final int unit in latin.codeUnits) {
    out.writeCharCode(digits.codeUnitAt(unit - 0x30));
  }
  return out.toString();
}
