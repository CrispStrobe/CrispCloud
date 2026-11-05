import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/src/editor_reports/report_template_strings.dart';
import 'package:quds_office_engine/quds_reports.dart';

Map<String, Object?> _sampleData() => {};

void main() {
  test('built-in template categories, families and languages are localized',
      () {
    // The deprecated programmatic catalog shares the IDs of bundled assets.
    // ignore: deprecated_member_use
    const templates = ReportTemplates.all;
    const english = ReportTemplateStrings('en');
    for (final lang in ['de', 'fr', 'es', 'pt', 'zh', 'ja', 'ko', 'ar']) {
      final strings = ReportTemplateStrings(lang);
      for (final category in ReportTemplateCategory.values) {
        expect(strings.category(category), isNot(english.category(category)),
            reason: '$lang ${category.name}');
      }
      for (final template in templates) {
        expect(strings.family(template, bundled: true),
            isNot(english.family(template, bundled: true)),
            reason: '$lang ${template.family}');
        expect(strings.title(template, bundled: true),
            contains(strings.language(template.language)));
      }
      for (final language in ReportTemplateLanguage.values) {
        expect(strings.language(language), isNot(english.language(language)),
            reason: '$lang ${language.name}');
      }
    }
  });

  test('custom template names survive even when IDs match built-in templates',
      () {
    const custom = ReportTemplateInfo(
      id: 'feature_showcase_en',
      family: 'feature_showcase',
      title: 'User title {0}',
      titleAr: 'عنوان',
      description: '',
      descriptionAr: '',
      category: ReportTemplateCategory.sales,
      rtl: false,
      xml: '',
      sampleData: _sampleData,
    );
    const strings = ReportTemplateStrings('de');
    expect(strings.family(custom, bundled: false), custom.familyTitle);
    expect(strings.title(custom, bundled: false), 'User title {0}');
  });
}
