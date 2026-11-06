import '../services/auth_sync_notice.dart';
import 'provider_operation_strings.dart';

String localizedAuthSyncNotice(String language, AuthSyncNotice notice) {
  final template = (_messages[language] ?? _messages['en']!)[notice.code.name]!;
  final values = <String, String>{
    'pair': notice.pairName ?? '',
    'error': notice.cause == null
        ? ''
        : localizedProviderErrorForLanguage(language, notice.cause!),
  };
  // Replace template tokens in one pass; names and diagnostics remain literal.
  return template.replaceAllMapped(
    RegExp(r'\{(pair|error)\}'),
    (match) => values[match[1]]!,
  );
}

const Map<String, Map<String, String>> _messages = {
  "en": {
    "sessionExpired": "Session expired. Please log in again.",
    "syncPair": "Sync failed for \"{pair}\": {error}",
    "sync": "Sync failed: {error}",
    "download": "Failed to download file: {error}",
    "freeSpace": "Failed to free up space: {error}",
    "downloadAll": "Failed to download all files: {error}",
  },
  "de": {
    "sessionExpired": "Sitzung abgelaufen. Bitte melden Sie sich erneut an.",
    "syncPair": "Synchronisierung für „{pair}“ fehlgeschlagen: {error}",
    "sync": "Synchronisierung fehlgeschlagen: {error}",
    "download": "Datei konnte nicht heruntergeladen werden: {error}",
    "freeSpace": "Speicherplatz konnte nicht freigegeben werden: {error}",
    "downloadAll": "Nicht alle Dateien konnten heruntergeladen werden: {error}",
  },
  "fr": {
    "sessionExpired": "La session a expiré. Veuillez vous reconnecter.",
    "syncPair": "Échec de la synchronisation de « {pair} » : {error}",
    "sync": "Échec de la synchronisation : {error}",
    "download": "Impossible de télécharger le fichier : {error}",
    "freeSpace": "Impossible de libérer de l’espace : {error}",
    "downloadAll": "Impossible de télécharger tous les fichiers : {error}",
  },
  "es": {
    "sessionExpired": "La sesión ha caducado. Vuelve a iniciar sesión.",
    "syncPair": "Error de sincronización de «{pair}»: {error}",
    "sync": "Error de sincronización: {error}",
    "download": "No se pudo descargar el archivo: {error}",
    "freeSpace": "No se pudo liberar espacio: {error}",
    "downloadAll": "No se pudieron descargar todos los archivos: {error}",
  },
  "pt": {
    "sessionExpired": "A sessão expirou. Inicie sessão novamente.",
    "syncPair": "Falha na sincronização de «{pair}»: {error}",
    "sync": "Falha na sincronização: {error}",
    "download": "Não foi possível transferir o ficheiro: {error}",
    "freeSpace": "Não foi possível libertar espaço: {error}",
    "downloadAll": "Não foi possível transferir todos os ficheiros: {error}",
  },
  "zh": {
    "sessionExpired": "会话已过期。请重新登录。",
    "syncPair": "“{pair}”同步失败：{error}",
    "sync": "同步失败：{error}",
    "download": "无法下载文件：{error}",
    "freeSpace": "无法释放空间：{error}",
    "downloadAll": "无法下载所有文件：{error}",
  },
  "ja": {
    "sessionExpired": "セッションの有効期限が切れました。再度ログインしてください。",
    "syncPair": "「{pair}」の同期に失敗しました: {error}",
    "sync": "同期に失敗しました: {error}",
    "download": "ファイルをダウンロードできませんでした: {error}",
    "freeSpace": "空き容量を確保できませんでした: {error}",
    "downloadAll": "すべてのファイルをダウンロードできませんでした: {error}",
  },
  "ko": {
    "sessionExpired": "세션이 만료되었습니다. 다시 로그인하세요.",
    "syncPair": "“{pair}” 동기화 실패: {error}",
    "sync": "동기화 실패: {error}",
    "download": "파일 다운로드 실패: {error}",
    "freeSpace": "공간 확보 실패: {error}",
    "downloadAll": "모든 파일 다운로드 실패: {error}",
  },
  "ar": {
    "sessionExpired": "انتهت الجلسة. يُرجى تسجيل الدخول مجدداً.",
    "syncPair": "فشلت مزامنة «{pair}»: {error}",
    "sync": "فشلت المزامنة: {error}",
    "download": "تعذّر تنزيل الملف: {error}",
    "freeSpace": "تعذّر إخلاء مساحة: {error}",
    "downloadAll": "تعذّر تنزيل جميع الملفات: {error}",
  },
};
