import 'package:intl/intl.dart';

/// Chooses the plural form of a count for the editor's UI languages.
///
/// English and German use one/other; Arabic uses zero/one/two/few/many/other.
/// Each form receives the count and returns the full phrase, so the number can
/// sit where the language puts it (or be omitted, as in Arabic "نتيجتان").
/// Arabic takes precedence over [german]; German without its forms falls back
/// to English.
String officePlural(
  int count, {
  required bool arabic,
  bool german = false,
  required String Function(int) one,
  required String Function(int) other,
  String Function(int)? germanOne,
  String Function(int)? germanOther,
  String Function(int)? arabicZero,
  String Function(int)? arabicOne,
  String Function(int)? arabicTwo,
  String Function(int)? arabicFew,
  String Function(int)? arabicMany,
  String Function(int)? arabicOther,
}) {
  if (!arabic && german && germanOne != null && germanOther != null) {
    return Intl.plural(
      count,
      one: germanOne(count),
      other: germanOther(count),
      locale: 'de',
    );
  }
  if (!arabic) {
    return Intl.plural(
      count,
      one: one(count),
      other: other(count),
      locale: 'en',
    );
  }
  final fallback = arabicOther ?? other;
  return Intl.plural(
    count,
    zero: (arabicZero ?? fallback)(count),
    one: (arabicOne ?? fallback)(count),
    two: (arabicTwo ?? fallback)(count),
    few: (arabicFew ?? fallback)(count),
    many: (arabicMany ?? fallback)(count),
    other: fallback(count),
    locale: 'ar',
  );
}

/// "3 findings" / "3 Hinweise" / "٣ نتائج".
String officeFindings(int count, {bool arabic = false, bool german = false}) =>
    officePlural(
      count,
      arabic: arabic,
      german: german,
      one: (_) => '1 finding',
      other: (n) => '$n findings',
      germanOne: (_) => '1 Hinweis',
      germanOther: (n) => '$n Hinweise',
      arabicZero: (_) => 'لا توجد نتائج',
      arabicOne: (_) => 'نتيجة واحدة',
      arabicTwo: (_) => 'نتيجتان',
      arabicFew: (n) => '$n نتائج',
      arabicOther: (n) => '$n نتيجة',
    );

/// "3 issues" / "3 Hinweise" / "٣ ملاحظات".
String officeIssues(
  int count, {
  bool arabic = false,
  bool german = false,
  bool writing = false,
}) => officePlural(
  count,
  arabic: arabic,
  german: german,
  one: (_) => writing ? '1 writing issue' : '1 issue',
  other: (n) => writing ? '$n writing issues' : '$n issues',
  germanOne: (_) => writing ? '1 Schreibhinweis' : '1 Hinweis',
  germanOther: (n) => writing ? '$n Schreibhinweise' : '$n Hinweise',
  arabicZero: (_) => 'لا توجد ملاحظات',
  arabicOne: (_) => 'ملاحظة واحدة',
  arabicTwo: (_) => 'ملاحظتان',
  arabicFew: (n) => '$n ملاحظات',
  arabicOther: (n) => '$n ملاحظة',
);

/// "3 changes" / "3 Änderungen" / "٣ تغييرات".
String officeChanges(int count, {bool arabic = false, bool german = false}) =>
    officePlural(
      count,
      arabic: arabic,
      german: german,
      one: (_) => '1 change',
      other: (n) => '$n changes',
      germanOne: (_) => '1 Änderung',
      germanOther: (n) => '$n Änderungen',
      arabicZero: (_) => 'لا توجد تغييرات',
      arabicOne: (_) => 'تغيير واحد',
      arabicTwo: (_) => 'تغييران',
      arabicFew: (n) => '$n تغييرات',
      arabicMany: (n) => '$n تغييرًا',
      arabicOther: (n) => '$n تغيير',
    );

/// "3 paragraphs" / "3 Absätze" / "٣ فقرات".
String officeParagraphs(
  int count, {
  bool arabic = false,
  bool german = false,
}) => officePlural(
  count,
  arabic: arabic,
  german: german,
  one: (_) => '1 paragraph',
  other: (n) => '$n paragraphs',
  germanOne: (_) => '1 Absatz',
  germanOther: (n) => '$n Absätze',
  arabicZero: (_) => 'لا توجد فقرات',
  arabicOne: (_) => 'فقرة واحدة',
  arabicTwo: (_) => 'فقرتان',
  arabicFew: (n) => '$n فقرات',
  arabicOther: (n) => '$n فقرة',
);

/// English count phrase with a regular or given plural ("1 insertion").
String officeCount(int count, String singular, [String? plural]) =>
    officePlural(
      count,
      arabic: false,
      one: (_) => '1 $singular',
      other: (n) => '$n ${plural ?? '${singular}s'}',
    );
