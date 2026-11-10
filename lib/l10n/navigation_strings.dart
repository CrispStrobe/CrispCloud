import 'package:flutter/widgets.dart';

class NavigationStrings {
  NavigationStrings(BuildContext context)
      : language = Localizations.maybeLocaleOf(context)?.languageCode ?? 'en';
  final String language;

  String text(String key) =>
      (_messages[language] ?? _messages['en']!)[key] ?? _messages['en']![key] ?? key;

  String failure(Object error) => text('failed').replaceAll('{error}', '$error');

  static const _messages = {
    'en': {
      'history': 'Location history',
      'reopen': 'Reopen closed tab',
      'unavailable': 'Reconnect the original storage for this location.',
      'older': 'This older location does not identify its storage. Open it from its original source.',
      'failed': 'Could not open the saved location: {error}',
    },
    'de': {
      'history': 'Ortsverlauf',
      'reopen': 'Geschlossenen Tab wieder öffnen',
      'unavailable': 'Verbinden Sie den ursprünglichen Speicher für diesen Ort erneut.',
      'older': 'Dieser ältere Ort enthält keine Speicherzuordnung. Öffnen Sie ihn über seine ursprüngliche Quelle.',
      'failed': 'Der gespeicherte Ort konnte nicht geöffnet werden: {error}',
    },
    'fr': {
      'history': 'Historique des emplacements',
      'reopen': 'Rouvrir l’onglet fermé',
      'unavailable': 'Reconnectez le stockage d’origine de cet emplacement.',
      'older': 'Cet ancien emplacement n’identifie pas son stockage. Ouvrez-le depuis sa source d’origine.',
      'failed': 'Impossible d’ouvrir l’emplacement enregistré : {error}',
    },
    'es': {
      'history': 'Historial de ubicaciones',
      'reopen': 'Reabrir pestaña cerrada',
      'unavailable': 'Vuelve a conectar el almacenamiento original de esta ubicación.',
      'older': 'Esta ubicación antigua no identifica su almacenamiento. Ábrela desde su origen.',
      'failed': 'No se pudo abrir la ubicación guardada: {error}',
    },
    'pt': {
      'history': 'Histórico de locais',
      'reopen': 'Reabrir separador fechado',
      'unavailable': 'Ligue novamente o armazenamento original deste local.',
      'older': 'Este local antigo não identifica o armazenamento. Abra-o a partir da origem.',
      'failed': 'Não foi possível abrir o local guardado: {error}',
    },
    'zh': {
      'history': '位置历史记录',
      'reopen': '重新打开已关闭的标签页',
      'unavailable': '请重新连接此位置的原始存储。',
      'older': '此旧位置未标明其存储。请从原始来源打开。',
      'failed': '无法打开已保存的位置：{error}',
    },
    'ja': {
      'history': '場所の履歴',
      'reopen': '閉じたタブを開き直す',
      'unavailable': 'この場所の元のストレージに再接続してください。',
      'older': 'この古い場所にはストレージ情報がありません。元のソースから開いてください。',
      'failed': '保存した場所を開けませんでした: {error}',
    },
    'ko': {
      'history': '위치 기록',
      'reopen': '닫은 탭 다시 열기',
      'unavailable': '이 위치의 원래 저장소를 다시 연결하세요.',
      'older': '이 이전 위치에는 저장소 정보가 없습니다. 원래 소스에서 여세요.',
      'failed': '저장된 위치를 열 수 없습니다: {error}',
    },
    'ar': {
      'history': 'سجل المواقع',
      'reopen': 'إعادة فتح علامة التبويب المغلقة',
      'unavailable': 'أعد توصيل وحدة التخزين الأصلية لهذا الموقع.',
      'older': 'هذا الموقع القديم لا يحدد وحدة التخزين الخاصة به. افتحه من مصدره الأصلي.',
      'failed': 'تعذر فتح الموقع المحفوظ: {error}',
    },
  };
}
