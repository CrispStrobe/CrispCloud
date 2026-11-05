import 'package:flutter/widgets.dart';

class PanelTabStrings {
  PanelTabStrings(BuildContext context)
      : language = Localizations.maybeLocaleOf(context)?.languageCode ?? 'en';
  final String language;
  String text(String key) => (_values[language] ?? _values['en']!)[key] ?? _values['en']![key]!;
  static const Map<String, Map<String, String>> _values = {
    'en': {'renameTab': 'Rename Tab', 'tabName': 'Tab name'},
    'de': {'renameTab': 'Tab umbenennen', 'tabName': 'Tabname'},
    'fr': {'renameTab': 'Renommer l’onglet', 'tabName': 'Nom de l’onglet'},
    'es': {'renameTab': 'Renombrar pestaña', 'tabName': 'Nombre de pestaña'},
    'pt': {'renameTab': 'Renomear separador', 'tabName': 'Nome do separador'},
    'zh': {'renameTab': '重命名标签页', 'tabName': '标签页名称'},
    'ja': {'renameTab': 'タブ名を変更', 'tabName': 'タブ名'},
    'ko': {'renameTab': '탭 이름 바꾸기', 'tabName': '탭 이름'},
    'ar': {'renameTab': 'إعادة تسمية علامة التبويب', 'tabName': 'اسم علامة التبويب'},
  };
}
