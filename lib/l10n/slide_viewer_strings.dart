import 'package:flutter/widgets.dart';

class SlideViewerStrings {
  SlideViewerStrings(BuildContext context)
      : language = Localizations.maybeLocaleOf(context)?.languageCode ?? 'en';
  final String language;
  String text(String key) => (_values[language] ?? _values['en']!)[key] ?? _values['en']![key]!;
  static const Map<String, Map<String, String>> _values = {
    'en': {'empty': 'This presentation has no slides.', 'first': 'First slide', 'previous': 'Previous slide', 'next': 'Next slide', 'last': 'Last slide'},
    'de': {'empty': 'Diese Präsentation enthält keine Folien.', 'first': 'Erste Folie', 'previous': 'Vorherige Folie', 'next': 'Nächste Folie', 'last': 'Letzte Folie'},
    'fr': {'empty': 'Cette présentation ne contient aucune diapositive.', 'first': 'Première diapositive', 'previous': 'Diapositive précédente', 'next': 'Diapositive suivante', 'last': 'Dernière diapositive'},
    'es': {'empty': 'Esta presentación no tiene diapositivas.', 'first': 'Primera diapositiva', 'previous': 'Diapositiva anterior', 'next': 'Diapositiva siguiente', 'last': 'Última diapositiva'},
    'pt': {'empty': 'Esta apresentação não tem diapositivos.', 'first': 'Primeiro diapositivo', 'previous': 'Diapositivo anterior', 'next': 'Diapositivo seguinte', 'last': 'Último diapositivo'},
    'zh': {'empty': '此演示文稿没有幻灯片。', 'first': '第一张幻灯片', 'previous': '上一张幻灯片', 'next': '下一张幻灯片', 'last': '最后一张幻灯片'},
    'ja': {'empty': 'このプレゼンテーションにスライドはありません。', 'first': '最初のスライド', 'previous': '前のスライド', 'next': '次のスライド', 'last': '最後のスライド'},
    'ko': {'empty': '이 프레젠테이션에는 슬라이드가 없습니다.', 'first': '첫 슬라이드', 'previous': '이전 슬라이드', 'next': '다음 슬라이드', 'last': '마지막 슬라이드'},
    'ar': {'empty': 'لا يحتوي هذا العرض التقديمي على شرائح.', 'first': 'الشريحة الأولى', 'previous': 'الشريحة السابقة', 'next': 'الشريحة التالية', 'last': 'الشريحة الأخيرة'},
  };
}
