import 'dart:ui' show Locale;

/// Tray strings can be used without a widget tree or app providers.
class TrayStrings {
  TrayStrings(Locale? locale) : language = locale?.languageCode ?? 'en';
  final String language;
  String text(String key, [Map<String, Object> values = const {}]) {
    var result = (_values[language] ?? _values['en']!)[key] ?? _values['en']![key]!;
    values.forEach((key, value) => result = result.replaceAll('{$key}', value.toString()));
    return result;
  }
  static const Map<String, Map<String, String>> _values = {
    "en": {"manager": "Cloud File Manager", "show": "Show CrispCloud", "syncAll": "Sync All", "quit": "Quit", "syncing": "Syncing{pair}...", "last": "Last sync: {up} up, {down} down", "pairs": "Sync pairs: {count}"},
    "de": {"manager": "Cloud-Dateimanager", "show": "CrispCloud anzeigen", "syncAll": "Alles synchronisieren", "quit": "Beenden", "syncing": "Synchronisierung{pair} läuft...", "last": "Letzte Synchronisierung: {up} hoch, {down} herunter", "pairs": "Synchronisierungspaare: {count}"},
    "fr": {"manager": "Gestionnaire de fichiers cloud", "show": "Afficher CrispCloud", "syncAll": "Tout synchroniser", "quit": "Quitter", "syncing": "Synchronisation{pair}...", "last": "Dernière synchronisation : {up} envoyés, {down} téléchargés", "pairs": "Paires de synchronisation : {count}"},
    "es": {"manager": "Gestor de archivos en la nube", "show": "Mostrar CrispCloud", "syncAll": "Sincronizar todo", "quit": "Salir", "syncing": "Sincronizando{pair}...", "last": "Última sincronización: {up} subidos, {down} descargados", "pairs": "Pares de sincronización: {count}"},
    "pt": {"manager": "Gestor de ficheiros na nuvem", "show": "Mostrar CrispCloud", "syncAll": "Sincronizar tudo", "quit": "Sair", "syncing": "A sincronizar{pair}...", "last": "Última sincronização: {up} carregados, {down} transferidos", "pairs": "Pares de sincronização: {count}"},
    "zh": {"manager": "云文件管理器", "show": "显示 CrispCloud", "syncAll": "全部同步", "quit": "退出", "syncing": "正在同步{pair}...", "last": "上次同步：上传 {up}，下载 {down}", "pairs": "同步对：{count}"},
    "ja": {"manager": "クラウドファイルマネージャー", "show": "CrispCloud を表示", "syncAll": "すべて同期", "quit": "終了", "syncing": "同期中{pair}...", "last": "前回の同期: アップロード {up}、ダウンロード {down}", "pairs": "同期ペア: {count}"},
    "ko": {"manager": "클라우드 파일 관리자", "show": "CrispCloud 표시", "syncAll": "모두 동기화", "quit": "종료", "syncing": "동기화 중{pair}...", "last": "마지막 동기화: 업로드 {up}, 다운로드 {down}", "pairs": "동기화 쌍: {count}"},
    "ar": {"manager": "مدير الملفات السحابية", "show": "إظهار CrispCloud", "syncAll": "مزامنة الكل", "quit": "إنهاء", "syncing": "جارٍ المزامنة{pair}...", "last": "آخر مزامنة: رفع {up}، تنزيل {down}", "pairs": "أزواج المزامنة: {count}"},
  };
}
