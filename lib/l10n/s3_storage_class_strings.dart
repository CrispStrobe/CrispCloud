import 'package:flutter/widgets.dart';

import '../services/s3_client_adapter.dart';

/// Translates storage choices at presentation time, preserving S3 wire values.
class S3StorageClassStrings {
  S3StorageClassStrings(BuildContext context)
    : language = Localizations.maybeLocaleOf(context)?.languageCode ?? 'en';
  final String language;
  String label(S3StorageClass value) =>
      (_labels[language] ?? _labels['en']!)[value.name]!;
  static const Map<String, Map<String, String>> _labels = {
    "en": {
      "standard": "Standard",
      "standardIa": "Standard-IA",
      "onezoneIa": "One Zone-IA",
      "intelligentTiering": "Intelligent-Tiering",
      "glacier": "Glacier Flexible Retrieval",
      "glacierIr": "Glacier Instant Retrieval",
      "deepArchive": "Glacier Deep Archive",
      "reducedRedundancy": "Reduced Redundancy",
    },
    "de": {
      "standard": "Standard",
      "standardIa": "Standard – seltener Zugriff",
      "onezoneIa": "Eine Zone – seltener Zugriff",
      "intelligentTiering": "Intelligente Speicherklassen",
      "glacier": "Glacier – flexibler Abruf",
      "glacierIr": "Glacier – sofortiger Abruf",
      "deepArchive": "Glacier – Langzeitarchiv",
      "reducedRedundancy": "Reduzierte Redundanz",
    },
    "fr": {
      "standard": "Standard",
      "standardIa": "Standard – accès peu fréquent",
      "onezoneIa": "Zone unique – accès peu fréquent",
      "intelligentTiering": "Hiérarchisation intelligente",
      "glacier": "Glacier – récupération flexible",
      "glacierIr": "Glacier – récupération instantanée",
      "deepArchive": "Glacier – archivage profond",
      "reducedRedundancy": "Redondance réduite",
    },
    "es": {
      "standard": "Estándar",
      "standardIa": "Estándar – acceso poco frecuente",
      "onezoneIa": "Una zona – acceso poco frecuente",
      "intelligentTiering": "Niveles inteligentes",
      "glacier": "Glacier – recuperación flexible",
      "glacierIr": "Glacier – recuperación instantánea",
      "deepArchive": "Glacier – archivo profundo",
      "reducedRedundancy": "Redundancia reducida",
    },
    "pt": {
      "standard": "Padrão",
      "standardIa": "Padrão – acesso pouco frequente",
      "onezoneIa": "Uma zona – acesso pouco frequente",
      "intelligentTiering": "Níveis inteligentes",
      "glacier": "Glacier – recuperação flexível",
      "glacierIr": "Glacier – recuperação instantânea",
      "deepArchive": "Glacier – arquivo profundo",
      "reducedRedundancy": "Redundância reduzida",
    },
    "zh": {
      "standard": "标准",
      "standardIa": "标准 – 低频访问",
      "onezoneIa": "单区 – 低频访问",
      "intelligentTiering": "智能分层",
      "glacier": "Glacier – 灵活检索",
      "glacierIr": "Glacier – 即时检索",
      "deepArchive": "Glacier – 深度归档",
      "reducedRedundancy": "低冗余",
    },
    "ja": {
      "standard": "標準",
      "standardIa": "標準 – 低頻度アクセス",
      "onezoneIa": "1 ゾーン – 低頻度アクセス",
      "intelligentTiering": "インテリジェント階層化",
      "glacier": "Glacier – 柔軟な取り出し",
      "glacierIr": "Glacier – 即時取り出し",
      "deepArchive": "Glacier – 長期アーカイブ",
      "reducedRedundancy": "低冗長化",
    },
    "ko": {
      "standard": "표준",
      "standardIa": "표준 – 저빈도 액세스",
      "onezoneIa": "단일 영역 – 저빈도 액세스",
      "intelligentTiering": "지능형 계층화",
      "glacier": "Glacier – 유연한 검색",
      "glacierIr": "Glacier – 즉시 검색",
      "deepArchive": "Glacier – 심층 아카이브",
      "reducedRedundancy": "감소된 중복성",
    },
    "ar": {
      "standard": "قياسي",
      "standardIa": "قياسي – وصول غير متكرر",
      "onezoneIa": "منطقة واحدة – وصول غير متكرر",
      "intelligentTiering": "طبقات ذكية",
      "glacier": "Glacier – استرجاع مرن",
      "glacierIr": "Glacier – استرجاع فوري",
      "deepArchive": "Glacier – أرشيف عميق",
      "reducedRedundancy": "تكرار مخفّض",
    },
  };
}
