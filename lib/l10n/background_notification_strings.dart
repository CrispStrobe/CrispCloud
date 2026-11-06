import 'dart:ui' show Locale, PlatformDispatcher;

import '../services/locale_preference.dart';
import '../services/sync_engine.dart';
import 'provider_operation_strings.dart';

/// Notification text independent of the widget tree and foreground isolate.
class BackgroundNotificationStrings {
  BackgroundNotificationStrings(Locale? locale)
      : language = locale?.languageCode ?? 'en';
  factory BackgroundNotificationStrings.system() {
    try {
      return BackgroundNotificationStrings(PlatformDispatcher.instance.locale);
    } catch (_) {
      return BackgroundNotificationStrings(null);
    }
  }
  static Future<BackgroundNotificationStrings> fromPreferences() async {
    final locale = await LocalePreference.read(refresh: true);
    return locale == null
        ? BackgroundNotificationStrings.system()
        : BackgroundNotificationStrings(locale);
  }

  final String language;
  String text(String key) =>
      (_values[language] ?? _values['en']!)[key] ?? _values['en']![key]!;
  String failure(Object error) =>
      text('failure').replaceAll('{error}', localizedProviderErrorForLanguage(language, error));
  String failureDetail(SyncFailureDetail detail) {
    if (!detail.providerUnavailable) {
      final cause = detail.cause;
      return '${detail.location}: ${cause == null ? '' : localizedProviderErrorForLanguage(language, cause)}';
    }
    final values = {'pair': detail.location, 'provider': detail.provider ?? ''};
    return text('unavailable').replaceAllMapped(RegExp(r'\{([A-Za-z]+)\}'),
        (match) => values[match.group(1)] ?? match.group(0)!);
  }

  String body(
      {required int conflicts,
      required int errors,
      required List<String> details}) {
    final parts = <String>[];
    if (conflicts > 0)
      parts.add(text(conflicts == 1 ? 'conflictOne' : 'conflictOther')
          .replaceAll('{n}', '$conflicts'));
    if (errors > 0)
      parts.add(text(errors == 1 ? 'errorOne' : 'errorOther')
          .replaceAll('{n}', '$errors'));
    if (details.isNotEmpty) parts.add(details.first);
    return parts.join(' — ');
  }

  static const Map<String, Map<String, String>> _values = {
    "en": {
      "unavailable": "{pair}: Background connection unavailable for {provider}",
      "title": "CrispCloud Sync",
      "errorTitle": "CrispCloud Sync Error",
      "channel": "Sync Notifications",
      "failure": "Background sync failed: {error}",
      "conflictOne": "{n} conflict",
      "conflictOther": "{n} conflicts",
      "errorOne": "{n} error",
      "errorOther": "{n} errors"
    },
    "de": {
      "unavailable":
          "{pair}: Hintergrundverbindung für {provider} nicht verfügbar",
      "title": "CrispCloud-Synchronisierung",
      "errorTitle": "CrispCloud-Synchronisierungsfehler",
      "channel": "Synchronisierungsbenachrichtigungen",
      "failure": "Hintergrundsynchronisierung fehlgeschlagen: {error}",
      "conflictOne": "{n} Konflikt",
      "conflictOther": "{n} Konflikte",
      "errorOne": "{n} Fehler",
      "errorOther": "{n} Fehler"
    },
    "fr": {
      "unavailable":
          "{pair} : connexion en arrière-plan indisponible pour {provider}",
      "title": "Synchronisation CrispCloud",
      "errorTitle": "Erreur de synchronisation CrispCloud",
      "channel": "Notifications de synchronisation",
      "failure": "Échec de la synchronisation en arrière-plan : {error}",
      "conflictOne": "{n} conflit",
      "conflictOther": "{n} conflits",
      "errorOne": "{n} erreur",
      "errorOther": "{n} erreurs"
    },
    "es": {
      "unavailable":
          "{pair}: conexión en segundo plano no disponible para {provider}",
      "title": "Sincronización de CrispCloud",
      "errorTitle": "Error de sincronización de CrispCloud",
      "channel": "Notificaciones de sincronización",
      "failure": "Error de sincronización en segundo plano: {error}",
      "conflictOne": "{n} conflicto",
      "conflictOther": "{n} conflictos",
      "errorOne": "{n} error",
      "errorOther": "{n} errores"
    },
    "pt": {
      "unavailable":
          "{pair}: ligação em segundo plano indisponível para {provider}",
      "title": "Sincronização do CrispCloud",
      "errorTitle": "Erro de sincronização do CrispCloud",
      "channel": "Notificações de sincronização",
      "failure": "Falha na sincronização em segundo plano: {error}",
      "conflictOne": "{n} conflito",
      "conflictOther": "{n} conflitos",
      "errorOne": "{n} erro",
      "errorOther": "{n} erros"
    },
    "zh": {
      "unavailable": "{pair}：{provider} 的后台连接不可用",
      "title": "CrispCloud 同步",
      "errorTitle": "CrispCloud 同步错误",
      "channel": "同步通知",
      "failure": "后台同步失败：{error}",
      "conflictOne": "冲突：{n}",
      "conflictOther": "冲突：{n}",
      "errorOne": "错误：{n}",
      "errorOther": "错误：{n}"
    },
    "ja": {
      "unavailable": "{pair}: {provider} のバックグラウンド接続を利用できません",
      "title": "CrispCloud の同期",
      "errorTitle": "CrispCloud 同期エラー",
      "channel": "同期通知",
      "failure": "バックグラウンド同期に失敗しました: {error}",
      "conflictOne": "競合: {n} 件",
      "conflictOther": "競合: {n} 件",
      "errorOne": "エラー: {n} 件",
      "errorOther": "エラー: {n} 件"
    },
    "ko": {
      "unavailable": "{pair}: {provider} 백그라운드 연결을 사용할 수 없습니다",
      "title": "CrispCloud 동기화",
      "errorTitle": "CrispCloud 동기화 오류",
      "channel": "동기화 알림",
      "failure": "백그라운드 동기화 실패: {error}",
      "conflictOne": "충돌: {n}개",
      "conflictOther": "충돌: {n}개",
      "errorOne": "오류: {n}개",
      "errorOther": "오류: {n}개"
    },
    "ar": {
      "unavailable": "{pair}: اتصال الخلفية غير متاح لـ {provider}",
      "title": "مزامنة CrispCloud",
      "errorTitle": "خطأ مزامنة CrispCloud",
      "channel": "إشعارات المزامنة",
      "failure": "فشلت المزامنة في الخلفية: {error}",
      "conflictOne": "التعارضات: {n}",
      "conflictOther": "التعارضات: {n}",
      "errorOne": "الأخطاء: {n}",
      "errorOther": "الأخطاء: {n}"
    },
  };
}
