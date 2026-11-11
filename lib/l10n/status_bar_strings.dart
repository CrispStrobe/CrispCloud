import 'package:flutter/widgets.dart';

class StatusBarStrings {
  StatusBarStrings(BuildContext context)
    : _language = Localizations.maybeLocaleOf(context)?.languageCode ?? 'en';

  @visibleForTesting
  StatusBarStrings.forLanguage(this._language);
  final String _language;

  String text(String key) => _values[_language]?[key] ?? _values['en']![key]!;
  String value(String key, String value) =>
      text(key).replaceAll('{value}', value);

  @visibleForTesting
  static Map<String, Map<String, String>> get translations => _values;

  static const _values = <String, Map<String, String>>{
    'en': {
      'quotaLoading': 'Loading storage usage…',
      'quotaUnavailable': 'Storage usage unavailable',
      'quotaFailed': 'Could not load storage usage. Retry.',
      'quotaRefresh': 'Refresh storage usage',
      'quotaUsed': '{value} used',
      'quotaTotal': '{value} total',
      'unavailable': 'Unavailable',
      'flatView': 'Flat view',
    },
    'de': {
      'quotaLoading': 'Speicherbelegung wird geladen…',
      'quotaUnavailable': 'Speicherbelegung nicht verfügbar',
      'quotaFailed':
          'Speicherbelegung konnte nicht geladen werden. Erneut versuchen.',
      'quotaRefresh': 'Speicherbelegung aktualisieren',
      'quotaUsed': '{value} belegt',
      'quotaTotal': '{value} insgesamt',
      'unavailable': 'Nicht verfügbar',
      'flatView': 'Flache Ansicht',
    },
    'fr': {
      'quotaLoading': 'Chargement de l’espace utilisé…',
      'quotaUnavailable': 'Utilisation du stockage indisponible',
      'quotaFailed':
          'Impossible de charger l’utilisation du stockage. Réessayer.',
      'quotaRefresh': 'Actualiser l’utilisation du stockage',
      'quotaUsed': '{value} utilisés',
      'quotaTotal': '{value} au total',
      'unavailable': 'Indisponible',
      'flatView': 'Vue à plat',
    },
    'es': {
      'quotaLoading': 'Cargando uso del almacenamiento…',
      'quotaUnavailable': 'Uso del almacenamiento no disponible',
      'quotaFailed': 'No se pudo cargar el uso del almacenamiento. Reintentar.',
      'quotaRefresh': 'Actualizar uso del almacenamiento',
      'quotaUsed': '{value} usados',
      'quotaTotal': '{value} en total',
      'unavailable': 'No disponible',
      'flatView': 'Vista plana',
    },
    'pt': {
      'quotaLoading': 'A carregar utilização do armazenamento…',
      'quotaUnavailable': 'Utilização do armazenamento indisponível',
      'quotaFailed': 'Não foi possível carregar a utilização do armazenamento. Tentar novamente.',
      'quotaRefresh': 'Atualizar utilização do armazenamento',
      'quotaUsed': '{value} utilizados',
      'quotaTotal': '{value} no total',
      'unavailable': 'Indisponível',
      'flatView': 'Vista plana',
    },
    'zh': {
      'quotaLoading': '正在加载存储用量…',
      'quotaUnavailable': '存储用量不可用',
      'quotaFailed': '无法加载存储用量。重试。',
      'quotaRefresh': '刷新存储用量',
      'quotaUsed': '已使用 {value}',
      'quotaTotal': '共 {value}',
      'unavailable': '不可用',
      'flatView': '平面视图',
    },
    'ja': {
      'quotaLoading': 'ストレージ使用量を読み込み中…',
      'quotaUnavailable': 'ストレージ使用量を取得できません',
      'quotaFailed': 'ストレージ使用量を読み込めませんでした。再試行します。',
      'quotaRefresh': 'ストレージ使用量を更新',
      'quotaUsed': '{value} 使用中',
      'quotaTotal': '合計 {value}',
      'unavailable': '利用できません',
      'flatView': 'フラット表示',
    },
    'ko': {
      'quotaLoading': '저장소 사용량 불러오는 중…',
      'quotaUnavailable': '저장소 사용량을 사용할 수 없음',
      'quotaFailed': '저장소 사용량을 불러오지 못했습니다. 다시 시도하세요.',
      'quotaRefresh': '저장소 사용량 새로고침',
      'quotaUsed': '{value} 사용 중',
      'quotaTotal': '총 {value}',
      'unavailable': '사용할 수 없음',
      'flatView': '평면 보기',
    },
    'ar': {
      'quotaLoading': 'جارٍ تحميل استخدام التخزين…',
      'quotaUnavailable': 'استخدام التخزين غير متاح',
      'quotaFailed': 'تعذر تحميل استخدام التخزين. أعد المحاولة.',
      'quotaRefresh': 'تحديث استخدام التخزين',
      'quotaUsed': '{value} مستخدم',
      'quotaTotal': '{value} إجمالًا',
      'unavailable': 'غير متاح',
      'flatView': 'عرض مسطح',
    },
  };
}
