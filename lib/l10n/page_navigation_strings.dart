import 'package:flutter/widgets.dart';

/// Accessible labels for page navigation controls.
class PageNavigationStrings {
  PageNavigationStrings(BuildContext context)
      : language = Localizations.maybeLocaleOf(context)?.languageCode ?? 'en';
  final String language;
  String text(String key) => (_values[language] ?? _values['en']!)[key] ?? _values['en']![key]!;
  static const Map<String, Map<String, String>> _values = {
    'en': {'first': 'First page', 'previous': 'Previous page', 'next': 'Next page', 'last': 'Last page'},
    'de': {'first': 'Erste Seite', 'previous': 'Vorherige Seite', 'next': 'Nächste Seite', 'last': 'Letzte Seite'},
    'fr': {'first': 'Première page', 'previous': 'Page précédente', 'next': 'Page suivante', 'last': 'Dernière page'},
    'es': {'first': 'Primera página', 'previous': 'Página anterior', 'next': 'Página siguiente', 'last': 'Última página'},
    'pt': {'first': 'Primeira página', 'previous': 'Página anterior', 'next': 'Página seguinte', 'last': 'Última página'},
    'zh': {'first': '第一页', 'previous': '上一页', 'next': '下一页', 'last': '最后一页'},
    'ja': {'first': '最初のページ', 'previous': '前のページ', 'next': '次のページ', 'last': '最後のページ'},
    'ko': {'first': '첫 페이지', 'previous': '이전 페이지', 'next': '다음 페이지', 'last': '마지막 페이지'},
    'ar': {'first': 'الصفحة الأولى', 'previous': 'الصفحة السابقة', 'next': 'الصفحة التالية', 'last': 'الصفحة الأخيرة'},
  };
}
