import 'package:flutter/widgets.dart';

/// User-facing names are independent of the stable keys in saved presets.
String renameMaskVariantLabel(BuildContext context, {required bool extended}) {
  final language = Localizations.maybeLocaleOf(context)?.languageCode ?? 'en';
  final labels = _labels[language] ?? _labels['en']!;
  return labels[extended ? 1 : 0];
}

const _labels = <String, List<String>>{
  'en': ['Classic masks', 'Extended masks'],
  'de': ['Klassische Masken', 'Erweiterte Masken'],
  'fr': ['Masques classiques', 'Masques étendus'],
  'es': ['Máscaras clásicas', 'Máscaras ampliadas'],
  'pt': ['Máscaras clássicas', 'Máscaras estendidas'],
  'zh': ['经典掩码', '扩展掩码'],
  'ja': ['標準マスク', '拡張マスク'],
  'ko': ['기본 마스크', '확장 마스크'],
  'ar': ['أقنعة تقليدية', 'أقنعة موسعة'],
};
