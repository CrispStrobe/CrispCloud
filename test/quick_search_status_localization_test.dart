import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/quick_search_status_strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'search status distinguishes filtering and navigation in every locale',
    (tester) async {
      const expectedLabels = {
        'en': ['Filter: "', 'Find: "', 'no matches'],
        'de': ['Filter: „', 'Suchen: „', 'keine Treffer'],
        'fr': ['Filtre : « ', 'Recherche : « ', 'aucun résultat'],
        'es': ['Filtro: «', 'Buscar: «', 'sin coincidencias'],
        'pt': ['Filtro: «', 'Pesquisar: «', 'sem ocorrências'],
        'zh': ['筛选：“', '查找：“', '无匹配项'],
        'ja': ['フィルター:「', '検索:「', '一致なし'],
        'ko': ['필터: “', '찾기: “', '일치 항목 없음'],
        'ar': ['تصفية: «', 'بحث: «', 'لا توجد تطابقات'],
      };
      final noMatchLabels = <String>{};
      for (final locale in AppLocalizations.supportedLocales) {
        late QuickSearchStatusStrings strings;
        await tester.pumpWidget(
          MaterialApp(
            locale: locale,
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            home: Builder(
              builder: (context) {
                strings = QuickSearchStatusStrings(context);
                return const SizedBox.shrink();
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        String status(bool typeahead, bool quickFilter, int count) =>
            strings.status(
              query: '報告 {query} "*.pdf"',
              isTypeahead: typeahead,
              isQuickFilterActive: quickFilter,
              matchPosition: 2,
              matchCount: count,
            );
        final filter = status(false, false, 4);
        final find = status(true, false, 4);
        expect(filter, contains('報告 {query} "*.pdf"'));
        expect(filter, isNot(contains('2/4')));
        expect(find, endsWith('  2/4'));
        expect(find, isNot('$filter  2/4'));
        expect(status(true, true, 4), '$filter  2/4');
        final noMatches = status(true, false, 0);
        expect(noMatches, isNot(contains('2/0')));
        expect(noMatches, contains('報告 {query} "*.pdf"'));
        noMatchLabels.add(noMatches);
        final labels = expectedLabels[locale.languageCode]!;
        expect(filter, startsWith(labels[0]));
        expect(find, startsWith(labels[1]));
        expect(noMatches, endsWith('  ${labels[2]}'));
      }
      expect(noMatchLabels, hasLength(9));
    },
  );

  testWidgets(
    'unsupported locale uses English fallback without dropping query',
    (tester) async {
      late String status;
      await tester.pumpWidget(
        Localizations(
          locale: const Locale('xx'),
          delegates: const [DefaultWidgetsLocalizations.delegate],
          child: Builder(
            builder: (context) {
              status = QuickSearchStatusStrings(context).status(
                query: 'notes',
                isTypeahead: true,
                isQuickFilterActive: false,
                matchPosition: 0,
                matchCount: 0,
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(status, 'Find: "notes"  no matches');
    },
  );
}
