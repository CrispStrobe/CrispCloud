import 'package:flutter/widgets.dart';

/// User-visible names for the service's stable biometric identifiers.
class BiometricStrings {
  BiometricStrings(BuildContext context)
      : language = Localizations.maybeLocaleOf(context)?.languageCode ?? 'en';
  final String language;
  String text(String key) => (_values[language] ?? _values['en']!)[key] ?? _values['en']![key]!;
  String label(String identifier) => switch (identifier) {
    'Fingerprint' => text('fingerprint'),
    'Iris' => text('iris'),
    'Biometric' => text('biometric'),
    // Platform brand names and unknown platform identifiers stay intact.
    _ => identifier,
  };
  static const Map<String, Map<String, String>> _values = {
    'en': {'fingerprint': 'Fingerprint', 'iris': 'Iris', 'biometric': 'Biometric', 'reason': 'Unlock CrispCloud'},
    'de': {'fingerprint': 'Fingerabdruck', 'iris': 'Iris', 'biometric': 'Biometrie', 'reason': 'CrispCloud entsperren'},
    'fr': {'fingerprint': 'Empreinte digitale', 'iris': 'Iris', 'biometric': 'Biométrie', 'reason': 'Déverrouiller CrispCloud'},
    'es': {'fingerprint': 'Huella digital', 'iris': 'Iris', 'biometric': 'Biometría', 'reason': 'Desbloquear CrispCloud'},
    'pt': {'fingerprint': 'Impressão digital', 'iris': 'Íris', 'biometric': 'Biometria', 'reason': 'Desbloquear CrispCloud'},
    'zh': {'fingerprint': '指纹', 'iris': '虹膜', 'biometric': '生物识别', 'reason': '解锁 CrispCloud'},
    'ja': {'fingerprint': '指紋', 'iris': '虹彩', 'biometric': '生体認証', 'reason': 'CrispCloud のロックを解除'},
    'ko': {'fingerprint': '지문', 'iris': '홍채', 'biometric': '생체 인증', 'reason': 'CrispCloud 잠금 해제'},
    'ar': {'fingerprint': 'بصمة الإصبع', 'iris': 'قزحية العين', 'biometric': 'القياسات الحيوية', 'reason': 'فتح قفل CrispCloud'},
  };
}
