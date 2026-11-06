import 'package:flutter/widgets.dart';

/// Presentation of panel filtering and type-ahead results.
class QuickSearchStatusStrings {
  QuickSearchStatusStrings(BuildContext context)
    : language = Localizations.maybeLocaleOf(context)?.languageCode ?? 'en';
  final String language;

  String status({
    required String query,
    required bool isTypeahead,
    required bool isQuickFilterActive,
    required int matchPosition,
    required int matchCount,
  }) {
    final values = _values[language] ?? _values['en']!;
    final label =
        values[!isTypeahead || isQuickFilterActive ? 'filter' : 'find']!;
    // Substitute the query last so text resembling a placeholder remains literal.
    final result = isTypeahead
        ? '  ${matchCount > 0 ? '$matchPosition/$matchCount' : values['noMatches']!}'
        : '';
    return label.replaceAll('{query}', query) + result;
  }

  static const Map<String, Map<String, String>> _values = {
    "en": {
      "filter": "Filter: \"{query}\"",
      "find": "Find: \"{query}\"",
      "noMatches": "no matches",
    },
    "de": {
      "filter": "Filter: „{query}“",
      "find": "Suchen: „{query}“",
      "noMatches": "keine Treffer",
    },
    "fr": {
      "filter": "Filtre : « {query} »",
      "find": "Recherche : « {query} »",
      "noMatches": "aucun résultat",
    },
    "es": {
      "filter": "Filtro: «{query}»",
      "find": "Buscar: «{query}»",
      "noMatches": "sin coincidencias",
    },
    "pt": {
      "filter": "Filtro: «{query}»",
      "find": "Pesquisar: «{query}»",
      "noMatches": "sem ocorrências",
    },
    "zh": {
      "filter": "筛选：“{query}”",
      "find": "查找：“{query}”",
      "noMatches": "无匹配项",
    },
    "ja": {
      "filter": "フィルター:「{query}」",
      "find": "検索:「{query}」",
      "noMatches": "一致なし",
    },
    "ko": {
      "filter": "필터: “{query}”",
      "find": "찾기: “{query}”",
      "noMatches": "일치 항목 없음",
    },
    "ar": {
      "filter": "تصفية: «{query}»",
      "find": "بحث: «{query}»",
      "noMatches": "لا توجد تطابقات",
    },
  };
}
