import 'package:flutter/widgets.dart';

class StreamingViewStrings {
  StreamingViewStrings(BuildContext context)
      : language = Localizations.maybeLocaleOf(context)?.languageCode ?? 'en';
  final String language;
  String text(String key) => (_values[language] ?? _values['en']!)[key] ?? _values['en']![key]!;
  String indexed(int megabytes) => text('indexed').replaceAll('{n}', '$megabytes');
  static const Map<String, Map<String, String>> _values = {
    'en': {'indexed': '(indexed to {n} MB — use Hex mode for deeper offsets)', 'loading': '(loading…)'},
    'de': {'indexed': '(bis {n} MB indiziert — für spätere Positionen Hex-Modus verwenden)', 'loading': '(wird geladen…)'},
    'fr': {'indexed': '(indexé jusqu’à {n} Mo — utilisez le mode Hex pour les positions suivantes)', 'loading': '(chargement…)'},
    'es': {'indexed': '(indexado hasta {n} MB; usa el modo Hex para posiciones posteriores)', 'loading': '(cargando…)'},
    'pt': {'indexed': '(indexado até {n} MB — use o modo Hex para posições posteriores)', 'loading': '(a carregar…)'},
    'zh': {'indexed': '（已索引至 {n} MB；使用十六进制模式查看更后面的偏移量）', 'loading': '（正在加载…）'},
    'ja': {'indexed': '（{n} MB まで索引済み。それ以降は16進数モードを使用）', 'loading': '（読み込み中…）'},
    'ko': {'indexed': '({n}MB까지 색인됨 — 이후 위치는 16진수 모드 사용)', 'loading': '(불러오는 중…)'},
    'ar': {'indexed': '(تمت الفهرسة حتى {n} ميغابايت — استخدم الوضع السداسي عشري للإزاحات الأبعد)', 'loading': '(جارٍ التحميل…)'},
  };
}
