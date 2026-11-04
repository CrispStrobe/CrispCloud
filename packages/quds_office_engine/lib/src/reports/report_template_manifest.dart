import 'dart:convert';

import 'report_templates.dart';

/// Catalog details of a template `.qrep`, saved in the package as
/// [entry] (`template.json`). A report file that carries one is offered as a
/// starting point ([ReportTemplateInfo.fromPackage]).
class ReportTemplateManifest {
  /// ReportTemplateManifest API. [family] defaults to [id], the Arabic texts
  /// to the English ones, and the family titles to the titles.
  const ReportTemplateManifest({
    required this.id,
    required this.title,
    String? titleAr,
    String? family,
    String? familyTitle,
    String? familyTitleAr,
    this.description = '',
    String? descriptionAr,
    this.category = ReportTemplateCategory.sales,
    this.language = ReportTemplateLanguage.english,
    this.order = 0,
  }) : titleAr = titleAr ?? title,
       family = family ?? id,
       familyTitle = familyTitle ?? title,
       familyTitleAr = familyTitleAr ?? titleAr ?? title,
       descriptionAr = descriptionAr ?? description;

  /// Package entry holding the manifest.
  static const String entry = 'template.json';

  /// Stable identifier (`sales_invoice_ar`); see [isValidId].
  final String id;

  /// Shared id of the language versions (`sales_invoice`).
  final String family;

  /// English title.
  final String title;

  /// Arabic title.
  final String titleAr;

  /// English title shared by the language versions.
  final String familyTitle;

  /// Arabic title shared by the language versions.
  final String familyTitleAr;

  /// English summary.
  final String description;

  /// Arabic summary.
  final String descriptionAr;

  /// Menu group.
  final ReportTemplateCategory category;

  /// Language the template prints in.
  final ReportTemplateLanguage language;

  /// Position within its category; lower comes first.
  final int order;

  static final RegExp _id = RegExp(r'^[A-Za-z0-9_\-]{1,64}$');

  /// Whether [id] is 1–64 ASCII letters, digits, `_` or `-`.
  static bool isValidId(String id) => _id.hasMatch(id);

  /// Pretty-printed JSON for [entry].
  String encode() =>
      const JsonEncoder.withIndent('  ').convert(<String, Object?>{
        'id': id,
        'family': family,
        'title': title,
        'titleAr': titleAr,
        'familyTitle': familyTitle,
        'familyTitleAr': familyTitleAr,
        'description': description,
        'descriptionAr': descriptionAr,
        'category': category.name,
        'language': language.code,
        'order': order,
      });

  /// Reads [encode]'s JSON. Missing optional fields take their defaults.
  ///
  /// Throws [FormatException] when the JSON is malformed, `id` is invalid,
  /// `title` is missing, or `category` / `language` are unknown.
  static ReportTemplateManifest decode(String json) {
    final Object? root = jsonDecode(json);
    if (root is! Map<String, Object?>) {
      throw const FormatException('Expected a JSON object');
    }
    String? text(String key) {
      final Object? v = root[key];
      if (v == null) {
        return null;
      }
      if (v is! String) {
        throw FormatException('"$key" must be a string');
      }
      return v;
    }

    final String id = text('id') ?? '';
    if (!isValidId(id)) {
      throw FormatException('Invalid template id "$id"');
    }
    final String? title = text('title');
    if (title == null || title.trim().isEmpty) {
      throw const FormatException('Missing "title"');
    }
    final String category =
        text('category') ?? ReportTemplateCategory.sales.name;
    final String language =
        text('language') ?? ReportTemplateLanguage.english.code;
    final Object? order = root['order'];
    if (order != null && order is! int) {
      throw const FormatException('"order" must be an integer');
    }
    return ReportTemplateManifest(
      id: id,
      title: title,
      titleAr: text('titleAr'),
      family: text('family'),
      familyTitle: text('familyTitle'),
      familyTitleAr: text('familyTitleAr'),
      description: text('description') ?? '',
      descriptionAr: text('descriptionAr'),
      category: ReportTemplateCategory.values.firstWhere(
        (ReportTemplateCategory c) => c.name == category,
        orElse: () => throw FormatException('Unknown category "$category"'),
      ),
      language: ReportTemplateLanguage.values.firstWhere(
        (ReportTemplateLanguage l) => l.code == language,
        orElse: () => throw FormatException('Unknown language "$language"'),
      ),
      order: order is int ? order : 0,
    );
  }
}
