import 'package:flutter/widgets.dart';

/// A small independent fallback so startup errors remain readable even when
/// the normal application state and providers could not be initialized.
class StartupFailureStrings {
  StartupFailureStrings(BuildContext context)
      : language = Localizations.maybeLocaleOf(context)?.languageCode ?? 'en';
  final String language;
  String get title => _titles[language] ?? _titles['en']!;
  static const Map<String, String> _titles = {
    'en': 'Failed to start CrispCloud:',
    'de': 'CrispCloud konnte nicht gestartet werden:',
    'fr': 'Impossible de démarrer CrispCloud :',
    'es': 'No se pudo iniciar CrispCloud:',
    'pt': 'Não foi possível iniciar o CrispCloud:',
    'zh': '无法启动 CrispCloud：',
    'ja': 'CrispCloud を起動できませんでした:',
    'ko': 'CrispCloud를 시작할 수 없습니다:',
    'ar': 'تعذر بدء CrispCloud:',
  };
}
