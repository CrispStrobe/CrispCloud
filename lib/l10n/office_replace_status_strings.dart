import 'dart:ui' show Locale;

/// A complete sentence so languages can order the count and verb naturally.
String officeReplaceStatus(Locale locale, int count) {
  switch (locale.languageCode) {
    case 'de':
      return '$count Vorkommen ersetzt.';
    case 'fr':
      return '$count ${count <= 1 ? 'occurrence remplacée' : 'occurrences remplacées'}.';
    case 'es':
      return 'Se ${count == 1 ? 'reemplazó' : 'reemplazaron'} $count ${count == 1 ? 'coincidencia' : 'coincidencias'}.';
    case 'pt':
      return '${count == 1 ? 'Foi substituída' : 'Foram substituídas'} $count ${count == 1 ? 'ocorrência' : 'ocorrências'}.';
    case 'zh':
      return '已替换 $count 处匹配项。';
    case 'ja':
      return '$count 件を置換しました。';
    case 'ko':
      return '$count개 항목을 바꿨습니다.';
    case 'ar':
      if (count == 0) return 'لم يتم استبدال أي نتيجة (0).';
      if (count == 1) return 'تم استبدال نتيجة واحدة (1).';
      if (count == 2) return 'تم استبدال نتيجتين (2).';
      final mod100 = count % 100;
      if (mod100 >= 3 && mod100 <= 10) return 'تم استبدال $count نتائج.';
      if (mod100 >= 11 && mod100 <= 99) return 'تم استبدال $count نتيجةً.';
      return 'تم استبدال $count نتيجة.';
    default:
      return 'Replaced $count ${count == 1 ? 'occurrence' : 'occurrences'}.';
  }
}
