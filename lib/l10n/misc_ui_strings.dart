import 'package:flutter/widgets.dart';

class MiscUiStrings {
  MiscUiStrings(BuildContext context) : language = Localizations.maybeLocaleOf(context)?.languageCode ?? 'en';
  final String language;
  String text(String key) => (_values[language] ?? _values['en']!)[key] ?? _values['en']![key]!;
  String privacyLevel(int score) => text(score >= 90 ? 'excellent' : score >= 70 ? 'good' : score >= 50 ? 'fair' : score >= 30 ? 'low' : 'poor');
  static const Map<String, Map<String, String>> _values = {
    "en": {"privacy": "Privacy", "excellent": "Excellent", "good": "Good", "fair": "Fair", "low": "Low", "poor": "Poor", "back": "Navigate back", "forward": "Navigate forward", "home": "Home", "bookmark": "Toggle bookmark", "unknown": "Unknown", "none": "None", "version": "Version", "build": "build"},
    "de": {"privacy": "Datenschutz", "excellent": "Ausgezeichnet", "good": "Gut", "fair": "Mittel", "low": "Niedrig", "poor": "Schlecht", "back": "Zurück", "forward": "Vorwärts", "home": "Persönlicher Ordner", "bookmark": "Lesezeichen umschalten", "unknown": "Unbekannt", "none": "Keine", "version": "Version", "build": "Build"},
    "fr": {"privacy": "Confidentialité", "excellent": "Excellent", "good": "Bon", "fair": "Moyen", "low": "Faible", "poor": "Médiocre", "back": "Retour", "forward": "Avancer", "home": "Dossier personnel", "bookmark": "Activer ou désactiver le signet", "unknown": "Inconnu", "none": "Aucun", "version": "Version", "build": "build"},
    "es": {"privacy": "Privacidad", "excellent": "Excelente", "good": "Buena", "fair": "Aceptable", "low": "Baja", "poor": "Deficiente", "back": "Atrás", "forward": "Adelante", "home": "Carpeta personal", "bookmark": "Alternar marcador", "unknown": "Desconocido", "none": "Ninguno", "version": "Versión", "build": "compilación"},
    "pt": {"privacy": "Privacidade", "excellent": "Excelente", "good": "Boa", "fair": "Razoável", "low": "Baixa", "poor": "Fraca", "back": "Voltar", "forward": "Avançar", "home": "Pasta pessoal", "bookmark": "Alternar marcador", "unknown": "Desconhecido", "none": "Nenhum", "version": "Versão", "build": "compilação"},
    "zh": {"privacy": "隐私", "excellent": "优秀", "good": "良好", "fair": "一般", "low": "较低", "poor": "差", "back": "后退", "forward": "前进", "home": "主文件夹", "bookmark": "切换书签", "unknown": "未知", "none": "无", "version": "版本", "build": "构建"},
    "ja": {"privacy": "プライバシー", "excellent": "非常に良い", "good": "良い", "fair": "普通", "low": "低い", "poor": "不十分", "back": "戻る", "forward": "進む", "home": "ホーム", "bookmark": "ブックマークを切り替え", "unknown": "不明", "none": "なし", "version": "バージョン", "build": "ビルド"},
    "ko": {"privacy": "개인정보 보호", "excellent": "매우 좋음", "good": "좋음", "fair": "보통", "low": "낮음", "poor": "나쁨", "back": "뒤로", "forward": "앞으로", "home": "홈 폴더", "bookmark": "북마크 전환", "unknown": "알 수 없음", "none": "없음", "version": "버전", "build": "빌드"},
    "ar": {"privacy": "الخصوصية", "excellent": "ممتاز", "good": "جيد", "fair": "متوسط", "low": "منخفض", "poor": "ضعيف", "back": "رجوع", "forward": "تقدم", "home": "المجلد الرئيسي", "bookmark": "تبديل الإشارة المرجعية", "unknown": "غير معروف", "none": "لا شيء", "version": "الإصدار", "build": "البناء"},
  };
}
